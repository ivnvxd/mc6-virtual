import Testing
@testable import MC6Core

/// The plan's Gestures section, spec 6.2 action sequences, U08 and S7.
/// Synthetic recorder presets send CC `action` with value `tag` for each action they have, so the bytes show the actions.
@MainActor @Suite struct GestureTests {
    /// A recorder preset: each action sends CC `action` with value `tag` (1 = A, 2 = B, ...).
    static func recorder(_ tag: UInt8, actions: [Int] = Array(1...9)) -> [Message] {
        actions.enumerated().map { slot, action in
            EngineTests.message(slot, EngineTests.cc(UInt8(action), tag), action: action)
        }
    }

    /// A has messages for every action, so it waits for a second tap. B has none for actions 5 to 8.
    static func harness(longPressTime: Int = 12) -> EngineHarness {
        EngineHarness(EngineTests.backup(
            [[recorder(1), recorder(2, actions: [1, 2, 3, 4, 9])]], longPressTime: longPressTime))
    }

    /// Each sent message as preset letter and action, for example "A1" for Press of A.
    static func fired(_ h: EngineHarness) -> [String] {
        h.bytes.map { "\(Character(UnicodeScalar(64 + $0[2])))\($0[1])" }
    }

    static func ms(_ value: Int) -> Duration { .milliseconds(value) }

    /// Down, 50 ms, up.
    static func tap(_ h: EngineHarness, _ button: Footswitch, source: InputSource = .mouse) {
        h.recognizer.down(button, source: source)
        h.scheduler.advance(by: ms(50))
        h.recognizer.up(button, source: source)
    }

    // MARK: - Short press and hold

    @Test("A short tap on a preset without double-tap messages: Press, then Release and Release All on up")
    func shortTap() {
        let h = Self.harness()
        h.recognizer.down(.b, source: .mouse)
        h.scheduler.advance(by: Self.ms(100))
        #expect(Self.fired(h) == ["B1"])
        h.recognizer.up(.b, source: .mouse)
        h.scheduler.advance(by: .seconds(1))
        #expect(Self.fired(h) == ["B1", "B2", "B9"])
        #expect(h.sink.sent.map(\.time) == [.zero, Self.ms(100), Self.ms(100)])
    }

    @Test("A hold: Long Press at 700 ms, then Long Press Release and Release All on up, no Release")
    func hold() {
        let h = Self.harness()
        h.recognizer.down(.b, source: .mouse)
        h.scheduler.advance(by: Self.ms(699))
        #expect(Self.fired(h) == ["B1"])
        h.scheduler.advance(by: Self.ms(1))
        #expect(Self.fired(h) == ["B1", "B3"])
        h.scheduler.advance(by: Self.ms(300))
        h.recognizer.up(.b, source: .mouse)
        #expect(Self.fired(h) == ["B1", "B3", "B4", "B9"])
        #expect(h.sink.sent.map(\.time) == [.zero, Self.ms(700), Self.ms(1000), Self.ms(1000)])
    }

    @Test("U08: the long-press time is 100 + 50 * longPressTime ms", arguments: [(0, 100), (12, 700), (28, 1500)])
    func u08LongPressTime(longPressTime: Int, ms: Int) {
        let h = Self.harness(longPressTime: longPressTime)
        #expect(h.recognizer.longPress == Self.ms(ms))
        h.recognizer.down(.b, source: .mouse)
        h.scheduler.advance(by: Self.ms(ms - 1))
        #expect(Self.fired(h) == ["B1"])
        h.scheduler.advance(by: Self.ms(1))
        #expect(Self.fired(h) == ["B1", "B3"])
    }

    @Test("U08: a hold on a preset with double-tap messages releases at once on up")
    func holdOnDoubleTapPreset() {
        let h = Self.harness()
        h.recognizer.down(.a, source: .mouse)
        h.scheduler.advance(by: Self.ms(800))
        h.recognizer.up(.a, source: .mouse)
        #expect(Self.fired(h) == ["A1", "A3", "A4", "A9"])
        h.scheduler.advance(by: .seconds(1))
        #expect(Self.fired(h) == ["A1", "A3", "A4", "A9"])
    }

    // MARK: - Double tap (U08)

    @Test("U08: a short tap on a preset with double-tap messages waits 300 ms, then Release and Release All")
    func singleTapWaits() {
        let h = Self.harness()
        Self.tap(h, .a)
        h.scheduler.advance(by: Self.ms(299))
        #expect(Self.fired(h) == ["A1"])
        h.scheduler.advance(by: Self.ms(1))
        #expect(Self.fired(h) == ["A1", "A2", "A9"])
        #expect(h.sink.sent.map(\.time) == [.zero, Self.ms(350), Self.ms(350)])
    }

    @Test("A second tap: Double Tap, Double Tap Release, Release All; no second Press and no Release")
    func doubleTap() {
        let h = Self.harness()
        Self.tap(h, .a)
        h.scheduler.advance(by: Self.ms(100))
        Self.tap(h, .a)
        h.scheduler.advance(by: .seconds(1))
        #expect(Self.fired(h) == ["A1", "A5", "A6", "A9"])
    }

    @Test("A second tap held past the long-press time: Long Double Tap, then Long Double Tap Release and Release All")
    func longDoubleTap() {
        let h = Self.harness()
        Self.tap(h, .a)
        h.scheduler.advance(by: Self.ms(100))
        h.recognizer.down(.a, source: .mouse)
        h.scheduler.advance(by: Self.ms(699))
        #expect(Self.fired(h) == ["A1"])
        h.scheduler.advance(by: Self.ms(1))
        #expect(Self.fired(h) == ["A1", "A7"])
        h.recognizer.up(.a, source: .mouse)
        h.scheduler.advance(by: .seconds(1))
        #expect(Self.fired(h) == ["A1", "A7", "A8", "A9"])
    }

    @Test("Another button during the wait ends the first tap as a single tap before its own Press")
    func anotherButtonEndsWait() {
        let h = Self.harness()
        Self.tap(h, .a)
        h.scheduler.advance(by: Self.ms(100))
        Self.tap(h, .b)
        h.scheduler.advance(by: .seconds(1))
        #expect(Self.fired(h) == ["A1", "A2", "A9", "B1", "B2", "B9"])
    }

    // MARK: - Focus loss

    @Test("Focus loss during the wait: Release, Release All")
    func focusLostDuringWait() {
        let h = Self.harness()
        Self.tap(h, .a)
        h.recognizer.focusLost()
        #expect(Self.fired(h) == ["A1", "A2", "A9"])
        h.scheduler.advance(by: .seconds(1))
        #expect(Self.fired(h) == ["A1", "A2", "A9"])
    }

    @Test("Focus loss after Long Press: Long Press Release, Release All; the later up does nothing")
    func focusLostAfterLongPress() {
        let h = Self.harness()
        h.recognizer.down(.b, source: .mouse)
        h.scheduler.advance(by: Self.ms(700))
        h.recognizer.focusLost()
        h.recognizer.up(.b, source: .mouse)
        h.scheduler.advance(by: .seconds(1))
        #expect(Self.fired(h) == ["B1", "B3", "B4", "B9"])
    }

    @Test("Focus loss before Long Press cancels: nothing after Press, not even on up")
    func focusLostBeforeLongPress() {
        let h = Self.harness()
        h.recognizer.down(.b, source: .mouse)
        h.scheduler.advance(by: Self.ms(100))
        h.recognizer.focusLost()
        h.scheduler.advance(by: .seconds(1))
        h.recognizer.up(.b, source: .mouse)
        #expect(Self.fired(h) == ["B1"])
    }

    @Test("Focus loss on a second tap: before Long Double Tap it cancels, after it releases")
    func focusLostOnSecondTap() {
        let cancelled = Self.harness()
        Self.tap(cancelled, .a)
        cancelled.recognizer.down(.a, source: .mouse)
        cancelled.recognizer.focusLost()
        cancelled.scheduler.advance(by: .seconds(1))
        #expect(Self.fired(cancelled) == ["A1"])

        let released = Self.harness()
        Self.tap(released, .a)
        released.recognizer.down(.a, source: .mouse)
        released.scheduler.advance(by: Self.ms(700))
        released.recognizer.focusLost()
        released.recognizer.up(.a, source: .mouse)
        #expect(Self.fired(released) == ["A1", "A7", "A8", "A9"])
    }

    // MARK: - Repeat and second source

    @Test("Key repeat is ignored")
    func keyRepeat() {
        let h = Self.harness()
        for _ in 0..<3 {
            h.recognizer.down(.b, source: .keyboard)
            h.scheduler.advance(by: Self.ms(30))
        }
        h.recognizer.up(.b, source: .keyboard)
        #expect(Self.fired(h) == ["B1", "B2", "B9"])
    }

    @Test("A second source on a held button does nothing, down or up")
    func secondSource() {
        let short = Self.harness()
        short.recognizer.down(.b, source: .mouse)
        short.recognizer.down(.b, source: .keyboard)
        short.recognizer.up(.b, source: .keyboard)
        #expect(Self.fired(short) == ["B1"])
        short.scheduler.advance(by: Self.ms(100))
        short.recognizer.up(.b, source: .mouse)
        #expect(Self.fired(short) == ["B1", "B2", "B9"])

        let held = Self.harness()
        held.recognizer.down(.b, source: .keyboard)
        held.recognizer.down(.b, source: .mouse)
        held.scheduler.advance(by: Self.ms(700))
        held.recognizer.up(.b, source: .mouse)
        #expect(Self.fired(held) == ["B1", "B3"])
        held.recognizer.up(.b, source: .keyboard)
        #expect(Self.fired(held) == ["B1", "B3", "B4", "B9"])
    }

    // MARK: - Captured address

    @Test("The address is captured at down and stays after Press or Long Press changes the page")
    func capturedAddress() {
        // C (2): Press and Long Press go to page 2; its Release, Long Press Release and Release All tag 3.
        // I (8), physical C on page 2: Release tags 9.
        let c: [Message] = [
            EngineTests.message(0, .togglePage(.up), action: 1),
            EngineTests.message(1, EngineTests.cc(2, 3), action: 2),
            EngineTests.message(2, .togglePage(.up), action: 3),
            EngineTests.message(3, EngineTests.cc(4, 3), action: 4),
            EngineTests.message(4, EngineTests.cc(9, 3), action: 9),
        ]
        var presets = Array(repeating: [Message](), count: 9)
        presets[2] = c
        presets[8] = [EngineTests.message(0, EngineTests.cc(2, 9))]
        let h = EngineHarness(EngineTests.backup([presets], pageLimit: 0))

        Self.tap(h, .c)
        #expect(h.engine.state.page == 1)
        #expect(Self.fired(h) == ["C2", "C9"])
        Self.tap(h, .c)  // I on page 2
        #expect(Self.fired(h) == ["C2", "C9", "I2"])

        let hold = EngineHarness(EngineTests.backup([presets], pageLimit: 0))
        hold.recognizer.down(.c, source: .mouse)
        hold.scheduler.advance(by: Self.ms(700))
        hold.recognizer.up(.c, source: .mouse)
        #expect(hold.engine.state.page == 2)
        #expect(Self.fired(hold) == ["C4", "C9"])
    }

    @Test("Another button during the double-tap wait gets the address of the page shown at its down")
    func addressBeforeDeferredRelease() {
        // A waits for a second tap, and its Release turns the page. B (1) and H (7, physical B on page 2) tag 2 and 8.
        var presets = Array(repeating: [Message](), count: 8)
        presets[0] = [
            EngineTests.message(0, .togglePage(.up), action: 2),
            EngineTests.message(1, EngineTests.cc(5, 1), action: 5),
        ]
        presets[1] = [EngineTests.message(0, EngineTests.cc(1, 2), action: 1)]
        presets[7] = [EngineTests.message(0, EngineTests.cc(1, 8), action: 1)]
        let h = EngineHarness(EngineTests.backup([presets]))
        Self.tap(h, .a)
        h.recognizer.down(.b, source: .mouse)
        #expect(h.engine.state.page == 1)
        #expect(Self.fired(h) == ["B1"])
    }

    // MARK: - Generation bump

    enum Bump: CaseIterable {
        case reset, cancel
    }

    static func bump(_ h: EngineHarness, _ bump: Bump) {
        switch bump {
        case .reset: h.engine.reset()
        case .cancel: h.engine.cancel()
        }
    }

    @Test("A held button across a generation bump fires nothing, and the next gesture works", arguments: Bump.allCases)
    func heldAcrossBump(bump: Bump) {
        let h = Self.harness()
        h.recognizer.down(.b, source: .mouse)
        Self.bump(h, bump)
        h.scheduler.advance(by: .seconds(1))
        h.recognizer.up(.b, source: .mouse)
        #expect(Self.fired(h) == ["B1"])
        Self.tap(h, .b)
        #expect(Self.fired(h) == ["B1", "B1", "B2", "B9"])
    }

    @Test("A bump after Long Press or during the wait for a second tap fires nothing more", arguments: Bump.allCases)
    func laterPhasesAcrossBump(bump: Bump) {
        let held = Self.harness()
        held.recognizer.down(.b, source: .mouse)
        held.scheduler.advance(by: Self.ms(700))
        Self.bump(held, bump)
        held.recognizer.up(.b, source: .mouse)
        held.recognizer.focusLost()
        #expect(Self.fired(held) == ["B1", "B3"])

        let waiting = Self.harness()
        Self.tap(waiting, .a)
        Self.bump(waiting, bump)
        waiting.scheduler.advance(by: .seconds(1))
        waiting.recognizer.focusLost()
        #expect(Self.fired(waiting) == ["A1"])
    }

    @Test("A fault in Release stops the gesture: Release All does not run")
    func faultStopsGesture() {
        let h = EngineHarness(EngineTests.backup([[[
            EngineTests.message(0, .engage(bank: 0, preset: 0, action: 2)),
            EngineTests.message(1, EngineTests.cc(9, 1), action: 9),
        ]]]))
        Self.tap(h, .a)
        #expect(h.faults == [.depthLimit(pointer: "/synthetic/0")])
        #expect(h.bytes.isEmpty)
    }

    // MARK: - S7 (fixture)

    // Bank IDs of the fixture. HOME E goes to LOOPER; LOOPER D is CLEAR with Double Tap and Long Press only.
    static let looper = 3, daw = 4

    static func looperHarness() throws -> EngineHarness {
        let h = EngineHarness(try Fixture.backup())
        tap(h, .e)
        #expect(h.engine.state.place == Place(bank: looper, page: 0))
        return h
    }

    @Test("S7: a single tap on LOOPER CLEAR sends nothing")
    func s7SingleTap() throws {
        let h = try Self.looperHarness()
        Self.tap(h, .d)
        h.scheduler.advance(by: .seconds(1))
        #expect(h.bytes.isEmpty)
        #expect(h.engine.state.place == Place(bank: Self.looper, page: 0))
        #expect(h.faults.isEmpty)
    }

    @Test("S7: a double tap on LOOPER CLEAR sends CC34 127, 10 ms, CC34 0 on channel 1")
    func s7DoubleTap() throws {
        let h = try Self.looperHarness()
        Self.tap(h, .d)
        h.scheduler.advance(by: Self.ms(100))
        h.recognizer.down(.d, source: .mouse)
        h.scheduler.advance(by: Self.ms(50))
        let start = h.scheduler.now
        h.recognizer.up(.d, source: .mouse)
        h.scheduler.advance(by: .seconds(1))
        #expect(h.sink.sent.map(\.bytes) == [[0xB0, 34, 127], [0xB0, 34, 0]])
        #expect(h.sink.sent.map(\.time) == [start, start + Self.ms(10)])
        #expect(h.engine.state.place == Place(bank: Self.looper, page: 0))
        #expect(h.faults.isEmpty)
    }

    @Test("S7: a hold on LOOPER CLEAR goes to DAW and sends nothing")
    func s7Hold() throws {
        let h = try Self.looperHarness()
        h.recognizer.down(.d, source: .mouse)
        h.scheduler.advance(by: Self.ms(700))
        #expect(h.engine.state.place == Place(bank: Self.daw, page: 0))
        h.recognizer.up(.d, source: .mouse)
        h.scheduler.advance(by: .seconds(1))
        #expect(h.bytes.isEmpty)
        #expect(h.engine.state.place == Place(bank: Self.daw, page: 0))
    }
}
