import Testing
@testable import MC6Core

/// The new key functions: bank and page steps, the bank sidebar and engage I, J, K (V01 to V05).
@MainActor @Suite struct NavigationKeysTests {
    static func ms(_ value: Int) -> Duration { .milliseconds(value) }

    static func fixture() throws -> EngineHarness { EngineHarness(try Fixture.backup()) }

    @Test("V01: Bank Up from bank 12 wraps to bank 0, Bank Down from bank 0 wraps to bank 12")
    func bankWrap() throws {
        let h = try Self.fixture()
        h.engine.state.bank = 12
        h.engine.navigate(.bankUp)
        #expect(h.engine.state.place == Place(bank: 0, page: 0))
        h.engine.navigate(.bankDown)
        #expect(h.engine.state.place == Place(bank: 12, page: 0))
    }

    @Test("V01: bank steps visit only the production banks, in order, and never bank 20")
    func bankStepsStayInProduction() throws {
        let h = try Self.fixture()
        #expect(h.engine.backup.sortedProductionBanks == Array(0...12))
        var visited: [Int] = []
        for _ in 0..<13 {
            h.engine.navigate(.bankUp)
            visited.append(h.engine.state.bank)
        }
        #expect(visited == Array(1...12) + [0])
    }

    @Test("V02: a bank step goes to page 1 and records the place it left, like a Bank Jump")
    func bankStepRecordsLastPlace() throws {
        let h = try Self.fixture()
        h.engine.state.bank = 2
        h.engine.state.page = 1
        h.engine.navigate(.bankDown)
        #expect(h.engine.state.place == Place(bank: 1, page: 0))
        #expect(h.engine.state.lastPlace == Place(bank: 2, page: 1))
    }

    @Test("V03: page steps wrap within the bank's page count (PEDALS has 3 pages)")
    func pageSteps() throws {
        let h = try Self.fixture()
        h.engine.state.bank = 2
        h.engine.navigate(.pageDown)
        #expect(h.engine.state.page == 2)
        h.engine.navigate(.pageUp)
        h.engine.navigate(.pageUp)
        #expect(h.engine.state.page == 1)
    }

    @Test("V02: the sidebar goes to page 1 of the selected bank")
    func selectBank() throws {
        let h = try Self.fixture()
        h.engine.state.bank = 2
        h.engine.state.page = 1
        h.engine.navigate(.select(4))
        #expect(h.engine.state.place == Place(bank: 4, page: 0))
        #expect(h.engine.state.lastPlace == Place(bank: 2, page: 1))
    }

    @Test("V01: the sidebar ignores a bank outside the production banks")
    func selectUnreachable() throws {
        let h = try Self.fixture()
        h.engine.navigate(.select(20))
        #expect(h.engine.state.place == Place(bank: 0, page: 0))
    }

    // MARK: - Engage

    /// Presets I, J and K (8, 9, 10) send CC `action` with value `tag` for actions 1, 2, 3 and 9.
    static func engageBackup(pageLimit: Int = 0) -> Backup {
        var presets: [[Message]] = Array(repeating: [], count: 11)
        for (preset, tag) in [(8, 9), (9, 10), (10, 11)] {
            presets[preset] = GestureTests.recorder(UInt8(tag), actions: [1, 2, 3, 9])
        }
        return EngineTests.backup([presets], pageLimit: pageLimit)
    }

    @Test("V04: engage runs Press, Release and Release All of stored presets 8, 9 and 10", arguments: [8, 9, 10])
    func engage(_ preset: Int) {
        let h = EngineHarness(Self.engageBackup())
        h.engine.engage(preset: preset)
        let tag = UInt8(preset + 1)
        #expect(h.bytes == [[0xB0, 1, tag], [0xB0, 2, tag], [0xB0, 9, tag]])
    }

    @Test("V04: engage does nothing in a one-page bank, where I, J and K are hidden")
    func engageOnePage() {
        let h = EngineHarness(Self.engageBackup(pageLimit: 1))
        h.engine.engage(preset: 8)
        #expect(h.bytes.isEmpty)
    }

    @Test("V04: a fault in the Press of an engaged preset drops its Release and Release All")
    func engageFault() {
        var presets: [[Message]] = Array(repeating: [], count: 9)
        presets[8] = [
            EngineTests.message(0, .engage(bank: 0, preset: 8, action: 1), action: 1),
            EngineTests.message(1, EngineTests.ccCommand(2), action: 2),
            EngineTests.message(2, EngineTests.ccCommand(9), action: 9),
        ]
        let h = EngineHarness(EngineTests.backup([presets]))
        h.engine.engage(preset: 8)
        #expect(h.faults.count == 1)
        #expect(h.bytes.isEmpty)
    }

    // MARK: - Queue rules

    @Test("V05: navigation sends no MIDI, in Dry Run and Live")
    func noOutput() throws {
        let scheduler = FakeScheduler()
        let sink = RecordingSink(scheduler: scheduler)
        let session = Session(scheduler: scheduler, output: sink)
        session.load(try Fixture.data())
        for live in [false, true] {
            if live { session.arm() }
            for step in [NavigationStep.bankUp, .bankDown, .pageUp, .pageDown, .select(2)] { session.navigate(step) }
        }
        #expect(sink.sent.isEmpty)
        #expect(session.log.isEmpty)
        #expect(session.engine?.state.place == Place(bank: 2, page: 0))
    }

    /// Preset A presses with a 10 ms delay. Expression input 1 sends CC 7 with the pedal value.
    static func delayBackup() -> Backup {
        EngineTests.backup(
            [[[EngineTests.message(0, .delay(ms: 10), action: 1)]], [], []],
            expressions: [[EngineTests.message(0, .expression(channel: 1, number: 7, min: 0, max: 127), action: 0)]])
    }

    @Test("A navigation queued behind a delayed trigger waits for it")
    func waitsBehindTrigger() {
        let h = EngineHarness(Self.delayBackup())
        h.engine.enqueue(EngineTests.a, SwitchAction.press)
        h.engine.navigate(.bankUp)
        #expect(h.engine.state.bank == 0)
        h.scheduler.advance(by: Self.ms(10))
        #expect(h.engine.state.bank == 1)
    }

    @Test("cancel() drops a queued navigation")
    func cancelDropsNavigation() {
        let h = EngineHarness(Self.delayBackup())
        h.engine.enqueue(EngineTests.a, SwitchAction.press)
        h.engine.navigate(.bankUp)
        h.engine.cancel()
        h.scheduler.advance(by: Self.ms(10))
        #expect(h.engine.state.bank == 0)
    }

    @Test("A pedal move does not merge with a pedal move queued before a bank step")
    func pedalDoesNotMergeAcrossNavigation() {
        let h = EngineHarness(Self.delayBackup())
        h.engine.enqueue(EngineTests.a, SwitchAction.press)
        h.engine.moveExpression(input: 0, to: 10)
        h.engine.navigate(.bankUp)
        h.engine.moveExpression(input: 0, to: 20)
        h.scheduler.advance(by: Self.ms(10))
        #expect(h.bytes == [[0xB0, 7, 10], [0xB0, 7, 20]])
    }
}
