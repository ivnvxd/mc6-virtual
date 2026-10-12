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
        let address = PresetAddress(bank: bank, preset: preset)
        for action in [SwitchAction.press, SwitchAction.release, SwitchAction.releaseAll] { engine.enqueue(address, action) }
    }

    /// A hold: Press, Long Press, Long Press Release, Release All.
    func hold(bank: Int, preset: Int) {
        let address = PresetAddress(bank: bank, preset: preset)
        for action in [SwitchAction.press, SwitchAction.longPress, SwitchAction.longPressRelease, SwitchAction.releaseAll] {
            engine.enqueue(address, action)
        }
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

    /// The stored preset under the physical button with letter `button` on the shown page.
    private func shown(_ button: Character) -> PresetAddress {
        engine.state.address(of: Footswitch.allCases.first { $0.letter == String(button) }!)
    }

    /// The bytes sent so far.
    var bytes: [[UInt8]] { sink.sent.map(\.bytes) }
}
