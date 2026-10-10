import MC6Core

/// A `MidiSink` that keeps everything sent, stamped with the scheduler time.
@MainActor
final class RecordingSink: MidiSink {
    struct Sent: Equatable {
        let time: Duration
        let bytes: [UInt8]
        let ports: Ports
    }

    private let scheduler: any Scheduler
    private(set) var sent: [Sent] = []

    init(scheduler: any Scheduler) {
        self.scheduler = scheduler
    }

    func send(_ bytes: [UInt8], to ports: Ports) throws {
        sent.append(Sent(time: scheduler.now, bytes: bytes, ports: ports))
    }
}
