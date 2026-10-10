@testable import MC6Core

/// An engine wired to a `FakeScheduler` and a `RecordingSink`, with the faults it reported.
@MainActor
final class EngineHarness {
    let scheduler = FakeScheduler()
    let sink: RecordingSink
    let engine: Engine
    private(set) var faults: [EngineFault] = []

    init(_ backup: Backup) {
        sink = RecordingSink(scheduler: scheduler)
        engine = Engine(backup: backup, scheduler: scheduler, sink: sink)
        engine.onFault = { [unowned self] in faults.append($0) }
    }

    /// A short press: Press, Release, Release All.
    func tap(bank: Int, preset: Int) {
        for action in [1, 2, 9] { engine.enqueue(PresetAddress(bank: bank, preset: preset), action) }
    }

    /// The bytes sent so far.
    var bytes: [[UInt8]] { sink.sent.map(\.bytes) }
}
