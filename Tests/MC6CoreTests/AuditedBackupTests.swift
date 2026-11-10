import Testing
@testable import MC6Core

/// Acceptance tests on the audited backup of 2026-11-07, which runs on the user's MC6 Pro.
@MainActor @Suite(.needsSpec) struct AuditedBackupTests {
    static let reverb = PresetAddress(bank: FixtureBank.pedals, preset: 1)

    @Test("The audited backup loads")
    func loads() throws {
        #expect(try Fixture.audited().banks.count == Importer.bankCount)
    }

    @Test("V18, V20 to V24: the audited backup loads with no skipped item; its notes are 160 unused values")
    func noSkips() throws {
        let backup = try Fixture.audited()
        #expect(backup.notes.allSatisfy { !$0.isSkipped })
        #expect(backup.skippedPresets.isEmpty)
        #expect(backup.notes.filter { $0.kind == .unusedValue }.count == 160)
        #expect(backup.notes.count == 160)
    }

    @Test("U01: the 160 unused values of the audited backup give 4 note lines")
    func unusedLines() throws {
        let backup = try Fixture.audited()
        #expect(ImportText.lines(backup.notes.filter { $0.kind == .unusedValue }, in: backup).count == 4)
    }

    @Test("V21: HOME has three once-only enter messages and LOOPER one each-time enter message")
    func enterMessages() throws {
        let banks = try Fixture.audited().banks
        let home = banks[FixtureBank.home].enterMessages
        #expect(home.map(\.once) == [true, true, true])
        #expect(home.map(\.target) == [12, 18, 22].map { PresetAddress(bank: FixtureBank.pedals, preset: $0) })
        #expect(home.map(\.action) == [2, 2, 2])
        let looper = banks[FixtureBank.looper].enterMessages
        #expect(looper.map(\.once) == [false])
        #expect(looper.map(\.target) == [PresetAddress(bank: FixtureBank.looper, preset: 2)])
        #expect(looper.map(\.action) == [SwitchAction.releaseAll])
    }

    @Test("V20: DUMBLE FORD turns the reverb on: V FX ON engages B REVERB with No Action, which sends CC40=127 on channel 1")
    func dumbleFordReverb() throws {
        let h = EngineHarness(try Fixture.audited())
        h.tap(bank: FixtureBank.core, preset: 3)
        h.scheduler.advance(by: .seconds(1))
        let reverb = h.bytes.filter { $0.count == 3 && $0[0] == 0xB0 && $0[1] == 40 }
        #expect(reverb.last == cc(1, 40, 127))
        #expect(h.engine.state[position: Self.reverb] == .two)
        #expect(h.faults.isEmpty)
    }

    /// LOOPER C STOP: Press writes the short name "HOLD: CLEAR", Long Press "CLEAR", Release All restores it.
    @Test("V25: a hold of DUMBLE FORD keeps CORE shown until the release, then shows DAW")
    func dumbleFordHold() throws {
        let h = EngineHarness(try Fixture.audited())
        h.engine.state.bank = FixtureBank.core
        h.recognizer.down(.d, source: .mouse)
        h.scheduler.advance(by: .milliseconds(900))
        #expect(h.engine.state.bank == FixtureBank.core)
        h.recognizer.up(.d, source: .mouse)
        h.scheduler.advance(by: .seconds(1))
        #expect(h.engine.state.bank == FixtureBank.daw)
        #expect(h.faults.isEmpty)
    }

    @Test("V24: LOOPER STOP shows HOLD: CLEAR on Press, CLEAR on Long Press and STOP again after Release All")
    func stopNames() throws {
        let backup = try Fixture.audited()
        let h = EngineHarness(backup)
        h.engine.state.bank = FixtureBank.looper
        let stop = PresetAddress(bank: FixtureBank.looper, preset: 2)
        func shown() -> [NamePart] {
            ScreenDisplay.screens(h.engine.state, in: backup, lastPressed: nil, expression: 0, showLetters: false)[2].bottom.parts
        }
        h.engine.enqueue(stop, SwitchAction.press)
        h.scheduler.advance(by: .seconds(1))
        #expect(shown() == [.text("HOLD: CLEAR")])
        h.engine.enqueue(stop, SwitchAction.longPress)
        h.scheduler.advance(by: .seconds(1))
        #expect(shown() == [.text("CLEAR")])
        h.engine.enqueue(stop, SwitchAction.releaseAll)
        #expect(shown() == NamePart.parts(backup.banks[FixtureBank.looper].presets[2].shortName))
    }

    @Test("V21: entering LOOPER runs STOP's Release All, which restores its name and colors")
    func enterLooper() throws {
        let backup = try Fixture.audited()
        let h = EngineHarness(backup)
        let stop = PresetAddress(bank: FixtureBank.looper, preset: 2)
        h.engine.state.names[NameKey(address: stop, kind: .short)] = "CLEAR"
        h.engine.state.colors[stop] = PresetColors(strip: 9, text: 7, background: 9)
        h.engine.navigate(.select(FixtureBank.looper))
        #expect(h.engine.state.names[NameKey(address: stop, kind: .short)] == nil)
        #expect(h.engine.state.colors[stop] == backup.banks[FixtureBank.looper].presets[2].colors)
        #expect(h.faults.isEmpty)
    }

    @Test("V21: HOME's once-only enter messages run at power-on and not when HOME is entered again")
    func homeOnce() throws {
        let h = EngineHarness(try Fixture.audited())
        h.engine.powerOn()
        h.scheduler.advance(by: .seconds(1))
        #expect(h.bytes.contains(cc(1, 62, 21)))
        let count = h.bytes.count
        h.engine.navigate(.select(FixtureBank.pedals))
        h.engine.navigate(.select(FixtureBank.home))
        h.scheduler.advance(by: .seconds(1))
        #expect(h.bytes.count == count)
        #expect(h.faults.isEmpty)
    }

    /// A session with the audited backup and a recording sink.
    static func session() throws -> (Session, RecordingSink, FakeScheduler) {
        let scheduler = FakeScheduler()
        let sink = RecordingSink(scheduler: scheduler)
        let session = Session(scheduler: scheduler, output: sink)
        session.load(try Fixture.auditedData())
        scheduler.advance(by: .seconds(1))
        return (session, sink, scheduler)
    }

    /// The bytes of the log outputs, live or dry.
    static func logged(_ session: Session, live: Bool) -> [[UInt8]] {
        session.log.compactMap { if case .output(let bytes, _, _, live) = $0.event { bytes } else { nil } }
    }

    @Test("V22: Open runs HOME's start messages in Dry Run: the log has them as dry, and the ports get nothing")
    func openRunsStartDry() throws {
        let (session, sink, _) = try Self.session()
        // U06: every expression message is active at power-on, then HOME's start messages select message 1 of input 1.
        #expect(session.engine?.state.expressionMasks[0] == 1)
        #expect(session.mode == .dryRun)
        #expect(Self.logged(session, live: false).contains(cc(1, 62, 21)))
        #expect(sink.sent.isEmpty)
    }

    @Test("V22: Arm runs the start messages again, live; Reset from Live runs them in Dry Run and sends nothing")
    func armRunsStartLive() throws {
        let (session, sink, scheduler) = try Self.session()
        session.arm()
        scheduler.advance(by: .seconds(1))
        #expect(sink.sent.map(\.bytes).contains(cc(1, 62, 21)))
        let sent = sink.sent.count
        let dry = Self.logged(session, live: false).count
        session.reset()
        scheduler.advance(by: .seconds(1))
        #expect(session.mode == .dryRun)
        #expect(sink.sent.count == sent)
        #expect(Self.logged(session, live: false).count > dry)
    }

    @Test("V12: a bank step that runs enter messages starts a new Sent group; one that runs none keeps the group")
    func stepEnterGroup() throws {
        let (session, _, scheduler) = try Self.session()
        session.moveExpression(input: 0, to: 10)
        scheduler.advance(by: .milliseconds(10))
        #expect(session.groupCount > 0)
        session.navigate(.select(FixtureBank.pedals))
        #expect(session.groupCount > 0)
        session.navigate(.select(FixtureBank.looper))
        #expect(session.groupCount == 0)
    }

    @Test("V23: after two Releases of K SPACE, W SPACE NORMAL makes the next Release send K's first message again")
    func spaceNormalCue() throws {
        let h = EngineHarness(try Fixture.audited())
        let space = PresetAddress(bank: FixtureBank.pedals, preset: 10)
        func tapSpace() -> [[UInt8]] {
            let before = h.bytes.count
            h.tap(bank: space.bank, preset: space.preset)
            return Array(h.bytes[before...])
        }
        #expect(tapSpace() == [cc(1, 62, 64)])
        #expect(tapSpace() == [cc(1, 62, 107)])
        h.tap(bank: FixtureBank.pedals, preset: 22)
        #expect(tapSpace() == [cc(1, 62, 64)])
        #expect(h.faults.isEmpty)
    }

    @Test("V24: LOOPER STOP gets an orange strip on Press, a red background on Long Press and its own colors after Release All")
    func stopColors() throws {
        let backup = try Fixture.audited()
        let h = EngineHarness(backup)
        h.engine.state.bank = FixtureBank.looper
        let stop = PresetAddress(bank: FixtureBank.looper, preset: 2)
        func shown() -> Band {
            ScreenDisplay.screens(h.engine.state, in: backup, lastPressed: nil, expression: 0, showLetters: false)[2].bottom
        }
        let stored = backup.banks[FixtureBank.looper].presets[2].colors
        h.engine.enqueue(stop, SwitchAction.press)
        h.scheduler.advance(by: .seconds(1))
        #expect(shown().strip == Palette.color(8))
        h.engine.enqueue(stop, SwitchAction.longPress)
        h.scheduler.advance(by: .seconds(1))
        #expect(shown().background == Palette.color(9))
        h.engine.enqueue(stop, SwitchAction.releaseAll)
        #expect(h.engine.state.colors[stop] == stored)
        #expect(shown().strip == Palette.color(stored.strip))
    }
}
