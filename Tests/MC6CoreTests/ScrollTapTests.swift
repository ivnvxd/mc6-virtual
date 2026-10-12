import Testing
@testable import MC6Core

/// Message scroll, Rename and Clock Tap (spec 7.9, 7.11, 7.12, S6, S8) with U07, U09 and U10.
/// Expected bytes and names come from inventory/BANK-MANIFEST.md.
@MainActor @Suite struct ScrollTapTests {
    /// PEDALS K (SPACE), page 2 physical E: Press `[6,4,2]`, Release m0 to m5 = three CC62 + Rename pairs.
    static let space = PresetAddress(bank: FixtureBank.pedals, preset: 10)

    /// Taps physical button E on the shown page and returns the bytes it sent.
    static func tapE(_ h: EngineHarness) -> [[UInt8]] {
        let before = h.bytes.count
        h.tap("E")
        return Array(h.bytes[before...])
    }

    // MARK: - S6 and U07

    @Test("S6: SPACE Releases send CC62=64 \\@ CLEAR, CC62=107 \\N DEEP, CC62=22 \\S NORMAL, then wrap")
    func s6Space() throws {
        let h = EngineHarness(try Fixture.backup())
        h.hold("B")  // HOME PEDALS page 2
        let groups: [(UInt8, String)] = [
            (64, "\\@ CLEAR"), (107, "\\N DEEP"), (22, "\\S NORMAL"), (64, "\\@ CLEAR"), (107, "\\N DEEP"),
        ]
        for (value, name) in groups {
            #expect(Self.tapE(h) == [cc(1, 62, value)])
            #expect(h.engine.state.names[Self.space] == name)
        }
        #expect(h.engine.state.messageScroll[Self.space]?.groupSize == 2)
        #expect(h.faults.isEmpty)
    }

    @Test("U07: the pointer survives a trip out of PEDALS, and a hold does not advance it")
    func u07PointerSurvives() throws {
        let h = EngineHarness(try Fixture.backup())
        h.hold("B")
        #expect(Self.tapE(h) == [cc(1, 62, 64)])
        let before = h.bytes.count
        h.hold("E")  // SPACE hold: LOOPER [3,0,6]
        #expect(h.bytes.count == before)
        #expect(h.engine.state.place == Place(bank: FixtureBank.looper, page: 0))
        h.tap("F")  // LOOPER BACK [0,126,6]
        #expect(h.engine.state.place == Place(bank: FixtureBank.pedals, page: 1))
        #expect(Self.tapE(h) == [cc(1, 62, 107)])
        #expect(h.engine.state.names[Self.space] == "\\N DEEP")
    }

    // MARK: - U09

    @Test("U09: a temporary name stays across banks and other presses until reset")
    func u09NameUntilReset() throws {
        let backup = try Fixture.backup()
        let h = EngineHarness(backup)
        h.hold("B")
        _ = Self.tapE(h)
        h.tap("B")  // PEDALS H (WAH/SWEEP) to Position 2
        h.hold("E")  // to LOOPER
        h.tap("A")  // LOOPER LOOP
        #expect(h.engine.state.names == [Self.space: "\\@ CLEAR"])
        h.engine.reset()
        #expect(h.engine.state == RuntimeState(backup: backup))
        #expect(h.engine.state.names.isEmpty)
    }

    // MARK: - S8 and U10

    @Test("S8/U10: a short TAP Release sends CC26 127, 10 ms, CC26 0, then reports the tap")
    func s8TapRelease() throws {
        let backup = try Fixture.backup()
        let expected = [
            RecordingSink.Sent(time: .zero, bytes: cc(1, 26, 127), ports: [.port1, .port2]),
            RecordingSink.Sent(time: .milliseconds(10), bytes: cc(1, 26, 0), ports: [.port1, .port2]),
        ]
        let home = EngineHarness(backup)
        home.tap("C")  // HOME C TAP
        home.scheduler.advance(by: .milliseconds(100))
        #expect(home.sink.sent == expected)
        #expect(home.taps == [.milliseconds(10)])

        let looper = EngineHarness(backup)
        looper.tap("E")  // HOME LOOPER
        looper.tap("C")  // LOOPER C TAP
        looper.scheduler.advance(by: .milliseconds(100))
        #expect(looper.sink.sent == expected)
        #expect(looper.taps == [.milliseconds(10)])
    }

    @Test("S8: a TAP hold sends no pulse, reports no tap, and leaves bank and page unchanged")
    func s8TapHold() throws {
        let backup = try Fixture.backup()
        for bank in [FixtureBank.home, FixtureBank.looper] {
            let h = EngineHarness(backup)
            h.engine.state.bank = bank
            h.hold("C")  // PageUp in a bank with pageLimit 1
            h.scheduler.advance(by: .milliseconds(100))
            #expect(h.bytes.isEmpty, "bank \(bank)")
            #expect(h.taps.isEmpty, "bank \(bank)")
            #expect(h.engine.state.place == Place(bank: bank, page: 0), "bank \(bank)")
        }
    }
}
