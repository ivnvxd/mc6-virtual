import Observation

/// Why the engine stopped a trigger. The session disarms on any fault.
public enum EngineFault: Error, Sendable, Equatable {
    /// An Engage would put more than `Engine.maxDepth` frames on the stack.
    case depthLimit(pointer: String)
    /// A trigger tried to run more than `Engine.maxMessagesPerTrigger` messages.
    case budgetLimit(pointer: String)
    /// The sink threw while sending the message.
    case sendFailed(pointer: String, reason: String)

    /// The JSON Pointer of the message that caused the fault.
    public var pointer: String {
        switch self {
        case .depthLimit(let pointer), .budgetLimit(let pointer), .sendFailed(let pointer, _): pointer
        }
    }

    /// The fault in words, for the log and the window.
    public var reason: String {
        switch self {
        case .depthLimit: "depth limit"
        case .budgetLimit: "message budget limit"
        case .sendFailed(_, let reason): "send failed: \(reason)"
        }
    }
}

/// Runs switch actions of the backup (spec section 5.3).
///
/// One serial queue (U11): a trigger or an expression move waits until the running trigger ends, delays included.
/// Engage is call and return on a frame stack. Delay suspends through the scheduler.
@MainActor @Observable
public final class Engine {
    /// The most frames on the stack: the trigger and up to seven nested Engage calls.
    nonisolated public static let maxDepth = 8
    /// The most messages one trigger runs, nested calls included.
    nonisolated public static let maxMessagesPerTrigger = 512

    /// Settable inside the module so tests can prepare a state.
    public internal(set) var state: RuntimeState
    /// Bumped by `cancel()` and by every fault. Work from an older generation never runs.
    public private(set) var generation = 0
    /// Called after a fault has stopped the trigger and cleared the queue.
    public var onFault: ((EngineFault) -> Void)?
    /// Called for each MIDI Clock Tap, for the session log. U10: a tap sends no F8 clock.
    public var onClockTap: (() -> Void)?
    /// Called for each Utility BPM step, +1 or -1, for the shown tempo (V27).
    public var onTempoStep: ((Int) -> Void)?
    /// Called when a bank step starts On Enter Bank messages (V21). The session starts a new Sent group (V12).
    public var onStepEnter: (() -> Void)?
    /// Called after each successful send, with the pointer of the source message, for the session log.
    public var onOutput: ((_ bytes: [UInt8], _ ports: Ports, _ pointer: String) -> Void)?
    /// Called for each switch message the engine runs, before it runs. The sweep test reads it,
    /// because a sink cannot see messages without output, such as Bank Jump.
    var onExecute: ((Message) -> Void)?

    private struct Frame {
        /// The preset that acts: its position gates the messages, and Toggle Preset, Rename and colors change it.
        let address: PresetAddress
        /// The preset whose messages run. V26: in a Trigger Messages frame it differs from `address`.
        let source: PresetAddress
        /// The action that runs. Nil in a Trigger Messages frame, which runs its slots whatever their action and position.
        let action: Int?
        /// The slots that run; nil runs every slot. U07: the message scroll group of a Release. V26: the checked messages.
        var slots: Set<Int>?
        /// Index into the preset's non-empty messages, which are in slot order.
        var next = 0
        /// V25: the root frame of an On Enter Bank Engage. Its bank change applies when its stack empties.
        var fromEnter = false
    }

    /// V25: a bank change of a message, which waits for the end of its input.
    private enum BankChange {
        case jump(BankJumpTarget, enter: Bool)
        case step(up: Bool)
    }

    private enum Work {
        /// `token` names this one trigger, so a gesture can withdraw its own Press.
        case trigger(PresetAddress, action: Int, token: Int)
        case expression(input: Int, value: Int)
        case navigate(NavigationStep)
        /// V25: the end of an input. The pending bank change applies. V30: a Toggle Mode preset of the input toggles.
        case endInput(toggling: PresetAddress?)
    }

    /// The gesture recognizer reads the long-press time and the double-tap presets from it.
    let backup: Backup
    private let scheduler: any Scheduler
    private let sink: any MidiSink
    private var queue: [Work] = []
    /// V21: the On Enter Bank Engage calls of a bank change. They run before `queue`, as soon as no frame is on the stack.
    private var enterQueue: [(address: PresetAddress, action: Int)] = []
    private var frames: [Frame] = []
    private var executed = 0
    private var wakeup: Wakeup?
    private var nextToken = 0
    /// V25: the last bank change of the running input. One slot: the end of any input applies it.
    private var pendingBankChange: BankChange?

    public init(backup: Backup, scheduler: any Scheduler, sink: any MidiSink) {
        self.backup = backup
        self.scheduler = scheduler
        self.sink = sink
        state = RuntimeState(backup: backup)
    }

    /// Adds a switch action (1 to 9) of a preset to the queue and runs it when the engine is free.
    /// Returns a token for `withdraw`.
    @discardableResult
    public func enqueue(_ address: PresetAddress, _ action: Int) -> Int {
        nextToken += 1
        queue.append(.trigger(address, action: action, token: nextToken))
        if frames.isEmpty, wakeup == nil { run() }
        return nextToken
    }

    /// Removes the queued trigger of `token`, if it has not started. A running one goes on.
    /// Returns true when it removed the trigger.
    @discardableResult
    func withdraw(_ token: Int) -> Bool {
        let count = queue.count
        queue.removeAll {
            guard case .trigger(_, _, token) = $0 else { return false }
            return true
        }
        return queue.count < count
    }

    /// Moves expression input `input` (0 to 3) to `value` (0 to 127). The move waits in the same queue as triggers.
    /// A pending move of the same input takes the new value, unless a trigger is queued after it (spec 5.4).
    public func moveExpression(input: Int, to value: Int) {
        search: for index in queue.indices.reversed() {
            switch queue[index] {
            case .trigger, .navigate, .endInput: break search
            case .expression(input, _):
                queue[index] = .expression(input: input, value: value)
                return
            case .expression: continue
            }
        }
        queue.append(.expression(input: input, value: value))
        if frames.isEmpty, wakeup == nil { run() }
    }

    /// Adds a bank or page step of the keys or the bank sidebar to the queue (V01 to V03). It sends no MIDI (V05).
    public func navigate(_ step: NavigationStep) {
        queue.append(.navigate(step))
        if frames.isEmpty, wakeup == nil { run() }
    }

    /// V04: runs a stored preset of the shown bank as a short tap: Press, Release and Release All, with no wait
    /// for a second tap. A preset on a hidden page does nothing. A fault stops the remaining actions.
    /// Returns false for a preset on a hidden page.
    @discardableResult
    public func engage(preset: Int) -> Bool {
        guard preset / Footswitch.allCases.count < backup.banks[state.bank].pageCount else { return false }
        let address = PresetAddress(bank: state.bank, preset: preset)
        let generation = generation
        for action in [SwitchAction.press, SwitchAction.release, SwitchAction.releaseAll] where self.generation == generation {
            enqueue(address, action)
        }
        if self.generation == generation { endInput(toggling: address) }
        return true
    }

    /// V25: the end of an input: a gesture, a key 1-3 tap. A Bank Jump of the input runs now, after all its actions,
    /// as the manual says: "Bank Jump messages only execute at the end of the Preset."
    /// V30: `address` is the pressed preset. If it has Toggle Mode, it changes position now.
    public func endInput(toggling address: PresetAddress? = nil) {
        queue.append(.endInput(toggling: address))
        if frames.isEmpty, wakeup == nil { run() }
    }

    /// V22: the power-on of the MC6. Runs the On Enter Bank messages of the shown bank, once-only messages included.
    public func powerOn() {
        guard enterBank() else { return }
        // A power-on is an input of its own, with a fresh message budget.
        executed = 0
        if frames.isEmpty, wakeup == nil { run() }
    }

    /// Bumps the generation: drops the queues, the running trigger and its pending wake-up.
    public func cancel() {
        generation += 1
        queue.removeAll()
        enterQueue.removeAll()
        pendingBankChange = nil
        frames.removeAll()
        if let wakeup { scheduler.cancel(wakeup) }
        wakeup = nil
    }

    /// Bumps the generation and restores the start state (U12). Temporary names and scroll pointers go too (U09).
    public func reset() {
        cancel()
        state = RuntimeState(backup: backup)
    }

    private func run() {
        while true {
            guard let frame = frames.last else {
                // V21: enter messages keep the message count, so an input and its whole enter cascade share the budget.
                if !enterQueue.isEmpty {
                    let enter = enterQueue.removeFirst()
                    var root = makeFrame(enter.address, enter.action)
                    root.fromEnter = true
                    frames = [root]
                    continue
                }
                guard !queue.isEmpty else { return }
                switch queue.removeFirst() {
                case .trigger(let address, let action, _):
                    frames = [makeFrame(address, action)]
                    executed = 0
                case .expression(let input, let value):
                    guard sendExpression(input, value) else { return }
                case .navigate(let step):
                    let bank = state.bank
                    state.navigate(step, backup: backup)
                    executed = 0
                    if state.bank != bank, enterBank() { onStepEnter?() }
                case .endInput(let address):
                    // The enter messages after the end of an input share one fresh budget.
                    executed = 0
                    if let address, backup.banks[address.bank].presets[address.preset].toggleMode {
                        state[position: address] = state[position: address] == .one ? .two : .one
                    }
                    applyBankChange()
                }
                continue
            }
            let messages = backup.banks[frame.source.bank].presets[frame.source.preset].messages
            guard frame.next < messages.count else {
                frames.removeLast()
                // V25: an On Enter Bank Engage is an input of its own, so its bank change applies when it ends.
                if frames.isEmpty, frame.fromEnter { applyBankChange() }
                continue
            }
            frames[frames.count - 1].next += 1
            let message = messages[frame.next]
            // U02: the gate reads the live position of the frame preset. V26: a trigger frame has no action and no gate.
            guard frame.slots?.contains(message.slot) ?? true,
                frame.action.map({ message.action == $0 && passes(message.gate, state[position: frame.address]) }) ?? true
            else { continue }
            executed += 1
            guard executed <= Self.maxMessagesPerTrigger else { return fail(.budgetLimit(pointer: message.pointer)) }
            onExecute?(message)
            guard execute(message, in: frame.address) else { return }
        }
    }

    /// A frame for `action` of a preset. U07: a Release of a message scroll preset runs only the next group.
    private func makeFrame(_ address: PresetAddress, _ action: Int) -> Frame {
        let preset = backup.banks[address.bank].presets[address.preset]
        guard preset.toMsgScroll, action == SwitchAction.release else { return Frame(address: address, source: address, action: action) }
        let releases = preset.messages.filter { $0.action == action }
        return Frame(address: address, source: address, action: action, slots: state.nextScrollGroup(releases, of: address))
    }

    /// Sends the selected messages of an expression input in the shown bank (U06: masks are global).
    /// There is no gate to check: the importer loads expression messages only with `tg=2` (both positions).
    /// Returns false when a send failed.
    private func sendExpression(_ input: Int, _ value: Int) -> Bool {
        for message in state.selectedExpressions(input: input, in: backup) {
            guard case .expression(let channel, let number, let min, let max) = message.command else { continue }
            let bytes = expressionBytes(channel: channel, number: number, min: min, max: max, value: value)
            guard send(bytes, message) else { return false }
        }
        return true
    }

    /// Sends bytes to the ports of their channel. A message without a channel goes to both ports (V29).
    /// Returns false when the sink threw.
    private func send(_ bytes: [UInt8], _ message: Message) -> Bool {
        let ports: Ports = bytes[0] >= 0xF0 ? [.port1, .port2] : Ports(sendToPort: backup.sendToPort[Int(bytes[0] & 0x0F)])
        do {
            try sink.send(bytes, to: ports)
            onOutput?(bytes, ports, message.pointer)
            return true
        } catch let error as PartialSend {
            onOutput?(bytes, error.delivered, message.pointer)
            fail(.sendFailed(pointer: message.pointer, reason: "\(error.underlying)"))
            return false
        } catch {
            fail(.sendFailed(pointer: message.pointer, reason: "\(error)"))
            return false
        }
    }

    /// Runs one message. Returns false when the trigger waits for a wake-up or has stopped.
    private func execute(_ message: Message, in address: PresetAddress) -> Bool {
        switch message.command {
        case .midi(let bytes):
            return send(bytes, message)
        case .midiList(let list):
            for bytes in list {
                guard send(bytes, message) else { return false }
            }
        case .delay(let ms):
            let generation = generation
            wakeup = scheduler.schedule(after: .milliseconds(ms)) { [weak self] in
                guard let self, self.generation == generation else { return }
                self.wakeup = nil
                self.run()
            }
            return false
        case .engage(let bank, let preset, let action):
            guard frames.count < Self.maxDepth else {
                fail(.depthLimit(pointer: message.pointer))
                return false
            }
            frames.append(makeFrame(PresetAddress(bank: bank, preset: preset), action))
        case .triggerMessages(let preset, let slots):
            guard frames.count < Self.maxDepth else {
                fail(.depthLimit(pointer: message.pointer))
                return false
            }
            let source = PresetAddress(bank: address.bank, preset: preset)
            frames.append(Frame(address: address, source: source, action: nil, slots: Set((0..<32).filter { slots & 1 << $0 != 0 })))
        case .bankColors(let colors):
            state.bankColors[address.bank] = colors
        case .clearToggles:
            state.positions = state.positions.map { $0.map { _ in .one } }
        case .tempoStep(let step):
            onTempoStep?(step)
        case .togglePreset:
            state[position: address] = state[position: address] == .one ? .two : .one
        case .setToggle(let position, let mask):
            for preset in state.positions[address.bank].indices where mask & 1 << preset != 0 {
                state.positions[address.bank][preset] = position
            }
        case .flipToggle(let mask):
            for preset in state.positions[address.bank].indices where mask & 1 << preset != 0 {
                state.positions[address.bank][preset] = state.positions[address.bank][preset] == .one ? .two : .one
            }
        case .setToggleOnly(let mask):
            for preset in state.positions[address.bank].indices {
                state.positions[address.bank][preset] = mask & 1 << preset != 0 ? .two : .one
            }
        case .selectExpression(let input, let mask):
            state.expressionMasks[input] = mask
        case .bankJump(let target, let enter):
            pendingBankChange = .jump(target, enter: enter)
        case .bankStep(let up):
            pendingBankChange = .step(up: up)
        case .togglePage(let change):
            state.turnPage(change, banks: backup.banks)
        case .clockTap:
            onClockTap?()
        case .scrollGroupSize(let size):
            state.messageScroll[address, default: MessageScroll()].groupSize = size
        case .scrollCounter(let preset, let slot):
            let target = PresetAddress(bank: address.bank, preset: preset ?? address.preset)
            let releases = backup.banks[target.bank].presets[target.preset].messages.filter { $0.action == SwitchAction.release }
            state.cueScroll(target, slot: slot, releases: releases)
        case .presetColors(let preset, let colors):
            state.colors[PresetAddress(bank: address.bank, preset: preset ?? address.preset)] = colors
        case .rename(let kind, let name):
            state.names[NameKey(address: address, kind: kind)] = name
        case .expression:
            break  // Only expression presets hold these, and `sendExpression` runs them.
        }
        return true
    }

    /// V25: applies the pending bank change, then queues the On Enter Bank messages of the new bank (V21).
    private func applyBankChange() {
        guard let change = pendingBankChange else { return }
        pendingBankChange = nil
        let bank = state.bank
        switch change {
        case .jump(let target, let enter):
            state.jump(target, banks: backup.banks)
            if enter, state.bank != bank { enterBank() }
        case .step(let up):
            state.navigate(up ? .bankUp : .bankDown, backup: backup)
            if state.bank != bank { enterBank() }
        }
    }

    /// V21: queues the On Enter Bank messages of the shown bank. Once-only messages run only on the first entry after a
    /// power-on: the bank counts as entered once they are queued. Returns false when nothing was queued.
    @discardableResult
    private func enterBank() -> Bool {
        let bank = state.bank
        let entered = state.enteredOnce.contains(bank)
        let messages = backup.banks[bank].enterMessages.filter { !$0.once || !entered }
        if messages.contains(where: \.once) { state.enteredOnce.insert(bank) }
        enterQueue += messages.map { ($0.target, $0.action) }
        return !messages.isEmpty
    }

    private func passes(_ gate: Gate, _ position: Position) -> Bool {
        switch gate {
        case .both: true
        case .position1: position == .one
        case .position2: position == .two
        }
    }

    private func fail(_ fault: EngineFault) {
        cancel()
        onFault?(fault)
    }
}
