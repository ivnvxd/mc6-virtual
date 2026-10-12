@testable import MC6Core

/// An engine wired to a `FakeScheduler` and a `RecordingSink`, with the faults it reported.
@MainActor
final class EngineHarness {
    let scheduler = FakeScheduler()
    let sink: RecordingSink
    let engine: Engine
    let recognizer: GestureRecognizer
    private(set) var faults: [EngineFault] = []
    /// The scheduler time of each MIDI Clock Tap.
    private(set) var taps: [Duration] = []

    init(_ backup: Backup) {
        sink = RecordingSink(scheduler: scheduler)
        engine = Engine(backup: backup, scheduler: scheduler, sink: sink)
        recognizer = GestureRecognizer(engine: engine, scheduler: scheduler)
        engine.onFault = { [unowned self] in faults.append($0) }
        engine.onClockTap = { [unowned self] in taps.append(scheduler.now) }
    }

    /// A short press: Press, Release, Release All.
    func tap(bank: Int, preset: Int) {
        for action in [1, 2, 9] { engine.enqueue(PresetAddress(bank: bank, preset: preset), action) }
    }

    /// A hold: Press, Long Press, Long Press Release, Release All.
    func hold(bank: Int, preset: Int) {
        for action in [1, 3, 4, 9] { engine.enqueue(PresetAddress(bank: bank, preset: preset), action) }
    }

    /// A short press of physical button A to F on the shown page.
    func tap(_ button: Character) {
        let address = shown(button)
        tap(bank: address.bank, preset: address.preset)
    }

    /// A hold of physical button A to F on the shown page.
    func hold(_ button: Character) {
        let address = shown(button)
        hold(bank: address.bank, preset: address.preset)
    }

    /// Spec section 6.1: physical A to F press stored presets `page * 6` to `page * 6 + 5`.
    private func shown(_ button: Character) -> PresetAddress {
        let physical = Int(button.asciiValue! - Character("A").asciiValue!)
        return PresetAddress(bank: engine.state.bank, preset: engine.state.page * 6 + physical)
    }

    /// The bytes sent so far.
    var bytes: [[UInt8]] { sink.sent.map(\.bytes) }
}
