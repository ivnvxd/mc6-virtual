import Foundation
import Observation

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

    /// The scheduler time in milliseconds.
    public var milliseconds: Double { time / .milliseconds(1) }

    public init(time: Duration, event: Event) {
        self.time = time
        self.event = event
    }
}

/// The app's model: the imported backup, its engine and gesture recognizer, the armed state and the log.
///
/// U12 and spec 11: a session starts in Dry Run and sends nothing on import, startup or reset.
/// Re-import, reset, arm, disarm and an engine fault drop all pending work (an engine generation bump).
/// All of them except arm also disarm.
@MainActor @Observable
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
    public private(set) var engine: Engine?
    /// The last backup that loaded: the backup of the engine. A failed import keeps it.
    public var backup: Backup? { engine?.backup }
    /// Why the last import failed; empty after a good import.
    public private(set) var importProblems: [ImportProblem] = []
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
            importProblems = error.problems
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
        self.engine = engine
        recognizer = GestureRecognizer(engine: engine, scheduler: scheduler)
        importProblems = []
        stop(.dryRun)
    }

    /// Sends outputs to the MIDI ports from now on. Only the user arms, also after an error.
    /// Arm first drops pending work, so the rest of a Dry Run sequence never reaches the ports.
    public func arm() {
        engine?.cancel()
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

    /// How long a button must be held for Long Press (U08); nil before the first good import.
    public var longPress: Duration? { recognizer?.longPress }

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
    }

    private func append(_ event: LogEntry.Event) {
        if log.count == Self.logLimit { log.removeFirst() }
        log.append(LogEntry(time: scheduler.now, event: event))
    }
}

/// The JSON form of a log entry.
private struct Line: Encodable {
    let ms: Double
    let kind: String
    var bytes: [UInt8]?
    var ports: [Int]?
    var pointer: String?
    var live: Bool?
    var reason: String?

    init(_ entry: LogEntry) {
        ms = entry.milliseconds
        switch entry.event {
        case .output(let bytes, let ports, let pointer, let live):
            kind = "output"
            self.bytes = bytes
            self.ports = ports.numbers
            self.pointer = pointer
            self.live = live
        case .tap:
            kind = "tap"
        case .fault(let fault):
            kind = "fault"
            pointer = fault.pointer
            reason = fault.reason
        }
    }
}
