import Foundation
import Testing
@testable import MC6Core

/// Engine rules from spec section 5.3 and the plan's Engine flow, on small synthetic backups.
@MainActor @Suite struct EngineTests {
    // MARK: - Synthetic backups

    /// A message in `slot`; Release (2) and both positions unless given.
    static func message(_ slot: Int, _ command: Command, action: Int = 2, gate: Gate = .both) -> Message {
        Message(slot: slot, action: action, gate: gate, command: command, pointer: "/synthetic/\(slot)")
    }

    static func ccCommand(_ number: UInt8, _ value: UInt8 = 127, channel: UInt8 = 0) -> Command {
        .midi([0xB0 | channel, number, value])
    }

    /// A backup with the given messages per preset per bank; missing presets are empty.
    /// `expressions` are the messages of expression inputs 1 to 4, the same in every bank.
    static func backup(
        _ banks: [[[Message]]], sendToPort: [Int] = Array(repeating: 130, count: 16), pageLimit: Int = 0,
        expressions: [[Message]] = [], longPressTime: Int = 12
    ) -> Backup {
        let empty = Preset(shortName: "", toggleName: "", toMsgScroll: false, messages: [])
        return Backup(
            original: Data(),
            banks: banks.enumerated().map { number, presets in
                Bank(
                    number: number, name: "", pageLimit: pageLimit,
                    presets: (0..<24).map { index in
                        guard index < presets.count else { return empty }
                        return Preset(shortName: "", toggleName: "", toMsgScroll: false, messages: presets[index])
                    },
                    expressions: (0..<4).map { input in
                        guard input < expressions.count else { return empty }
                        return Preset(shortName: "", toggleName: "", toMsgScroll: false, messages: expressions[input])
                    })
            },
            productionBanks: Set(banks.indices), longPressTime: longPressTime, sendToPort: sendToPort, notes: [])
    }

    static let a = PresetAddress(bank: 0, preset: 0)
    static let b = PresetAddress(bank: 0, preset: 1)
    static let c = PresetAddress(bank: 0, preset: 2)

    // MARK: - Order and gates

    @Test("Messages run in slot order, only those of the triggered action")
    func slotOrder() {
        let h = EngineHarness(Self.backup([[[
            Self.message(0, Self.ccCommand(1)),
            Self.message(1, Self.ccCommand(2), action: 3),
            Self.message(5, Self.ccCommand(3)),
            Self.message(6, Self.ccCommand(4), action: 1),
            Self.message(31, Self.ccCommand(5)),
        ]]]))
        h.engine.enqueue(Self.a, 2)
        #expect(h.bytes == [[0xB0, 1, 127], [0xB0, 3, 127], [0xB0, 5, 127]])
    }

    @Test("A short press runs Press, Release, Release All in that order")
    func shortPress() {
        let h = EngineHarness(Self.backup([[[
            Self.message(0, Self.ccCommand(9), action: 9),
            Self.message(1, Self.ccCommand(2), action: 2),
            Self.message(2, Self.ccCommand(1), action: 1),
        ]]]))
        h.tap(bank: 0, preset: 0)
        #expect(h.bytes == [[0xB0, 1, 127], [0xB0, 2, 127], [0xB0, 9, 127]])
    }

    @Test("U02: tg reads the live position, so a gate after Toggle Preset sees the new position")
    func liveGate() {
        let h = EngineHarness(Self.backup([[[
            Self.message(0, Self.ccCommand(1), gate: .position1),
            Self.message(1, .togglePreset),
            Self.message(2, Self.ccCommand(2), gate: .position2),
            Self.message(3, Self.ccCommand(3), gate: .position1),
        ]]]))
        h.engine.enqueue(Self.a, 2)
        #expect(h.bytes == [[0xB0, 1, 127], [0xB0, 2, 127]])
        #expect(h.engine.state[position: Self.a] == .two)
    }

    @Test("Toggle Preset flips Position 1 and Position 2 on each run")
    func togglePreset() {
        let h = EngineHarness(Self.backup([[[Self.message(0, .togglePreset)]]]))
        h.engine.enqueue(Self.a, 2)
        #expect(h.engine.state[position: Self.a] == .two)
        h.engine.enqueue(Self.a, 2)
        #expect(h.engine.state[position: Self.a] == .one)
    }

    // MARK: - Frames

    @Test("Set Toggle and Toggle Preset in an engaged preset act on the frame bank, not the caller")
    func frameBank() {
        let h = EngineHarness(Self.backup([
            [[Self.message(0, .engage(bank: 1, preset: 0, action: 2))]],
            [[Self.message(0, .setToggle(.two, mask: 0b110)), Self.message(1, .togglePreset)]],
        ]))
        h.engine.enqueue(Self.a, 2)
        let positions = h.engine.state.positions
        #expect(positions[1][0...3] == [.two, .two, .two, .one])
        #expect(positions[0].allSatisfy { $0 == .one })
    }

    @Test("Set Toggle sets Position 1 or 2 only for the presets in the mask")
    func setToggle() {
        let h = EngineHarness(Self.backup([[
            [Self.message(0, .setToggle(.two, mask: 1 << 23 | 1 << 3 | 1))],
            [Self.message(0, .setToggle(.one, mask: 1 << 3))],
        ]]))
        h.engine.enqueue(Self.a, 2)
        h.engine.enqueue(Self.b, 2)
        let expected = (0..<24).map { [0, 23].contains($0) ? Position.two : .one }
        #expect(h.engine.state.positions[0] == expected)
    }

    @Test("Select Expression replaces the mask of its input and sends nothing")
    func selectExpression() {
        let h = EngineHarness(Self.backup([[[Self.message(0, .selectExpression(input: 2, mask: 1 << 31 | 1 << 5))]]]))
        h.engine.enqueue(Self.a, 2)
        #expect(h.engine.state.expressionMasks == [1, 1, 1 << 31 | 1 << 5, 1])
        #expect(h.sink.sent.isEmpty)
    }

    @Test("Engage runs the called action to its end, delay included, before the caller continues")
    func engageCallReturn() {
        let h = EngineHarness(Self.backup([[
            [Self.message(0, Self.ccCommand(1)), Self.message(1, .engage(bank: 0, preset: 1, action: 3)), Self.message(2, Self.ccCommand(4))],
            [Self.message(0, Self.ccCommand(2), action: 3), Self.message(1, .delay(ms: 10), action: 3), Self.message(2, Self.ccCommand(3), action: 3)],
        ]]))
        h.engine.enqueue(Self.a, 2)
        #expect(h.bytes == [[0xB0, 1, 127], [0xB0, 2, 127]])
        h.scheduler.advance(by: .milliseconds(10))
        #expect(h.sink.sent.map(\.time) == [.zero, .zero, .milliseconds(10), .milliseconds(10)])
        #expect(h.bytes == [[0xB0, 1, 127], [0xB0, 2, 127], [0xB0, 3, 127], [0xB0, 4, 127]])
    }

    @Test("Output goes to the ports of the channel's sendToPort mask")
    func ports() {
        var sendToPort = Array(repeating: 130, count: 16)
        sendToPort[2] = 1 << 1
        sendToPort[3] = 1 << 7
        sendToPort[4] = 1
        let h = EngineHarness(Self.backup([[[
            Self.message(0, Self.ccCommand(1, channel: 2)),
            Self.message(1, .midi([0xC3, 7])),
            Self.message(2, Self.ccCommand(3, channel: 4)),
            Self.message(3, Self.ccCommand(4, channel: 0)),
        ]]], sendToPort: sendToPort))
        h.engine.enqueue(Self.a, 2)
        #expect(h.sink.sent.map(\.ports) == [.port1, .port2, [], [.port1, .port2]])
    }

    // MARK: - Limits

    @Test("An Engage deeper than 8 frames stops the trigger, reports the fault and drops the queue")
    func depthLimit() {
        let h = EngineHarness(Self.backup([[
            [Self.message(0, Self.ccCommand(1)), Self.message(1, .engage(bank: 0, preset: 0, action: 2))],
            [Self.message(0, Self.ccCommand(2))],
            [Self.message(0, .delay(ms: 10))],
        ]]))
        h.engine.enqueue(Self.c, 2)
        h.engine.enqueue(Self.a, 2)
        h.engine.enqueue(Self.b, 2)
        h.scheduler.advance(by: .milliseconds(100))
        #expect(h.bytes == Array(repeating: [0xB0, 1, 127], count: 8))
        #expect(h.faults == [.depthLimit(pointer: "/synthetic/1")])
        #expect(h.engine.generation == 1)
    }

    @Test("A trigger that runs more than 512 messages stops, and the next trigger gets a fresh budget")
    func budgetLimit() {
        let h = EngineHarness(Self.backup([[
            (0..<32).map { Self.message($0, .engage(bank: 0, preset: 1, action: 2)) },
            (0..<32).map { Self.message($0, Self.ccCommand(UInt8($0))) },
        ]]))
        h.engine.enqueue(Self.a, 2)
        // Each Engage and each CC counts: 15 full calls (15 * 33 = 495), then an Engage and 16 CCs reach 512.
        #expect(h.sink.sent.count == 15 * 32 + 16)
        #expect(h.faults == [.budgetLimit(pointer: "/synthetic/16")])
        h.engine.enqueue(Self.b, 2)
        #expect(h.sink.sent.count == 15 * 32 + 16 + 32)
        #expect(h.faults.count == 1)
    }

    // MARK: - Queue and generation

    @Test("U11: a second trigger waits for the first, delay included")
    func serialQueue() {
        let h = EngineHarness(Self.backup([[
            [Self.message(0, Self.ccCommand(1)), Self.message(1, .delay(ms: 50)), Self.message(2, Self.ccCommand(2))],
            [Self.message(0, Self.ccCommand(3))],
        ]]))
        h.engine.enqueue(Self.a, 2)
        h.engine.enqueue(Self.b, 2)
        #expect(h.bytes == [[0xB0, 1, 127]])
        h.scheduler.advance(by: .milliseconds(49))
        #expect(h.bytes == [[0xB0, 1, 127]])
        h.scheduler.advance(by: .milliseconds(1))
        #expect(h.sink.sent == [
            .init(time: .zero, bytes: [0xB0, 1, 127], ports: [.port1, .port2]),
            .init(time: .milliseconds(50), bytes: [0xB0, 2, 127], ports: [.port1, .port2]),
            .init(time: .milliseconds(50), bytes: [0xB0, 3, 127], ports: [.port1, .port2]),
        ])
    }

    @Test("A generation bump drops the pending resume and the queue; the next trigger runs normally")
    func generationBump() {
        let h = EngineHarness(Self.backup([[
            [Self.message(0, Self.ccCommand(1)), Self.message(1, .delay(ms: 50)), Self.message(2, Self.ccCommand(2))],
            [Self.message(0, Self.ccCommand(3))],
        ]]))
        h.engine.enqueue(Self.a, 2)
        h.engine.enqueue(Self.b, 2)
        h.engine.cancel()
        #expect(h.engine.generation == 1)
        h.scheduler.advance(by: .milliseconds(100))
        #expect(h.bytes == [[0xB0, 1, 127]])
        h.engine.enqueue(Self.b, 2)
        #expect(h.bytes == [[0xB0, 1, 127], [0xB0, 3, 127]])
        h.engine.enqueue(Self.a, 2)
        h.scheduler.advance(by: .milliseconds(50))
        #expect(h.bytes == [[0xB0, 1, 127], [0xB0, 3, 127], [0xB0, 1, 127], [0xB0, 2, 127]])
    }

    @MainActor final class FailingSink: MidiSink {
        struct Failure: Error {}
        var calls = 0
        func send(_ bytes: [UInt8], to ports: Ports) throws {
            calls += 1
            throw Failure()
        }
    }

    @Test("A send error stops the trigger, reports the fault and bumps the generation")
    func sendError() {
        let sink = FailingSink()
        let engine = Engine(
            backup: Self.backup([[[Self.message(0, Self.ccCommand(1)), Self.message(1, Self.ccCommand(2)), Self.message(2, .togglePreset)]]]),
            scheduler: FakeScheduler(), sink: sink)
        var faults: [EngineFault] = []
        engine.onFault = { faults.append($0) }
        engine.enqueue(Self.a, 2)
        #expect(sink.calls == 1)
        #expect(faults == [.sendFailed(pointer: "/synthetic/0", reason: "Failure()")])
        #expect(engine.state[position: Self.a] == .one)
        #expect(engine.generation == 1)
    }
}
