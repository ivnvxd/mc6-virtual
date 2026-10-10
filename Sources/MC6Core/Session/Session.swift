import Foundation

/// One line of the session log.
public struct LogEntry: Sendable, Equatable {
    public enum Event: Sendable, Equatable {
        /// MIDI output of a message. `live` is false in Dry Run, where the bytes go only to the log.
        case output(bytes: [UInt8], ports: Ports, pointer: String, live: Bool)
        /// A MIDI Clock Tap (U10).
        case tap
        /// The engine stopped and the session disarmed.
        case fault(EngineFault)
    }

    /// Scheduler time.
    public let time: Duration
    public let event: Event

    public init(time: Duration, event: Event) {
        self.time = time
        self.event = event
    }
}

/// The app's model: the imported backup, its engine and gesture recognizer, the armed state and the log.
///
/// U12 and spec 11: a session starts in Dry Run and sends nothing on import, startup or reset.
/// Re-import, reset, disarm and an engine fault drop all pending work (a generation bump) and disarm.
@MainActor
public final class Session {
    public enum Mode: Sendable, Equatable {
        /// Outputs go to the log only.
        case dryRun
        /// Outputs go to the MIDI ports and the log.
        case live
        /// Disarmed by a fault. Bytes sent before it cannot be taken back, so the host may be in a partial state.
        case error(EngineFault)
    }

    /// The most log entries kept in memory. Older entries drop first.
    public static let logLimit = 10_000

    public private(set) var mode: Mode = .dryRun
    /// The last backup that loaded. A failed import keeps it.
    public private(set) var backup: Backup?
    public private(set) var engine: Engine?
    /// Why the last import failed; empty after a good import.
    public private(set) var importProblems: [ImportProblem] = []
    /// Bumped by re-import, reset, disarm and a fault. Each bump drops all pending work.
    public private(set) var generation = 0
    public private(set) var log: [LogEntry] = []

    private let scheduler: any Scheduler
    private let output: ArmedSink
    private var recognizer: GestureRecognizer?

    /// Passes outputs to the real sink only while the session is live.
    private final class ArmedSink: MidiSink {
        let sink: any MidiSink
        var live = false

        init(_ sink: any MidiSink) { self.sink = sink }

        func send(_ bytes: [UInt8], to ports: Ports) throws {
            if live { try sink.send(bytes, to: ports) }
        }
    }

    public init(scheduler: any Scheduler, output: any MidiSink) {
        self.scheduler = scheduler
        self.output = ArmedSink(output)
    }

    /// Imports a backup. On success it replaces the engine; on failure it keeps the previous backup
    /// and lists the problems. Both disarm.
    public func load(_ data: Data) {
        let backup: Backup
        do {
            backup = try Importer.load(data)
        } catch {
            importProblems = (error as? ImportError)?.problems ?? [ImportProblem(pointer: "", reason: "\(error)")]
            disarm()
            return
        }
        engine?.cancel()
        let engine = Engine(backup: backup, scheduler: scheduler, sink: output)
        engine.onOutput = { [weak self] bytes, ports, pointer in
            guard let self else { return }
            append(.output(bytes: bytes, ports: ports, pointer: pointer, live: output.live))
        }
        engine.onClockTap = { [weak self] in self?.append(.tap) }
        engine.onFault = { [weak self] fault in
            guard let self else { return }
            append(.fault(fault))
            stop(.error(fault))
        }
        self.backup = backup
        self.engine = engine
        recognizer = GestureRecognizer(backup: backup, engine: engine, scheduler: scheduler)
        importProblems = []
        stop(.dryRun)
    }

    /// Sends outputs to the MIDI ports from now on. Only the user arms, also after an error.
    public func arm() {
        output.live = true
        mode = .live
    }

    /// Back to Dry Run. Drops the queue, the running trigger and held gestures.
    public func disarm() {
        engine?.cancel()
        stop(.dryRun)
    }

    /// Restores the start state (U12) and disarms. Ableton is not reset (spec 5.4).
    public func reset() {
        engine?.reset()
        stop(.dryRun)
    }

    public func down(_ button: Footswitch, source: InputSource) {
        recognizer?.down(button, source: source)
    }

    public func up(_ button: Footswitch, source: InputSource) {
        recognizer?.up(button, source: source)
    }

    public func focusLost() {
        recognizer?.focusLost()
    }

    /// Moves expression input `input` (0 to 3) to `value` (0 to 127).
    public func moveExpression(input: Int, to value: Int) {
        engine?.moveExpression(input: input, to: value)
    }

    /// The log as JSON lines, one object per entry, with the time in milliseconds.
    public func exportLog() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var data = Data()
        for entry in log {
            // Encoding a struct of strings, numbers and arrays cannot fail.
            data += try! encoder.encode(Line(entry))
            data += Data("\n".utf8)
        }
        return data
    }

    private func stop(_ mode: Mode) {
        output.live = false
        self.mode = mode
        generation += 1
    }

    private func append(_ event: LogEntry.Event) {
        if log.count == Self.logLimit { log.removeFirst() }
        log.append(LogEntry(time: scheduler.now, event: event))
    }
}

/// The JSON form of a log entry. Ports are numbered 1 ("MC6 Virtual 1") and 2 ("MC6 Virtual 2").
private struct Line: Encodable {
    let ms: Double
    let kind: String
    var bytes: [UInt8]?
    var ports: [Int]?
    var pointer: String?
    var live: Bool?
    var reason: String?

    init(_ entry: LogEntry) {
        ms = entry.time / .milliseconds(1)
        switch entry.event {
        case .output(let bytes, let ports, let pointer, let live):
            kind = "output"
            self.bytes = bytes
            self.ports = [(Ports.port1, 1), (Ports.port2, 2)].filter { ports.contains($0.0) }.map(\.1)
            self.pointer = pointer
            self.live = live
        case .tap:
            kind = "tap"
        case .fault(let fault):
            kind = "fault"
            switch fault {
            case .depthLimit(let pointer):
                self.pointer = pointer
                reason = "depth limit"
            case .budgetLimit(let pointer):
                self.pointer = pointer
                reason = "message budget limit"
            case .sendFailed(let pointer, let error):
                self.pointer = pointer
                reason = "send failed: \(error)"
            }
        }
    }
}
