import Testing
@testable import MC6Core

/// Spec section 9, S2 to S5, on the fixture. Expected bytes come from inventory/BANK-MANIFEST.md.
@MainActor @Suite struct ToneScenarioTests {
    // Bank IDs and stored preset indices of the fixture.
    static let pedals = 2, core = 5, nolly = 9
    static let toneBanks = 5...12

    static func cc(_ channel: UInt8, _ number: UInt8, _ value: UInt8) -> [UInt8] { [0xB0 | (channel - 1), number, value] }
    static func pc(_ channel: UInt8, _ program: UInt8) -> [UInt8] { [0xC0 | (channel - 1), program] }

    /// PEDALS X (RST FX) from Position 1 helpers: CC42/43 ch1, CC50/52 ch2, then W calls U (CC51 ch2).
    static let pedalsResetFX: [[UInt8]] = [cc(1, 42, 0), cc(1, 43, 0), cc(2, 50, 0), cc(2, 52, 0), cc(2, 51, 0)]
    /// PEDALS V (RST DLY/REV): CC40/41 ch1.
    static let pedalsResetDelayReverb: [[UInt8]] = [cc(1, 40, 0), cc(1, 41, 0)]

    @Test("S2: CORE A Release runs bank 5 W fully, then CC60=107, 50 ms, PC3 ch2, CC62=21, and toggles A")
    func s2CoreA() throws {
        let h = EngineHarness(try Fixture.backup())
        h.tap(bank: Self.core, preset: 0)
        h.scheduler.advance(by: .milliseconds(100))
        // Bank 5 W: CC61/63/64=0 ch1, PEDALS X (with W and U), PEDALS V, then the X of each tone bank (state only).
        let atStart = [Self.cc(1, 61, 0), Self.cc(1, 63, 0), Self.cc(1, 64, 0)]
            + Self.pedalsResetFX + Self.pedalsResetDelayReverb + [Self.cc(1, 60, 107)]
        let expected = atStart.map { RecordingSink.Sent(time: .zero, bytes: $0, ports: [.port1, .port2]) } + [
            .init(time: .milliseconds(50), bytes: [193, 3], ports: [.port1, .port2]),
            .init(time: .milliseconds(50), bytes: Self.cc(1, 62, 21), ports: [.port1, .port2]),
        ]
        #expect(h.sink.sent == expected)
        #expect(h.engine.state[position: PresetAddress(bank: Self.core, preset: 0)] == .two)
        #expect(h.faults.isEmpty)
    }

    @Test("S3/U03: NOLLY A Release engages W of bank 9, sends PC2 ch5, runs PEDALS A without a screen change")
    func s3NollyA() throws {
        let h = EngineHarness(try Fixture.backup())
        h.engine.state.bank = Self.nolly
        h.tap(bank: Self.nolly, preset: 0)
        h.scheduler.advance(by: .milliseconds(100))
        // Bank 9 W sends CC63=127, where bank 5 W would send CC63=0 and CC64=0.
        let atStart = [Self.cc(1, 61, 0), Self.cc(1, 63, 127)]
            + Self.pedalsResetFX + Self.pedalsResetDelayReverb + [Self.cc(1, 64, 16)]
        let boostOn = [2, 5, 6, 7, 8].map { Self.cc($0, 50, 127) }
        let expected = atStart.map { RecordingSink.Sent(time: .zero, bytes: $0, ports: [.port1, .port2]) }
            + ([[196, 2]] + boostOn).map { RecordingSink.Sent(time: .milliseconds(50), bytes: $0, ports: [.port1, .port2]) }
        #expect(h.sink.sent == expected)
        #expect(h.engine.state[position: PresetAddress(bank: Self.pedals, preset: 0)] == .two)
        #expect(h.engine.state[position: PresetAddress(bank: Self.nolly, preset: 0)] == .two)
        #expect(h.engine.state.bank == Self.nolly)
        #expect(h.engine.state.page == 0)
        #expect(h.faults.isEmpty)
    }

    @Test("S4: from all Position 2, each reset helper sets Position 1 in its own bank only")
    func s4FromPosition2() throws {
        let backup = try Fixture.backup()
        let h = EngineHarness(backup)
        h.engine.state.positions = backup.banks.map { Array(repeating: .two, count: $0.presets.count) }
        h.engine.state.expressionMasks[0] = 0b10
        h.engine.enqueue(PresetAddress(bank: Self.core, preset: 22), 2)  // CORE W (RST ALL)
        h.scheduler.advance(by: .milliseconds(100))

        // PEDALS X [81,5] c1: A E G H J. PEDALS W [0,65,6] c1: H N P Q, then [0,32,0] c2: M to Position 2.
        // PEDALS V [10,0] c1: B D.
        let pedalsOne: Set = [0, 4, 6, 7, 9, 13, 15, 16, 1, 3]
        // Tone bank X [125,30] c1: A C D E F G I J K L; bank 8 X [121,28] c1: A D E F G J K L.
        let toneOne: Set = [0, 2, 3, 4, 5, 6, 8, 9, 10, 11]
        let bank8One: Set = [0, 3, 4, 5, 6, 9, 10, 11]
        for bank in backup.banks.indices {
            let one: Set<Int> = switch bank {
            case Self.pedals: pedalsOne
            case 8: bank8One
            case Self.toneBanks: toneOne
            default: []
            }
            let expected = (0..<24).map { one.contains($0) ? Position.one : .two }
            #expect(h.engine.state.positions[bank] == expected, "bank \(bank)")
        }
        #expect(h.engine.state.expressionMasks == [1, 1, 1, 1])
        // PEDALS U is at Position 2 here, so its tg=1 lines (CC51=0 on ch5 to ch8) run after its tg=2 line.
        let pedalsU = [Self.cc(2, 51, 0)] + [5, 6, 7, 8].map { Self.cc($0, 51, 0) }
        #expect(h.bytes == [Self.cc(1, 61, 0), Self.cc(1, 63, 0), Self.cc(1, 64, 0)]
            + Self.pedalsResetFX.dropLast() + pedalsU + Self.pedalsResetDelayReverb)
        #expect(h.faults.isEmpty)
    }

    @Test("S4: from all Position 1, the reset chain changes only PEDALS M, to Position 2, and selects message 0")
    func s4FromPosition1() throws {
        let backup = try Fixture.backup()
        let h = EngineHarness(backup)
        h.engine.state.expressionMasks[0] = 1 << 17 | 1 << 1
        h.engine.enqueue(PresetAddress(bank: Self.core, preset: 22), 2)
        h.scheduler.advance(by: .milliseconds(100))
        for bank in backup.banks.indices {
            let expected = (0..<24).map { bank == Self.pedals && $0 == 12 ? Position.two : .one }
            #expect(h.engine.state.positions[bank] == expected, "bank \(bank)")
        }
        #expect(h.engine.state.expressionMasks == [1, 1, 1, 1])
    }

    @Test("S5: BOOST pressed twice sends the Position 1 group, then the Position 2 group")
    func s5BoostTwice() throws {
        let h = EngineHarness(try Fixture.backup())
        let boost = PresetAddress(bank: Self.pedals, preset: 0)
        let channels: [UInt8] = [2, 5, 6, 7, 8]
        h.tap(bank: boost.bank, preset: boost.preset)
        #expect(h.bytes == channels.map { Self.cc($0, 50, 127) })
        #expect(h.engine.state[position: boost] == .two)
        h.tap(bank: boost.bank, preset: boost.preset)
        #expect(h.bytes == channels.map { Self.cc($0, 50, 127) } + channels.map { Self.cc($0, 50, 0) })
        #expect(h.engine.state[position: boost] == .one)
    }
}
