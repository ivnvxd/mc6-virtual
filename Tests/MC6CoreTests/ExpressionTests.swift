import Testing
@testable import MC6Core

/// Expression output (spec 7.6, 7.13, S9) with U06 and U11. Expected bytes come from inventory/BANK-MANIFEST.md:
/// expression input 1 of every production bank has m0 CC70 ch1, m1 CC71 ch2, m5 CC71 ch5, m9 CC71 ch6,
/// m13 CC71 ch7, m17 CC71 ch8. Inputs 2 to 4 have no messages.
@MainActor @Suite struct ExpressionTests {
    // Bank IDs and stored preset indices of the fixture.
    static let pedals = 2, daw = 4
    /// PEDALS H (WAH/SWEEP): Position 1 Release selects `[0,0,17,8,34]`, Position 2 Release `[0,0,0,0,1]`.
    static let wah = PresetAddress(bank: pedals, preset: 7)

    static func cc(_ channel: UInt8, _ number: UInt8, _ value: UInt8) -> [UInt8] { [0xB0 | (channel - 1), number, value] }

    /// Messages 1, 5, 9, 13 and 17 of input 1 at `value`.
    static func wahOutput(_ value: UInt8) -> [[UInt8]] { [2, 5, 6, 7, 8].map { cc($0, 71, value) } }

    /// The bytes sent by one expression move.
    static func move(_ h: EngineHarness, input: Int, to value: Int) -> [[UInt8]] {
        let before = h.bytes.count
        h.engine.moveExpression(input: input, to: value)
        return Array(h.bytes[before...])
    }

    // MARK: - S9

    @Test("S9: after [0,0,17,8,34], input 1 sends exactly messages 1, 5, 9, 13 and 17, each on its own channel")
    func s9SelectWah() throws {
        let h = EngineHarness(try Fixture.backup())
        h.tap("B")  // HOME PEDALS
        h.tap(bank: Self.wah.bank, preset: Self.wah.preset)
        let before = h.sink.sent.count
        h.engine.moveExpression(input: 0, to: 100)
        let expected = Self.wahOutput(100).map { RecordingSink.Sent(time: .zero, bytes: $0, ports: [.port1, .port2]) }
        #expect(Array(h.sink.sent[before...]) == expected)
        #expect(h.faults.isEmpty)
    }

    @Test("S9: after [0,0,0,0,1], input 1 sends only message 0")
    func s9SelectVolume() throws {
        let h = EngineHarness(try Fixture.backup())
        h.tap("B")
        h.tap(bank: Self.wah.bank, preset: Self.wah.preset)  // Position 1: [0,0,17,8,34]
        h.tap(bank: Self.wah.bank, preset: Self.wah.preset)  // Position 2: [0,0,0,0,1]
        #expect(Self.move(h, input: 0, to: 90) == [Self.cc(1, 70, 90)])
    }

    // MARK: - U06

    @Test("U06: at startup each input selects message 0 only")
    func u06Startup() throws {
        let h = EngineHarness(try Fixture.backup())
        #expect(h.engine.state.expressionMasks == [1, 1, 1, 1])
        #expect(Self.move(h, input: 0, to: 64) == [Self.cc(1, 70, 64)])
        // Inputs 2 to 4 have no messages, so they send nothing.
        for input in 1...3 { #expect(Self.move(h, input: input, to: 64).isEmpty) }
    }

    @Test("U06: a selection sends nothing until the pedal moves")
    func u06SelectionSendsNothing() throws {
        let h = EngineHarness(try Fixture.backup())
        h.tap("B")
        h.tap(bank: Self.wah.bank, preset: Self.wah.preset)
        // Only the WAH CC51=127 lines on ch2 and ch5 to ch8.
        #expect(h.bytes == [2, 5, 6, 7, 8].map { Self.cc($0, 51, 127) })
    }

    @Test("U06: the mask is global and survives a bank change")
    func u06SurvivesBankChange() throws {
        let h = EngineHarness(try Fixture.backup())
        h.tap("B")
        h.tap(bank: Self.wah.bank, preset: Self.wah.preset)
        h.hold(bank: Self.pedals, preset: 9)  // PEDALS J hold: DAW [4,0,6]
        #expect(h.engine.state.bank == Self.daw)
        #expect(Self.move(h, input: 0, to: 5) == Self.wahOutput(5))
    }

    // MARK: - Values

    @Test("Input values 0, 64 and 127 map to CC values 0, 64 and 127 for min 0, max 127")
    func fixtureValues() throws {
        let h = EngineHarness(try Fixture.backup())
        for value in [0, 64, 127] {
            #expect(Self.move(h, input: 0, to: value) == [Self.cc(1, 70, UInt8(value))])
        }
    }

    static func expression(_ slot: Int, number: Int, channel: Int = 1, min: Int = 0, max: Int = 127) -> Message {
        Message(
            slot: slot, action: 0, gate: .both,
            command: .expression(channel: channel, number: number, min: min, max: max), pointer: "/exp/\(slot)")
    }

    @Test("Spec 7.13: the value is min + round((max - min) * input / 127), also for max below min")
    func scaling() {
        let h = EngineHarness(EngineTests.backup([[]], expressions: [
            [Self.expression(0, number: 7, min: 20, max: 100)],
            [Self.expression(0, number: 8, min: 100, max: 20)],
        ]))
        // 80 * 32 / 127 = 20.16; 80 * 64 / 127 = 40.31; 80 * 95 / 127 = 59.84.
        for (value, scaled) in [(0, 20), (32, 40), (64, 60), (95, 80), (127, 100)] {
            #expect(Self.move(h, input: 0, to: value) == [[0xB0, 7, UInt8(scaled)]])
            #expect(Self.move(h, input: 1, to: value) == [[0xB0, 8, UInt8(120 - scaled)]])
        }
    }

    @Test("Spec 7.6: mask bit n selects the message in slot n, not the n-th non-empty message")
    func maskUsesSlot() {
        let h = EngineHarness(EngineTests.backup(
            [[[EngineTests.message(0, .selectExpression(input: 0, mask: 1 << 5))]]],
            expressions: [[Self.expression(0, number: 1), Self.expression(5, number: 2)]]))
        h.engine.enqueue(EngineTests.a, 2)
        #expect(Self.move(h, input: 0, to: 9) == [[0xB0, 2, 9]])
    }

    // MARK: - Queue (U11)

    @Test("U11: moves wait for the running trigger and the newest pending value of an input wins")
    func coalescing() throws {
        let h = EngineHarness(try Fixture.backup())
        h.tap("C")  // HOME TAP: CC26=127, 10 ms, CC26=0, Clock Tap
        for value in [10, 20, 30] { h.engine.moveExpression(input: 0, to: value) }
        #expect(h.bytes == [Self.cc(1, 26, 127)])
        h.scheduler.advance(by: .milliseconds(100))
        let expected = [
            RecordingSink.Sent(time: .zero, bytes: Self.cc(1, 26, 127), ports: [.port1, .port2]),
            RecordingSink.Sent(time: .milliseconds(10), bytes: Self.cc(1, 26, 0), ports: [.port1, .port2]),
            RecordingSink.Sent(time: .milliseconds(10), bytes: Self.cc(1, 70, 30), ports: [.port1, .port2]),
        ]
        #expect(h.sink.sent == expected)
        #expect(h.taps == [.milliseconds(10)])
    }

    @Test("U11: a move never jumps over a pending trigger, and inputs coalesce separately")
    func noCoalescingAcrossTrigger() {
        let h = EngineHarness(EngineTests.backup(
            [[[EngineTests.message(0, .delay(ms: 50)), EngineTests.message(1, EngineTests.cc(1))], [EngineTests.message(0, EngineTests.cc(2))]]],
            expressions: [[Self.expression(0, number: 7)], [Self.expression(0, number: 8, channel: 2)]]))
        h.engine.enqueue(EngineTests.a, 2)
        h.engine.moveExpression(input: 0, to: 10)
        h.engine.enqueue(EngineTests.b, 2)
        h.engine.moveExpression(input: 0, to: 20)
        h.engine.moveExpression(input: 1, to: 5)
        h.engine.moveExpression(input: 0, to: 30)
        h.scheduler.advance(by: .milliseconds(100))
        #expect(h.bytes == [[0xB0, 1, 127], [0xB0, 7, 10], [0xB0, 2, 127], [0xB0, 7, 30], [0xB1, 8, 5]])
    }

    @Test("A generation bump drops pending moves")
    func cancelDropsMoves() {
        let h = EngineHarness(EngineTests.backup(
            [[[EngineTests.message(0, .delay(ms: 50))]]], expressions: [[Self.expression(0, number: 7)]]))
        h.engine.enqueue(EngineTests.a, 2)
        h.engine.moveExpression(input: 0, to: 10)
        h.engine.cancel()
        h.scheduler.advance(by: .milliseconds(100))
        #expect(h.bytes.isEmpty)
    }
}
