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
/// One serial queue (U11): a trigger waits until the running one ends, delays included.
/// Engage is call and return on a frame stack. Delay suspends through the scheduler.
@MainActor
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

    private struct Frame {
        let address: PresetAddress
        let action: Int
        /// Index into the preset's non-empty messages, which are in slot order.
        var next = 0
    }

    private let backup: Backup
    private let scheduler: any Scheduler
    private let sink: any MidiSink
    private var queue: [(address: PresetAddress, action: Int)] = []
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
        queue.append((address, action))
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

    private func run() {
        while true {
            guard let frame = frames.last else {
                guard !queue.isEmpty else { return }
                let trigger = queue.removeFirst()
                frames = [Frame(address: trigger.address, action: trigger.action)]
                executed = 0
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
            guard message.action == frame.action, passes(message.gate, state[position: frame.address]) else { continue }
            executed += 1
            guard executed <= Self.maxMessagesPerTrigger else { return fail(.budgetLimit(pointer: message.pointer)) }
            guard execute(message, in: frame.address) else { return }
        }
    }

    /// Runs one message. Returns false when the trigger waits for a wake-up or has stopped.
    private func execute(_ message: Message, in address: PresetAddress) -> Bool {
        switch message.command {
        case .midi(let bytes):
            do {
                try sink.send(bytes, to: Ports(sendToPort: backup.sendToPort[Int(bytes[0] & 0x0F)]))
            } catch {
                fail(.sendFailed(pointer: message.pointer, reason: "\(error)"))
                return false
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
            frames.append(Frame(address: PresetAddress(bank: bank, preset: preset), action: action))
        case .togglePreset:
            state[position: address] = state[position: address] == .one ? .two : .one
        case .setToggle(let position, let mask):
            for preset in state.positions[address.bank].indices where mask & 1 << preset != 0 {
                state.positions[address.bank][preset] = position
            }
        case .selectExpression(let input, let mask):
            state.expressionMasks[input] = mask
        case .bankJump, .togglePage, .clockTap, .scrollGroupSize, .rename, .expression:
            break  // Navigation, tap, message scroll, rename and expression output are not run yet.
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
