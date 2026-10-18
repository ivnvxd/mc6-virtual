import Testing
@testable import MC6Core

/// Gesture timing and log size as settings (plan v2, Task 3, V08).
@MainActor @Suite struct TimingTests {
    static func ms(_ value: Int) -> Duration { .milliseconds(value) }

    @Test("V08: a custom long press of 1000 ms fires Long Press at 1000 ms, not at the backup's 700 ms")
    func customLongPress() {
        let h = GestureTests.harness()
        h.recognizer.timing = GestureTiming(longPress: Self.ms(1000))
        #expect(h.recognizer.longPress == Self.ms(1000))
        h.recognizer.down(.b, source: .mouse)
        h.scheduler.advance(by: Self.ms(999))
        #expect(GestureTests.fired(h) == ["B1"])
        h.scheduler.advance(by: Self.ms(1))
        #expect(GestureTests.fired(h) == ["B1", "B3"])
    }

    @Test("V08: without an override the long press comes from the backup")
    func backupLongPress() {
        let h = GestureTests.harness(longPressTime: 4)
        #expect(h.recognizer.timing == GestureTiming())
        #expect(h.recognizer.longPress == Self.ms(300))
    }

    @Test("V08: a double-tap window of 500 ms waits 500 ms for a second tap")
    func customDoubleTapWindow() {
        let h = GestureTests.harness()
        h.recognizer.timing = GestureTiming(doubleTapWindow: Self.ms(500))
        GestureTests.tap(h, .a)
        h.scheduler.advance(by: Self.ms(499))
        #expect(GestureTests.fired(h) == ["A1"])
        h.scheduler.advance(by: Self.ms(1))
        #expect(GestureTests.fired(h) == ["A1", "A2", "A9"])
    }

    @Test("V08: a timing change during a held gesture does not change that gesture")
    func changeDuringGesture() {
        let h = GestureTests.harness()
        h.recognizer.down(.b, source: .mouse)
        h.recognizer.timing = GestureTiming(longPress: Self.ms(1000), doubleTapWindow: Self.ms(500))
        h.scheduler.advance(by: Self.ms(700))
        #expect(GestureTests.fired(h) == ["B1", "B3"])
        h.recognizer.up(.b, source: .mouse)
        // The next gesture uses the new values.
        h.recognizer.down(.b, source: .mouse)
        h.scheduler.advance(by: Self.ms(999))
        #expect(GestureTests.fired(h) == ["B1", "B3", "B4", "B9", "B1"])
    }

    @Test("V08: a wait for a second tap keeps the window from its first down")
    func changeDuringWait() {
        let h = GestureTests.harness()
        GestureTests.tap(h, .a)
        h.recognizer.timing = GestureTiming(doubleTapWindow: Self.ms(100))
        h.scheduler.advance(by: Self.ms(299))
        #expect(GestureTests.fired(h) == ["A1"])
        h.scheduler.advance(by: Self.ms(1))
        #expect(GestureTests.fired(h) == ["A1", "A2", "A9"])
    }

    @Test("V08: the session keeps its timing across a second load")
    func sessionKeepsTiming() throws {
        let scheduler = FakeScheduler()
        let session = Session(scheduler: scheduler, output: RecordingSink(scheduler: scheduler))
        session.timing = GestureTiming(longPress: Self.ms(900))
        session.load(try Fixture.data())
        #expect(session.longPress == Self.ms(900))
        session.load(try Fixture.data())
        #expect(session.longPress == Self.ms(900))
        session.timing = GestureTiming()
        #expect(session.longPress == Self.ms(700))
    }

    @Test("A log limit of 1,000 keeps the newest 1,000 entries")
    func smallLogLimit() throws {
        let scheduler = FakeScheduler()
        let session = Session(scheduler: scheduler, output: RecordingSink(scheduler: scheduler))
        session.logLimit = 1_000
        session.load(try Fixture.data())
        for move in 0...1_000 {
            scheduler.advance(by: Self.ms(1))
            session.moveExpression(input: 0, to: move % 128)
        }
        #expect(session.log.count == 1_000)
        #expect(session.log.first?.time == Self.ms(2))
    }

    @Test("Lowering the log limit trims the log at once, oldest first")
    func lowerLimit() throws {
        let scheduler = FakeScheduler()
        let session = Session(scheduler: scheduler, output: RecordingSink(scheduler: scheduler))
        session.load(try Fixture.data())
        for move in 0..<1_500 {
            scheduler.advance(by: Self.ms(1))
            session.moveExpression(input: 0, to: move % 128)
        }
        #expect(session.log.count == 1_500)
        session.logLimit = 1_000
        #expect(session.log.count == 1_000)
        #expect(session.log.first?.time == Self.ms(501))
    }
}
