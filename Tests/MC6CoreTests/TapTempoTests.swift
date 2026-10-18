import Testing
@testable import MC6Core

/// Tap tempo for screen 3 (plan v2, V10).
@MainActor @Suite struct TapTempoTests {
    static func ms(_ value: Int) -> Duration { .milliseconds(value) }

    static func tempo(_ times: [Int]) -> TapTempo {
        var tempo = TapTempo()
        for time in times { tempo.tap(at: Self.ms(time)) }
        return tempo
    }

    @Test("V10: taps every 500 ms give 120 BPM; one tap gives no BPM")
    func steady() {
        #expect(Self.tempo([]).bpm == nil)
        #expect(Self.tempo([1000]).bpm == nil)
        #expect(Self.tempo([1000, 1500]).bpm == 120)
        #expect(Self.tempo([0, 500, 1000, 1500]).bpm == 120)
    }

    @Test("V10: a gap of more than 2 seconds starts a new count")
    func gap() {
        #expect(Self.tempo([0, 500, 2600]).bpm == nil)
        #expect(Self.tempo([0, 500, 2600, 3200]).bpm == 100)
        #expect(Self.tempo([0, 2000]).bpm == 30)
    }

    @Test("V10: taps at the same time count once, so a preset with two Clock Taps cannot divide by zero")
    func sameTime() {
        #expect(Self.tempo([1000, 1000]).bpm == nil)
        #expect(Self.tempo([0, 500, 500, 1000]).bpm == 120)
    }

    @Test("V10: only the last 4 intervals count")
    func lastFour() {
        // One slow interval of 1000 ms, then four of 500 ms.
        #expect(Self.tempo([0, 1000, 1500, 2000, 2500, 3000]).bpm == 120)
        // Mean of 500, 500, 500 and 1000 ms is 625 ms: 96 BPM.
        #expect(Self.tempo([0, 500, 1000, 1500, 2500]).bpm == 96)
    }

    @Test("V10: tapping HOME C (TAP) every 500 ms sets the session BPM; Reset clears it")
    func session() throws {
        let (session, scheduler) = try SessionTests.session(output: RecordingSink(scheduler: FakeScheduler()))
        #expect(session.bpm == nil)
        for _ in 0..<3 {
            SessionTests.tapC(session, scheduler)
            scheduler.advance(by: Self.ms(450))
        }
        #expect(session.bpm == 120)
        session.reset()
        #expect(session.bpm == nil)
    }

    @Test("V10: screen 3 shows the BPM below bank and page")
    func screen() throws {
        let backup = try Fixture.backup()
        let state = RuntimeState(backup: backup)
        let screens = ScreenDisplay.screens(state, in: backup, lastPressed: nil, expression: 0, bpm: 120, showLetters: false)
        #expect(screens[2].center == [[.text("EXP 1: 0%")], [.text("B001 PG1")], [.text("120 BPM")]])
    }
}
