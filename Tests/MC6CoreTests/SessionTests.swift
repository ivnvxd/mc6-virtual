import Carbon.HIToolbox
import Foundation
import Testing
@testable import MC6Core

/// Session rules from the plan (Task 8, U12) and spec 5.4 and 11: Dry Run, arm, disarm, generations and the log.
/// HOME C (TAP) Release sends CC26 127 on channel 1, waits 10 ms, sends CC26 0 and taps (inventory/BANK-MANIFEST.md).
@MainActor @Suite struct SessionTests {
    /// Channel 1 has `sendToPort` 130: both virtual ports (spec 8.1, 8.2).
    static let both: Ports = [.port1, .port2]
    static let tap = "/data/bankArray/0/presetArray/2/msgArray"

    static func session(output: any MidiSink) throws -> (Session, FakeScheduler) {
        let scheduler = FakeScheduler()
        let session = Session(scheduler: scheduler, output: output)
        session.load(try Fixture.data())
        return (session, scheduler)
    }

    /// Down on HOME C at the current time, up 50 ms later: Release at +50 ms, the second CC and the tap at +60 ms.
    static func tapC(_ session: Session, _ scheduler: FakeScheduler) {
        session.down(.c, source: .mouse)
        scheduler.advance(by: .milliseconds(50))
        session.up(.c, source: .mouse)
    }

    static func output(_ ms: Int, _ value: UInt8, slot: Int, live: Bool) -> LogEntry {
        LogEntry(time: .milliseconds(ms), event: .output(bytes: [0xB0, 26, value], ports: both, pointer: "\(tap)/\(slot)", live: live))
    }

    // MARK: - Dry Run and Live

    @Test("U12: a new session is in Dry Run with no backup, and an import sends nothing")
    func startsInDryRun() throws {
        let scheduler = FakeScheduler()
        let sink = RecordingSink(scheduler: scheduler)
        let session = Session(scheduler: scheduler, output: sink)
        #expect(session.mode == .dryRun)
        #expect(session.backup == nil)
        #expect(session.longPress == nil)
        session.load(try Fixture.data())
        #expect(session.longPress == .milliseconds(700))
        scheduler.advance(by: .seconds(1))
        #expect(session.mode == .dryRun)
        #expect(session.backup?.original == (try Fixture.data()))
        #expect(session.importProblems.isEmpty)
        #expect(session.engine?.state.place == Place(bank: 0, page: 0))
        #expect(session.engine?.state.positions.joined().allSatisfy { $0 == .one } == true)
        #expect(sink.sent.isEmpty)
        #expect(session.log.isEmpty)
    }

    @Test("Dry Run: outputs and taps go to the log only")
    func dryRunLogsOnly() throws {
        let scheduler = FakeScheduler()
        let sink = RecordingSink(scheduler: scheduler)
        let session = Session(scheduler: scheduler, output: sink)
        session.load(try Fixture.data())
        Self.tapC(session, scheduler)
        scheduler.advance(by: .milliseconds(100))
        #expect(sink.sent.isEmpty)
        #expect(session.log == [
            Self.output(50, 127, slot: 0, live: false),
            Self.output(60, 0, slot: 2, live: false),
            LogEntry(time: .milliseconds(60), event: .tap),
        ])
    }

    @Test("Live: an armed session sends to the ports and logs each output as live")
    func liveSends() throws {
        let scheduler = FakeScheduler()
        let sink = RecordingSink(scheduler: scheduler)
        let session = Session(scheduler: scheduler, output: sink)
        session.load(try Fixture.data())
        session.arm()
        #expect(session.mode == .live)
        Self.tapC(session, scheduler)
        scheduler.advance(by: .milliseconds(100))
        #expect(sink.sent == [
            RecordingSink.Sent(time: .milliseconds(50), bytes: [0xB0, 26, 127], ports: Self.both),
            RecordingSink.Sent(time: .milliseconds(60), bytes: [0xB0, 26, 0], ports: Self.both),
        ])
        #expect(session.log == [
            Self.output(50, 127, slot: 0, live: true),
            Self.output(60, 0, slot: 2, live: true),
            LogEntry(time: .milliseconds(60), event: .tap),
        ])
    }

    @Test("Expression moves reach the log with the pointer of the expression message")
    func expressionLogged() throws {
        let scheduler = FakeScheduler()
        let session = Session(scheduler: scheduler, output: RecordingSink(scheduler: scheduler))
        session.load(try Fixture.data())
        session.moveExpression(input: 0, to: 64)
        // HOME expression input 1, message 0: CC70 on channel 1, 0 to 127 (U06: message 0 only).
        #expect(session.log == [LogEntry(time: .zero, event: .output(
            bytes: [0xB0, 70, 64], ports: Self.both, pointer: "/data/bankArray/0/expPresetArray/0/msgArray/0", live: false))])
    }

    // MARK: - Disarm, reset, re-import and errors

    @Test("Arm drops pending Dry Run work: the rest of the sequence never reaches the ports")
    func armDropsPending() throws {
        let scheduler = FakeScheduler()
        let sink = RecordingSink(scheduler: scheduler)
        let session = Session(scheduler: scheduler, output: sink)
        session.load(try Fixture.data())
        let generation = try #require(session.engine).generation
        Self.tapC(session, scheduler)  // CC26 127 at 50 ms in Dry Run, CC26 0 due at 60 ms
        session.arm()
        scheduler.advance(by: .milliseconds(100))
        #expect(session.mode == .live)
        #expect(session.engine?.generation == generation + 1)
        #expect(sink.sent.isEmpty)
        #expect(session.log == [Self.output(50, 127, slot: 0, live: false)])
    }

    @Test("Disarm goes to Dry Run, bumps the engine generation and drops the pending delay")
    func disarmDropsPending() throws {
        let scheduler = FakeScheduler()
        let sink = RecordingSink(scheduler: scheduler)
        let session = Session(scheduler: scheduler, output: sink)
        session.load(try Fixture.data())
        session.arm()
        let generation = try #require(session.engine).generation
        Self.tapC(session, scheduler)  // CC26 127 at 50 ms, CC26 0 due at 60 ms
        session.disarm()
        scheduler.advance(by: .milliseconds(100))
        #expect(session.mode == .dryRun)
        #expect(session.engine?.generation == generation + 1)
        #expect(sink.sent.map(\.bytes) == [[0xB0, 26, 127]])
        #expect(session.log == [Self.output(50, 127, slot: 0, live: true)])
    }

    @Test("Re-import disarms, replaces the engine and cancels the old one")
    func reimport() throws {
        let scheduler = FakeScheduler()
        let sink = RecordingSink(scheduler: scheduler)
        let session = Session(scheduler: scheduler, output: sink)
        session.load(try Fixture.data())
        session.arm()
        let old = try #require(session.engine)
        session.down(.a, source: .mouse)
        session.up(.a, source: .mouse)  // HOME A Release: TONES
        #expect(old.state.bank == 1)
        session.load(try Fixture.data())
        scheduler.advance(by: .seconds(1))
        #expect(session.mode == .dryRun)
        #expect(session.engine !== old)
        #expect(session.engine?.state.place == Place(bank: 0, page: 0))
        #expect(old.generation > 0)
    }

    @Test("Re-import in the middle of a delay: the second CC never goes out")
    func reimportDuringDelay() throws {
        let scheduler = FakeScheduler()
        let sink = RecordingSink(scheduler: scheduler)
        let session = Session(scheduler: scheduler, output: sink)
        session.load(try Fixture.data())
        session.arm()
        Self.tapC(session, scheduler)
        session.load(try Fixture.data())
        scheduler.advance(by: .seconds(1))
        #expect(sink.sent.map(\.bytes) == [[0xB0, 26, 127]])
        #expect(session.log.count == 1)
    }

    @Test("Reset disarms, bumps the engine generation and restores HOME page 1 with all Position 1 (U12)")
    func reset() throws {
        let scheduler = FakeScheduler()
        let session = Session(scheduler: scheduler, output: RecordingSink(scheduler: scheduler))
        session.load(try Fixture.data())
        session.arm()
        let generation = try #require(session.engine).generation
        session.down(.f, source: .mouse)
        session.up(.f, source: .mouse)  // HOME F MUTE toggles to Position 2
        #expect(session.engine?.state[position: PresetAddress(bank: 0, preset: 5)] == .two)
        session.reset()
        #expect(session.mode == .dryRun)
        #expect(session.engine?.generation == generation + 1)
        #expect(session.engine?.state == RuntimeState(backup: try Fixture.backup()))
    }

    @Test("A send error disarms into Error, bumps the engine generation and logs the fault with its pointer")
    func sendError() throws {
        let sink = EngineTests.FailingSink()
        let (session, scheduler) = try Self.session(output: sink)
        session.arm()
        let generation = try #require(session.engine).generation
        Self.tapC(session, scheduler)
        let fault = EngineFault.sendFailed(pointer: "\(Self.tap)/0", reason: "Failure()")
        #expect(session.mode == .error(fault))
        #expect(session.engine?.generation == generation + 1)
        #expect(session.log == [LogEntry(time: .milliseconds(50), event: .fault(fault))])
        // Nothing more goes out until the user arms again.
        scheduler.advance(by: .milliseconds(100))
        Self.tapC(session, scheduler)
        #expect(sink.calls == 1)
        #expect(session.log.last == Self.output(200, 127, slot: 0, live: false))
    }

    @Test("Arm after an error goes Live again, and outputs reach the sink again")
    func armAfterError() throws {
        let sink = EngineTests.FailingSink()
        let (session, scheduler) = try Self.session(output: sink)
        session.arm()
        Self.tapC(session, scheduler)
        #expect(sink.calls == 1)
        session.arm()
        #expect(session.mode == .live)
        scheduler.advance(by: .milliseconds(100))
        Self.tapC(session, scheduler)
        #expect(sink.calls == 2)
    }

    @Test("A send error on a pedal move disarms into Error with the pointer of the expression message")
    func expressionSendError() throws {
        let (session, _) = try Self.session(output: EngineTests.FailingSink())
        session.arm()
        session.moveExpression(input: 0, to: 64)
        let fault = EngineFault.sendFailed(pointer: "/data/bankArray/0/expPresetArray/0/msgArray/0", reason: "Failure()")
        #expect(session.mode == .error(fault))
        #expect(session.log == [LogEntry(time: .zero, event: .fault(fault))])
    }

    @Test("A depth fault in Dry Run also stops in Error and logs the fault")
    func dryRunFault() throws {
        // HOME A Release, slot 31: an Engage of HOME A Release itself, so the call never ends.
        let engage = "/data/bankArray/0/presetArray/0/msgArray/31"
        let scheduler = FakeScheduler()
        let sink = RecordingSink(scheduler: scheduler)
        let session = Session(scheduler: scheduler, output: sink)
        session.load(try Fixture.mutated([.set("\(engage)/t", 27), .set("\(engage)/a", 2), .set("\(engage)/data/2", 2)]))
        #expect(session.importProblems.isEmpty)
        session.down(.a, source: .mouse)
        scheduler.advance(by: .milliseconds(50))
        session.up(.a, source: .mouse)
        let fault = EngineFault.depthLimit(pointer: engage)
        #expect(session.mode == .error(fault))
        #expect(session.log == [LogEntry(time: .milliseconds(50), event: .fault(fault))])
        #expect(sink.sent.isEmpty)
    }

    @Test("A failed import keeps the previous backup and engine, lists the problems and disarms")
    func failedImport() throws {
        let scheduler = FakeScheduler()
        let session = Session(scheduler: scheduler, output: RecordingSink(scheduler: scheduler))
        session.load(try Fixture.data())
        let engine = try #require(session.engine)
        session.arm()
        let generation = engine.generation
        let pointer = "/data/bankArray/0/presetArray/0/msgArray/0/t"
        session.load(try Fixture.mutated([.set(pointer, 99)]))
        #expect(session.importProblems.map(\.pointer) == [pointer])
        #expect(session.backup?.original == (try Fixture.data()))
        #expect(session.engine === engine)
        #expect(session.mode == .dryRun)
        #expect(engine.generation == generation + 1)
        // A good import clears the problems.
        session.load(try Fixture.data())
        #expect(session.importProblems.isEmpty)
    }

    @Test("A failed first import leaves the session without a backup; presses do nothing")
    func failedFirstImport() {
        let scheduler = FakeScheduler()
        let session = Session(scheduler: scheduler, output: RecordingSink(scheduler: scheduler))
        session.load(Data("{".utf8))
        #expect(!session.importProblems.isEmpty)
        #expect(session.backup == nil)
        session.down(.a, source: .mouse)
        session.up(.a, source: .mouse)
        session.focusLost()
        #expect(session.log.isEmpty)
    }

    // MARK: - Log

    @Test("The log exports as JSON lines with time, bytes, ports and source pointer")
    func exportJSONLines() throws {
        let (session, scheduler) = try Self.session(output: EngineTests.FailingSink())
        Self.tapC(session, scheduler)
        scheduler.advance(by: .milliseconds(100))
        session.arm()
        Self.tapC(session, scheduler)
        let text = String(decoding: session.exportLog(), as: UTF8.self)
        let lines = text.split(separator: "\n").map(String.init)
        let objects = try lines.map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! NSDictionary }
        #expect(objects == [
            ["kind": "output", "ms": 50, "bytes": [176, 26, 127], "ports": [1, 2], "pointer": "\(Self.tap)/0", "live": false],
            ["kind": "output", "ms": 60, "bytes": [176, 26, 0], "ports": [1, 2], "pointer": "\(Self.tap)/2", "live": false],
            ["kind": "tap", "ms": 60],
            ["kind": "fault", "ms": 200, "pointer": "\(Self.tap)/0", "reason": "send failed: Failure()"],
        ] as [NSDictionary])
        #expect(text.hasSuffix("\n"))
    }

    @Test("The log keeps the newest entries up to its limit")
    func logLimit() throws {
        let scheduler = FakeScheduler()
        let session = Session(scheduler: scheduler, output: RecordingSink(scheduler: scheduler))
        session.load(try Fixture.data())
        for move in 0...Session.logLimit {
            scheduler.advance(by: .milliseconds(1))
            session.moveExpression(input: 0, to: move % 128)
        }
        #expect(session.log.count == Session.logLimit)
        #expect(session.log.first?.time == .milliseconds(2))
        #expect(session.log.last?.time == .milliseconds(Session.logLimit + 1))
    }
}

/// What a footswitch shows (spec 6.1, 6.3): physical A to F of the shown page, names and key codes.
@MainActor @Suite struct ButtonDisplayTests {
    @Test("HOME page 1 shows stored A to F in physical order with readable icon tags")
    func homePage() throws {
        let backup = try Fixture.backup()
        let shown = ButtonDisplay.shown(RuntimeState(backup: backup), in: backup)
        #expect(shown.map(\.button) == Footswitch.allCases)
        #expect(shown.map(\.address) == (0..<6).map { PresetAddress(bank: 0, preset: $0) })
        #expect(shown.map(\.name) == ["[H] TONES", "[X] PEDALS", "[|] TAP", "[W] DAW", "[V] LOOPER", "[g] MUTE"])
        #expect(shown.allSatisfy { $0.position == .one })
    }

    @Test("Spec 6.1: PEDALS page 2 shows stored G to L on physical A to F")
    func secondPage() throws {
        let backup = try Fixture.backup()
        var state = RuntimeState(backup: backup)
        state.bank = 2
        state.page = 1
        let shown = ButtonDisplay.shown(state, in: backup)
        #expect(shown.map(\.address.preset) == Array(6...11))
        #expect(shown.map(\.name) == ["[z] FUZZ/DRIVE", "[O] WAH/SWEEP", "[,] PAGE+", "[N] MOD/COLOR", "[S] SPACE", "[l] BACK"])
    }

    @Test("U09: a temporary name comes before the backup name")
    func temporaryName() throws {
        let backup = try Fixture.backup()
        var state = RuntimeState(backup: backup)
        state.bank = 2
        state.page = 1
        state.names[PresetAddress(bank: 2, preset: 10)] = "\\@ CLEAR"
        #expect(ButtonDisplay.shown(state, in: backup)[4].name == "[@] CLEAR")
    }

    @Test("Position 2 shows the toggle name; an empty toggle name falls back to the short name")
    func toggleName() {
        func preset(_ short: String, _ toggle: String) -> Preset {
            Preset(shortName: short, toggleName: toggle, toMsgScroll: false, messages: [])
        }
        let backup = Backup(
            original: Data(),
            banks: [Bank(
                number: 0, name: "", pageLimit: 0,
                presets: [preset("\\a ON", "\\b OFF"), preset("PLAIN", "")] + Array(repeating: preset("", ""), count: 22),
                expressions: [])],
            productionBanks: [0], longPressTime: 12, sendToPort: [], notes: [])
        var state = RuntimeState(backup: backup)
        #expect(ButtonDisplay.shown(state, in: backup)[0].name == "[a] ON")
        state.positions[0][0] = .two
        state.positions[0][1] = .two
        let shown = ButtonDisplay.shown(state, in: backup)
        #expect(shown[0].name == "[b] OFF")
        #expect(shown[0].position == .two)
        #expect(shown[1].name == "PLAIN")
    }

    @Test("Icon escapes become readable tags; other text stays as it is")
    func readableTags() {
        #expect(ButtonDisplay.readable("\\h HOME") == "[h] HOME")
        #expect(ButtonDisplay.readable("A\\@B\\S") == "A[@]B[S]")
        #expect(ButtonDisplay.readable("EMPTY") == "EMPTY")
        #expect(ButtonDisplay.readable("END\\") == "END\\")
    }

    @Test("Keys Q W E press D E F and A S D press A B C, by physical key code")
    func keyCodes() {
        let keys = [kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_E, kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_D]
        #expect(keys.map { Footswitch(keyCode: UInt16($0)) } == [.d, .e, .f, .a, .b, .c])
        #expect(Footswitch(keyCode: UInt16(kVK_ANSI_Z)) == nil)
        #expect(Footswitch(keyCode: UInt16(kVK_Space)) == nil)
    }
}
