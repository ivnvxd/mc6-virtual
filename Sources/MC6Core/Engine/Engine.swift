import Observation

/// Why the engine stopped a trigger. The session disarms on any fault.
public enum EngineFault: Error, Sendable, Equatable {
    /// An Engage would put more than `Engine.maxDepth` frames on the stack.
    case depthLimit(pointer: String)
    /// A trigger tried to run more than `Engine.maxMessagesPerTrigger` messages.
    case budgetLimit(pointer: String)
    /// The sink threw while sending the message.
    case sendFailed(pointer: String, reason: String)
}

/// Runs switch actions of the backup (spec section 5.3).
///
/// One serial queue (U11): a trigger or an expression move waits until the running trigger ends, delays included.
/// Engage is call and return on a frame stack. Delay suspends through the scheduler.
@MainActor @Observable
public final class Engine {
    /// The most frames on the stack: the trigger and up to seven nested Engage calls.
    public static let maxDepth = 8
    /// The most messages one trigger runs, nested calls included.
    public static let maxMessagesPerTrigger = 512

    /// Settable inside the module so tests can prepare a state.
    public internal(set) var state: RuntimeState
    /// Bumped by `cancel()` and by every fault. Work from an older generation never runs.
    public private(set) var generation = 0
    /// Called after a fault has stopped the trigger and cleared the queue.
    public var onFault: ((EngineFault) -> Void)?
    /// Called for each MIDI Clock Tap, for the session log. U10: a tap sends no F8 clock.
    public var onClockTap: (() -> Void)?
    /// Called after each successful send, with the pointer of the source message, for the session log.
    public var onOutput: ((_ bytes: [UInt8], _ ports: Ports, _ pointer: String) -> Void)?
    /// Called for each switch message the engine runs, before it runs. The sweep test reads it,
    /// because a sink cannot see messages without output, such as Bank Jump.
    var onExecute: ((Message) -> Void)?

    private struct Frame {
        let address: PresetAddress
        let action: Int
        /// U07: the slots of the message scroll group this Release runs; nil runs every slot.
        var scrollGroup: Set<Int>?
        /// Index into the preset's non-empty messages, which are in slot order.
        var next = 0
    }

    private enum Work {
        case trigger(PresetAddress, action: Int)
        case expression(input: Int, value: Int)
    }

    private let backup: Backup
    private let scheduler: any Scheduler
    private let sink: any MidiSink
    private var queue: [Work] = []
    private var frames: [Frame] = []
    private var executed = 0
    private var wakeup: Wakeup?

    public init(backup: Backup, scheduler: any Scheduler, sink: any MidiSink) {
        self.backup = backup
        self.scheduler = scheduler
        self.sink = sink
        state = RuntimeState(backup: backup)
    }

    /// Adds a switch action (1 to 9) of a preset to the queue and runs it when the engine is free.
    public func enqueue(_ address: PresetAddress, _ action: Int) {
        queue.append(.trigger(address, action: action))
        if frames.isEmpty, wakeup == nil { run() }
    }

    /// Moves expression input `input` (0 to 3) to `value` (0 to 127). The move waits in the same queue as triggers.
    /// A pending move of the same input takes the new value, unless a trigger is queued after it (spec 5.4).
    public func moveExpression(input: Int, to value: Int) {
        search: for index in queue.indices.reversed() {
            switch queue[index] {
            case .trigger: break search
            case .expression(input, _):
                queue[index] = .expression(input: input, value: value)
                return
            case .expression: continue
            }
        }
        queue.append(.expression(input: input, value: value))
        if frames.isEmpty, wakeup == nil { run() }
    }

    /// Bumps the generation: drops the queue, the running trigger and its pending wake-up.
    public func cancel() {
        generation += 1
        queue.removeAll()
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
                guard !queue.isEmpty else { return }
                switch queue.removeFirst() {
                case .trigger(let address, let action):
                    frames = [makeFrame(address, action)]
                    executed = 0
                case .expression(let input, let value):
                    guard sendExpression(input, value) else { return }
                }
                continue
            }
            let messages = backup.banks[frame.address.bank].presets[frame.address.preset].messages
            guard frame.next < messages.count else {
                frames.removeLast()
                continue
            }
            frames[frames.count - 1].next += 1
            let message = messages[frame.next]
            // U02: the gate reads the live position of the frame preset.
            guard message.action == frame.action, frame.scrollGroup?.contains(message.slot) ?? true,
                passes(message.gate, state[position: frame.address])
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
        guard preset.toMsgScroll, action == 2 else { return Frame(address: address, action: action) }
        let releases = preset.messages.filter { $0.action == action }
        return Frame(address: address, action: action, scrollGroup: state.nextScrollGroup(releases, of: address))
    }

    /// Sends the selected messages of an expression input in the shown bank (U06: masks are global).
    /// Returns false when a send failed.
    private func sendExpression(_ input: Int, _ value: Int) -> Bool {
        let mask = state.expressionMasks[input]
        for message in backup.banks[state.bank].expressions[input].messages where mask & 1 << message.slot != 0 {
            guard case .expression(let channel, let number, let min, let max) = message.command else { continue }
            let bytes = expressionBytes(channel: channel, number: number, min: min, max: max, value: value)
            guard send(bytes, message) else { return false }
        }
        return true
    }

    /// Sends bytes to the ports of their channel. Returns false when the sink threw.
    private func send(_ bytes: [UInt8], _ message: Message) -> Bool {
        let ports = Ports(sendToPort: backup.sendToPort[Int(bytes[0] & 0x0F)])
        do {
            try sink.send(bytes, to: ports)
            onOutput?(bytes, ports, message.pointer)
            return true
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
        case .togglePreset:
            state[position: address] = state[position: address] == .one ? .two : .one
        case .setToggle(let position, let mask):
            for preset in state.positions[address.bank].indices where mask & 1 << preset != 0 {
                state.positions[address.bank][preset] = position
            }
        case .selectExpression(let input, let mask):
            state.expressionMasks[input] = mask
        case .bankJump(let target):
            state.jump(target, banks: backup.banks)
        case .togglePage(let change):
            state.turnPage(change, banks: backup.banks)
        case .clockTap:
            onClockTap?()
        case .scrollGroupSize(let size):
            state.messageScroll[address, default: MessageScroll()].groupSize = size
        case .rename(let name):
            state.names[address] = name
        case .expression:
            break  // Only expression presets hold these, and `sendExpression` runs them.
        }
        return true
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
