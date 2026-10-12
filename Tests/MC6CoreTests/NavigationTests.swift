import Testing
@testable import MC6Core

/// Bank Jump and Toggle Page (spec 7.3, 7.4) with U04 and U05. Routes and targets come from inventory/BANK-MANIFEST.md.
/// Pages are 0-based indices here: page 0 is page 1 of the spec.
@MainActor @Suite struct NavigationTests {
    enum Step {
        case tap(Character), hold(Character)
    }

    /// Runs each step on the shown page and expects the shown place after it.
    static func walk(_ h: EngineHarness, _ route: [(Step, Place)], sourceLocation: SourceLocation = #_sourceLocation) {
        for (index, (step, expected)) in route.enumerated() {
            switch step {
            case .tap(let button): h.tap(button)
            case .hold(let button): h.hold(button)
            }
            h.scheduler.advance(by: .seconds(1))
            #expect(h.engine.state.place == expected, "step \(index): \(step)", sourceLocation: sourceLocation)
        }
    }

    static func place(_ bank: Int, _ page: Int) -> Place { Place(bank: bank, page: page) }

    // MARK: - S1

    @Test("S1: HOME A Release goes to TONES page 1, HOME A hold to TONES page 2")
    func s1HomeTones() throws {
        let backup = try Fixture.backup()
        let tap = EngineHarness(backup)
        tap.tap("A")  // [1,0,6]
        #expect(tap.engine.state.place == Self.place(FixtureBank.tones, 0))
        let hold = EngineHarness(backup)
        hold.hold("A")  // [1,0,7]
        #expect(hold.engine.state.place == Self.place(FixtureBank.tones, 1))
        #expect(tap.bytes.isEmpty && hold.bytes.isEmpty)
    }

    @Test("S1: HOME B Release goes to PEDALS page 1, HOME B hold to PEDALS page 2")
    func s1HomePedals() throws {
        let backup = try Fixture.backup()
        let tap = EngineHarness(backup)
        tap.tap("B")  // [2,0,6]
        #expect(tap.engine.state.place == Self.place(FixtureBank.pedals, 0))
        let hold = EngineHarness(backup)
        hold.hold("B")  // [2,0,7]
        #expect(hold.engine.state.place == Self.place(FixtureBank.pedals, 1))
    }

    // MARK: - U04

    @Test("U04: BACK returns to the previous bank and page, and BACK there flips back")
    func u04BackFlips() throws {
        let h = EngineHarness(try Fixture.backup())
        Self.walk(h, [
            (.hold("B"), Self.place(FixtureBank.pedals, 1)),  // HOME PEDALS hold [2,0,7]
            (.hold("E"), Self.place(FixtureBank.looper, 0)),  // PEDALS K SPACE hold [3,0,6]
            (.tap("F"), Self.place(FixtureBank.pedals, 1)),  // LOOPER BACK [0,126,6]
            (.tap("F"), Self.place(FixtureBank.looper, 0)),  // PEDALS L BACK [0,126,6]
        ])
        #expect(h.engine.state.lastPlace == Self.place(FixtureBank.pedals, 1))
        #expect(h.faults.isEmpty)
    }

    @Test("U04: a same-bank jump changes only the page, so BACK returns to the new page")
    func u04SameBankJump() throws {
        let h = EngineHarness(try Fixture.backup())
        Self.walk(h, [
            (.tap("A"), Self.place(FixtureBank.tones, 0)),
            (.tap("A"), Self.place(FixtureBank.core, 0)),  // TONES CORE [5,0,6]
            (.hold("C"), Self.place(FixtureBank.core, 1)),  // CORE C hold [5,0,7]
        ])
        #expect(h.engine.state.lastPlace == Self.place(FixtureBank.tones, 0))
        Self.walk(h, [
            (.tap("B"), Self.place(FixtureBank.pedals, 0)),  // CORE H PEDALS [2,0,6]
            (.tap("F"), Self.place(FixtureBank.core, 1)),  // PEDALS BACK
        ])
    }

    @Test("U04: HOME F hold changes only the page and keeps the history")
    func u04HomeFHold() throws {
        let h = EngineHarness(try Fixture.backup())
        Self.walk(h, [
            (.tap("E"), Self.place(FixtureBank.looper, 0)),  // HOME LOOPER [3,0,6]
            (.tap("F"), Self.place(FixtureBank.home, 0)),  // LOOPER BACK
            (.hold("F"), Self.place(FixtureBank.home, 0)),  // HOME MUTE hold [0,0,6]
        ])
        #expect(h.engine.state.lastPlace == Self.place(FixtureBank.looper, 0))
        #expect(h.bytes.isEmpty)
    }

    @Test("U04: a cross-bank Engage keeps the history and the shown place")
    func u04EngageKeepsHistory() throws {
        let h = EngineHarness(try Fixture.backup())
        Self.walk(h, [
            (.hold("A"), Self.place(FixtureBank.tones, 1)),  // HOME TONES hold [1,0,7]
            (.tap("A"), Self.place(FixtureBank.nolly, 0)),  // TONES G NOLLY [9,0,6]
            (.tap("A"), Self.place(FixtureBank.nolly, 0)),  // NOLLY A engages bank 9 W and PEDALS A
        ])
        #expect(h.engine.state.lastPlace == Self.place(FixtureBank.tones, 1))
        #expect(h.engine.state[position: PresetAddress(bank: FixtureBank.pedals, preset: 0)] == .two)
        #expect(h.faults.isEmpty)
    }

    @Test("U04: BACK without a previous bank does nothing")
    func u04BackWithoutHistory() {
        let h = EngineHarness(EngineTests.backup([[[EngineTests.message(0, .bankJump(.lastBankAndPage))]]]))
        h.tap(bank: 0, preset: 0)
        #expect(h.engine.state.place == Self.place(0, 0))
        #expect(h.engine.state.lastPlace == nil)
    }

    @Test("U04: Last Bank (d1=127) goes to page 1 of the previous bank and records the place it leaves")
    func u04LastBank() {
        let h = EngineHarness(EngineTests.backup([
            [[EngineTests.message(0, .bankJump(.bank(1, page: 1)))]],
            [[EngineTests.message(0, .bankJump(.lastBank))]],
        ]))
        h.engine.state.page = 1
        h.tap(bank: 0, preset: 0)
        #expect(h.engine.state.place == Self.place(1, 1))
        h.tap(bank: 1, preset: 0)
        #expect(h.engine.state.place == Self.place(0, 0))
        #expect(h.engine.state.lastPlace == Self.place(1, 1))
    }

    // MARK: - U05

    @Test("U05: PAGE+ on PEDALS page 3 wraps to page 1; the hidden fourth page never shows")
    func u05PedalsWrap() throws {
        let h = EngineHarness(try Fixture.backup())
        Self.walk(h, [
            (.tap("B"), Self.place(FixtureBank.pedals, 0)),
            (.tap("C"), Self.place(FixtureBank.pedals, 1)),  // PEDALS C PAGE+ Press [1]
            (.tap("C"), Self.place(FixtureBank.pedals, 2)),  // PEDALS I PAGE+
            (.tap("C"), Self.place(FixtureBank.pedals, 0)),  // PEDALS O PAGE+
        ])
        #expect(h.bytes.isEmpty)
    }

    @Test("U05: pageLimit 0 means four pages, so PageDown on page 1 goes to page 4")
    func u05NoLimit() {
        let h = EngineHarness(EngineTests.backup([[[EngineTests.message(0, .togglePage(.down))]]]))
        h.tap(bank: 0, preset: 0)
        #expect(h.engine.state.page == 3)
        h.tap(bank: 0, preset: 0)
        #expect(h.engine.state.page == 2)
    }

    @Test("U05: a direct page past pageLimit shows the last visible page")
    func u05DirectPastLimit() {
        let h = EngineHarness(EngineTests.backup([
            [[EngineTests.message(0, .togglePage(.go(3))), EngineTests.message(1, .bankJump(.bank(1, page: 3)), action: 3)]],
            [],
        ], pageLimit: 2))
        h.tap(bank: 0, preset: 0)
        #expect(h.engine.state.place == Self.place(0, 1))
        h.hold(bank: 0, preset: 0)
        #expect(h.engine.state.place == Self.place(1, 1))
    }

    // MARK: - State across navigation

    @Test("Positions survive bank changes")
    func positionsSurvive() throws {
        let h = EngineHarness(try Fixture.backup())
        let boost = PresetAddress(bank: FixtureBank.pedals, preset: 0)
        Self.walk(h, [
            (.tap("B"), Self.place(FixtureBank.pedals, 0)),
            (.tap("A"), Self.place(FixtureBank.pedals, 0)),  // BOOST to Position 2
            (.hold("E"), Self.place(FixtureBank.looper, 0)),  // PEDALS COMP hold [3,0,6]
            (.tap("F"), Self.place(FixtureBank.pedals, 0)),  // LOOPER BACK
        ])
        #expect(h.engine.state[position: boost] == .two)
        h.tap("A")
        // S5: the Position 2 group of BOOST is CC50=0 on channels 2, 5, 6, 7, 8.
        #expect(h.bytes.suffix(5) == [2, 5, 6, 7, 8].map { [0xB0 | ($0 - 1), 50, 0] })
        #expect(h.engine.state[position: boost] == .one)
    }

    // MARK: - S10

    @Test("S10: HOME, TONES and each tone bank on both pages")
    func s10ToneBanks() throws {
        let h = EngineHarness(try Fixture.backup())
        Self.walk(h, [
            (.tap("A"), Self.place(FixtureBank.tones, 0)),
            // CORE: C hold [5,0,7], I hold [5,0,6], A hold [1,0,6].
            (.tap("A"), Self.place(FixtureBank.core, 0)),
            (.hold("C"), Self.place(FixtureBank.core, 1)),
            (.hold("C"), Self.place(FixtureBank.core, 0)),
            (.hold("A"), Self.place(FixtureBank.tones, 0)),
            // VINTAGE: C hold [6,0,7], G hold [1,0,6].
            (.tap("D"), Self.place(FixtureBank.vintage, 0)),
            (.hold("C"), Self.place(FixtureBank.vintage, 1)),
            (.hold("A"), Self.place(FixtureBank.tones, 0)),
            // MODERN: C hold [7,0,7], G hold [1,0,6].
            (.tap("E"), Self.place(FixtureBank.modern, 0)),
            (.hold("C"), Self.place(FixtureBank.modern, 1)),
            (.hold("A"), Self.place(FixtureBank.tones, 0)),
            // AMBIENT: C and I Release are PageUp, G hold [1,0,6].
            (.tap("F"), Self.place(FixtureBank.ambient, 0)),
            (.tap("C"), Self.place(FixtureBank.ambient, 1)),
            (.tap("C"), Self.place(FixtureBank.ambient, 0)),
            (.tap("C"), Self.place(FixtureBank.ambient, 1)),
            (.hold("A"), Self.place(FixtureBank.tones, 0)),
            // TONES C PAGE+ Press.
            (.tap("C"), Self.place(FixtureBank.tones, 1)),
            // NOLLY: G on TONES page 2; C hold [9,0,7], G hold [1,0,7].
            (.tap("A"), Self.place(FixtureBank.nolly, 0)),
            (.hold("C"), Self.place(FixtureBank.nolly, 1)),
            (.hold("A"), Self.place(FixtureBank.tones, 1)),
            // MAYER: J; C hold [10,0,7], G hold [1,0,7].
            (.tap("D"), Self.place(FixtureBank.mayer, 0)),
            (.hold("C"), Self.place(FixtureBank.mayer, 1)),
            (.hold("A"), Self.place(FixtureBank.tones, 1)),
            // RABEA: K; C hold [11,0,7], G hold [1,0,7].
            (.tap("E"), Self.place(FixtureBank.rabea, 0)),
            (.hold("C"), Self.place(FixtureBank.rabea, 1)),
            (.hold("A"), Self.place(FixtureBank.tones, 1)),
            // CORY: L; C hold [12,0,7], G hold [1,0,7].
            (.tap("F"), Self.place(FixtureBank.cory, 0)),
            (.hold("C"), Self.place(FixtureBank.cory, 1)),
            (.hold("A"), Self.place(FixtureBank.tones, 1)),
            // TONES I PAGE- is PageUp, which wraps to page 1.
            (.tap("C"), Self.place(FixtureBank.tones, 0)),
        ])
        #expect(h.bytes.isEmpty)
        #expect(h.faults.isEmpty)
    }

    @Test("S10: tone bank to PEDALS to BOOST to BACK, on both PEDALS entry pages")
    func s10ToneToPedals() throws {
        let h = EngineHarness(try Fixture.backup())
        Self.walk(h, [
            (.tap("A"), Self.place(FixtureBank.tones, 0)),
            (.tap("A"), Self.place(FixtureBank.core, 0)),
            (.tap("B"), Self.place(FixtureBank.pedals, 0)),  // CORE B PEDALS [2,0,6]
            (.tap("A"), Self.place(FixtureBank.pedals, 0)),  // BOOST
            (.tap("F"), Self.place(FixtureBank.core, 0)),  // PEDALS BACK
            (.hold("B"), Self.place(FixtureBank.pedals, 1)),  // CORE B hold [2,0,7]
            (.tap("F"), Self.place(FixtureBank.core, 0)),  // PEDALS L BACK
        ])
        #expect(h.bytes == [2, 5, 6, 7, 8].map { [0xB0 | ($0 - 1), 50, 127] })
        #expect(h.faults.isEmpty)
    }

    @Test("S10: LOOPER and BACK, repeated BACK transitions")
    func s10LooperBack() throws {
        let h = EngineHarness(try Fixture.backup())
        Self.walk(h, [
            (.tap("E"), Self.place(FixtureBank.looper, 0)),  // HOME LOOPER
            (.tap("F"), Self.place(FixtureBank.home, 0)),  // LOOPER BACK
            (.tap("B"), Self.place(FixtureBank.pedals, 0)),  // HOME PEDALS
            (.hold("E"), Self.place(FixtureBank.looper, 0)),  // PEDALS COMP hold [3,0,6]
            (.tap("F"), Self.place(FixtureBank.pedals, 0)),
            (.tap("F"), Self.place(FixtureBank.looper, 0)),
            (.tap("F"), Self.place(FixtureBank.pedals, 0)),
            (.tap("F"), Self.place(FixtureBank.looper, 0)),
            (.hold("F"), Self.place(FixtureBank.home, 0)),  // LOOPER BACK hold [0,0,6]
        ])
        #expect(h.bytes.isEmpty)
    }

    @Test("S10: DAW to HOME sends nothing, so no Stop")
    func s10DawHome() throws {
        let h = EngineHarness(try Fixture.backup())
        Self.walk(h, [
            (.tap("D"), Self.place(FixtureBank.daw, 0)),  // HOME DAW [4,0,6]
            (.hold("F"), Self.place(FixtureBank.home, 0)),  // DAW NEXT hold [0,0,6]
        ])
        #expect(h.bytes.isEmpty)
    }
}
