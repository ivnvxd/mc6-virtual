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
    /// `enter` holds the On Enter Bank messages of each bank (V21).
    static func backup(
        _ banks: [[[Message]]], sendToPort: [Int] = Array(repeating: 130, count: 16), pageLimit: Int = 0,
        expressions: [[Message]] = [], longPressTime: Int = 12, enter: [Int: [BankMessage]] = [:]
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
                    },
                    enterMessages: enter[number] ?? [])
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

    @Test("V20: no press action runs a No Action message")
    func noActionNeverPressed() {
        let h = EngineHarness(Self.backup([[[Self.message(0, Self.ccCommand(1), action: SwitchAction.noAction)]]]))
        for action in SwitchAction.all { h.engine.enqueue(Self.a, action) }
        #expect(h.bytes.isEmpty)
    }

    @Test("V20: an Engage with the target action No Action runs only the No Action messages of its target")
    func engageNoAction() {
        let h = EngineHarness(Self.backup([[
            [Self.message(0, .engage(bank: 0, preset: 1, action: SwitchAction.noAction))],
            [Self.message(0, Self.ccCommand(1), action: SwitchAction.noAction), Self.message(1, Self.ccCommand(2))],
        ]]))
        h.tap(bank: 0, preset: 0)
        #expect(h.bytes == [[0xB0, 1, 127]])
    }

    /// Bank 0 with scroll preset A, whose Release messages send CC 0 to 5 in their slot, and preset B, whose Release
    /// cues A. `releaseSlots` and `others` place A's messages.
    static func scrollBackup(cue: Command, releaseSlots: [Int] = Array(0..<6), others: [Message] = []) -> Backup {
        let releases = releaseSlots.map { Self.message($0, Self.ccCommand(UInt8($0))) }
        var backup = Self.backup([[[], [Self.message(0, cue)]]])
        var presets = backup.banks[0].presets
        presets[0] = Preset(shortName: "", toggleName: "", toMsgScroll: true, messages: (releases + others).sorted { $0.slot < $1.slot })
        let bank = backup.banks[0]
        backup = Backup(
            original: Data(), banks: [Bank(number: 0, name: "", pageLimit: 0, presets: presets, expressions: bank.expressions)],
            productionBanks: [0], longPressTime: 12, sendToPort: backup.sendToPort, notes: [])
        return backup
    }

    @Test("V23: a cue at a Release slot starts the next Release there, also in the middle of a group")
    func scrollCueMidGroup() {
        let h = EngineHarness(Self.scrollBackup(cue: .scrollCounter(preset: 0, slot: 1)))
        h.engine.state.messageScroll[Self.a] = MessageScroll(groupSize: 2)
        h.engine.enqueue(Self.b, SwitchAction.release)
        for _ in 0..<4 { h.engine.enqueue(Self.a, SwitchAction.release) }
        #expect(h.bytes == [[0xB0, 1, 127], [0xB0, 2, 127], [0xB0, 3, 127], [0xB0, 4, 127], [0xB0, 5, 127], [0xB0, 0, 127], [0xB0, 1, 127]])
    }

    @Test("V23: a cue at a slot without a Release message starts at the next Release message, or at the first")
    func scrollCueOtherSlot() {
        let press = Self.message(3, Self.ccCommand(99), action: SwitchAction.press)
        let next = EngineHarness(Self.scrollBackup(cue: .scrollCounter(preset: 0, slot: 3), releaseSlots: [0, 2, 4], others: [press]))
        next.engine.enqueue(Self.b, SwitchAction.release)
        next.engine.enqueue(Self.a, SwitchAction.release)
        #expect(next.bytes == [[0xB0, 4, 127]])
        let none = EngineHarness(Self.scrollBackup(cue: .scrollCounter(preset: 0, slot: 5), releaseSlots: [0, 2, 4]))
        none.engine.enqueue(Self.a, SwitchAction.release)
        none.engine.enqueue(Self.b, SwitchAction.release)
        none.engine.enqueue(Self.a, SwitchAction.release)
        #expect(none.bytes == [[0xB0, 0, 127], [0xB0, 0, 127]])
    }

    @Test("V23: Reset (127) starts the next Release at the first message")
    func scrollCueReset() {
        let h = EngineHarness(Self.scrollBackup(cue: .scrollCounter(preset: 0, slot: nil)))
        h.engine.enqueue(Self.a, SwitchAction.release)
        h.engine.enqueue(Self.a, SwitchAction.release)
        h.engine.enqueue(Self.b, SwitchAction.release)
        h.engine.enqueue(Self.a, SwitchAction.release)
        #expect(h.bytes == [[0xB0, 0, 127], [0xB0, 1, 127], [0xB0, 0, 127]])
    }

    @Test("V23: preset 127 cues the frame preset itself")
    func scrollCueSelf() {
        let cue = Self.message(10, .scrollCounter(preset: nil, slot: 2), action: SwitchAction.press)
        let h = EngineHarness(Self.scrollBackup(cue: .togglePreset, others: [cue]))
        h.engine.enqueue(Self.a, SwitchAction.press)
        h.engine.enqueue(Self.a, SwitchAction.release)
        #expect(h.bytes == [[0xB0, 2, 127]])
    }

    // MARK: - On Enter Bank (V21)

    /// An On Enter Bank message that engages `target` with Release.
    static func enter(_ slot: Int, _ target: PresetAddress, once: Bool = false) -> BankMessage {
        BankMessage(slot: slot, once: once, target: target, action: SwitchAction.release, pointer: "/synthetic/bank/\(slot)")
    }

    static func jump(_ bank: Int, enter: Bool = true) -> Command { .bankJump(.bank(bank, page: 0), enter: enter) }

    /// Bank 1 enters with its preset A, which sends CC 5.
    static let bank1 = [[Self.message(0, Self.ccCommand(5))]]

    @Test("V21: a Bank Jump with the enter bit runs the new bank's enter messages after the running action, before the next press")
    func enterAfterAction() {
        let h = EngineHarness(Self.backup(
            [[[Self.message(0, Self.jump(1)), Self.message(1, .delay(ms: 10)), Self.message(2, Self.ccCommand(1))],
              [Self.message(0, Self.ccCommand(9))]], Self.bank1],
            enter: [1: [Self.enter(0, PresetAddress(bank: 1, preset: 0))]]))
        h.engine.enqueue(Self.a, SwitchAction.release)
        h.engine.enqueue(Self.b, SwitchAction.release)
        h.scheduler.advance(by: .milliseconds(10))
        #expect(h.bytes == [[0xB0, 1, 127], [0xB0, 5, 127], [0xB0, 9, 127]])
    }

    @Test("V21: a bank step and a sidebar step into a bank with enter messages run them")
    func enterOnSteps() {
        let h = EngineHarness(Self.backup(
            [[[], [], [Self.message(0, Self.ccCommand(7))]], Self.bank1],
            enter: [0: [Self.enter(0, Self.c)], 1: [Self.enter(0, PresetAddress(bank: 1, preset: 0))]]))
        h.engine.navigate(.bankUp)
        #expect(h.bytes == [[0xB0, 5, 127]])
        h.engine.navigate(.select(0))
        #expect(h.bytes == [[0xB0, 5, 127], [0xB0, 7, 127]])
    }

    @Test("V21: a Bank Jump on Release runs the enter messages before the same gesture's Release All")
    func enterBeforeReleaseAll() {
        let h = EngineHarness(Self.backup(
            [[[Self.message(0, Self.jump(1)), Self.message(1, Self.ccCommand(2), action: SwitchAction.releaseAll)]], Self.bank1],
            enter: [1: [Self.enter(0, PresetAddress(bank: 1, preset: 0))]]))
        h.tap(bank: 0, preset: 0)
        #expect(h.bytes == [[0xB0, 5, 127], [0xB0, 2, 127]])
    }

    @Test("V21: a Bank Jump without the enter bit, a jump within the bank and an Engage of another bank run no enter messages")
    func noEnter() {
        let enter: [Int: [BankMessage]] = [0: [Self.enter(0, Self.c)], 1: [Self.enter(0, PresetAddress(bank: 1, preset: 0))]]
        let bank0 = [
            [Self.message(0, Self.jump(1, enter: false))],
            [Self.message(0, Self.jump(0))],
            [Self.message(0, Self.ccCommand(7))],
            [Self.message(0, .engage(bank: 1, preset: 1, action: SwitchAction.release))],
        ]
        let banks = [bank0, Self.bank1 + [[Self.message(0, Self.ccCommand(6))]]]
        let jump = EngineHarness(Self.backup(banks, enter: enter))
        jump.engine.enqueue(Self.a, SwitchAction.release)
        #expect(jump.bytes.isEmpty)
        #expect(jump.engine.state.bank == 1)
        let same = EngineHarness(Self.backup(banks, enter: enter))
        same.engine.enqueue(Self.b, SwitchAction.release)
        #expect(same.bytes.isEmpty)
        let engage = EngineHarness(Self.backup(banks, enter: enter))
        engage.engine.enqueue(PresetAddress(bank: 0, preset: 3), SwitchAction.release)
        #expect(engage.bytes == [[0xB0, 6, 127]])
    }

    @Test("V21: two jumps in one action run the enter messages of both banks in order")
    func enterTwoBanks() {
        let h = EngineHarness(Self.backup(
            [[[Self.message(0, Self.jump(1)), Self.message(1, Self.jump(2))]], Self.bank1, [[Self.message(0, Self.ccCommand(6))]]],
            enter: [1: [Self.enter(0, PresetAddress(bank: 1, preset: 0))], 2: [Self.enter(0, PresetAddress(bank: 2, preset: 0))]]))
        h.engine.enqueue(Self.a, SwitchAction.release)
        #expect(h.bytes == [[0xB0, 5, 127], [0xB0, 6, 127]])
    }

    @Test("V21: cancel drops pending enter messages")
    func cancelDropsEnter() {
        let h = EngineHarness(Self.backup(
            [[[Self.message(0, Self.jump(1)), Self.message(1, .delay(ms: 10))]], Self.bank1],
            enter: [1: [Self.enter(0, PresetAddress(bank: 1, preset: 0))]]))
        h.engine.enqueue(Self.a, SwitchAction.release)
        h.engine.cancel()
        h.scheduler.advance(by: .milliseconds(10))
        #expect(h.bytes.isEmpty)
    }

    @Test("V21, V22: power-on runs the shown bank's enter messages; a once-only message runs again only after a reset")
    func enterOnce() {
        let h = EngineHarness(Self.backup(
            [[[], [], [Self.message(0, Self.ccCommand(7))], [Self.message(0, Self.ccCommand(8))]], Self.bank1],
            enter: [0: [Self.enter(0, Self.c, once: true), Self.enter(1, PresetAddress(bank: 0, preset: 3))]]))
        h.engine.powerOn()
        #expect(h.bytes == [[0xB0, 7, 127], [0xB0, 8, 127]])
        h.engine.navigate(.bankUp)
        h.engine.navigate(.bankDown)
        #expect(h.bytes == [[0xB0, 7, 127], [0xB0, 8, 127], [0xB0, 8, 127]])
        h.engine.reset()
        h.engine.powerOn()
        #expect(h.bytes.suffix(2) == [[0xB0, 7, 127], [0xB0, 8, 127]])
    }

    @Test("V21: two banks whose enter messages jump to each other stop at the message limit")
    func enterLoop() {
        let h = EngineHarness(Self.backup(
            [[[Self.message(0, Self.jump(1))]], [[Self.message(0, Self.jump(0))]]],
            enter: [0: [Self.enter(0, Self.a)], 1: [Self.enter(0, PresetAddress(bank: 1, preset: 0))]]))
        h.engine.powerOn()
        #expect(h.faults.count == 1)
        guard case .budgetLimit = h.faults.first else { Issue.record("expected the budget limit"); return }
    }

    // MARK: - Limits
    // MARK: - Limits
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

    @MainActor final class Port2FailingSink: MidiSink {
        func send(_ bytes: [UInt8], to ports: Ports) throws {
            throw PartialSend(delivered: .port1, underlying: FailingSink.Failure())
        }
    }

    @Test("A send that fails on port 2 logs the output on port 1, then reports the fault")
    func partialSendError() {
        let engine = Engine(
            backup: Self.backup([[[Self.message(0, Self.ccCommand(1)), Self.message(1, Self.ccCommand(2))]]]),
            scheduler: FakeScheduler(), sink: Port2FailingSink())
        var events: [String] = []
        engine.onOutput = { bytes, ports, pointer in events.append("output \(bytes) \(ports.numbers) \(pointer)") }
        engine.onFault = { events.append("fault \($0.pointer) \($0.reason)") }
        engine.enqueue(Self.a, 2)
        #expect(events == ["output [176, 1, 127] [1] /synthetic/0", "fault /synthetic/0 send failed: Failure()"])
        #expect(engine.generation == 1)
    }

    @Test("V04: engage reports whether it queued the tap: false on a hidden page", .needsSpec)
    func engageResult() throws {
        let h = EngineHarness(try Fixture.backup())
        // HOME has one page: I (preset 8) is hidden, C (preset 2) is shown.
        #expect(!h.engine.engage(preset: 8))
        #expect(h.engine.engage(preset: 2))
    }
}
