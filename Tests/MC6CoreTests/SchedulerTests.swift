import Testing
@testable import MC6Core

@MainActor @Suite struct FakeSchedulerTests {
    @Test("FakeScheduler fires wake-ups in time order")
    func timeOrder() {
        let scheduler = FakeScheduler()
        var fired: [Duration] = []
        for ms in [30, 10, 20] {
            scheduler.schedule(after: .milliseconds(ms)) { fired.append(scheduler.now) }
        }
        scheduler.advance(by: .milliseconds(50))
        #expect(fired == [.milliseconds(10), .milliseconds(20), .milliseconds(30)])
        #expect(scheduler.now == .milliseconds(50))
    }

    @Test("FakeScheduler fires a wake-up scheduled by another wake-up within the same advance")
    func nested() {
        let scheduler = FakeScheduler()
        var fired: [Duration] = []
        scheduler.schedule(after: .milliseconds(10)) {
            scheduler.schedule(after: .milliseconds(10)) { fired.append(scheduler.now) }
        }
        scheduler.schedule(after: .milliseconds(15)) { fired.append(scheduler.now) }
        scheduler.advance(by: .milliseconds(20))
        #expect(fired == [.milliseconds(15), .milliseconds(20)])
    }

    @Test("FakeScheduler fires equal times in scheduling order")
    func ties() {
        let scheduler = FakeScheduler()
        var fired: [Int] = []
        for index in 0..<3 {
            scheduler.schedule(after: .milliseconds(5)) { fired.append(index) }
        }
        scheduler.advance(by: .milliseconds(5))
        #expect(fired == [0, 1, 2])
    }

    @Test("A cancelled FakeScheduler wake-up never fires")
    func cancel() {
        let scheduler = FakeScheduler()
        var fired = false
        let wakeup = scheduler.schedule(after: .milliseconds(10)) { fired = true }
        scheduler.cancel(wakeup)
        scheduler.advance(by: .milliseconds(100))
        #expect(!fired)
    }
}

@MainActor @Suite(.serialized) struct DispatchSchedulerTests {
    @Test("A 50 ms DispatchScheduler wake-up fires between 45 and 150 ms")
    func timing() async {
        let scheduler = DispatchScheduler()
        let clock = ContinuousClock()
        // Measured inside the wake-up: resuming the test task can wait for a busy thread pool.
        let elapsed = await withCheckedContinuation { continuation in
            let start = clock.now
            scheduler.schedule(after: .milliseconds(50)) { continuation.resume(returning: clock.now - start) }
        }
        #expect(elapsed >= .milliseconds(45))
        #expect(elapsed <= .milliseconds(150))
    }

    @Test("DispatchScheduler.now is monotonic and advances with real time")
    func now() async throws {
        let scheduler = DispatchScheduler()
        let before = scheduler.now
        try await Task.sleep(for: .milliseconds(20))
        #expect(scheduler.now - before >= .milliseconds(20))
    }

    @Test("A cancelled DispatchScheduler wake-up never fires")
    func cancel() async throws {
        let scheduler = DispatchScheduler()
        var fired = false
        let wakeup = scheduler.schedule(after: .milliseconds(20)) { fired = true }
        scheduler.cancel(wakeup)
        try await Task.sleep(for: .milliseconds(120))
        #expect(!fired)
    }
}

@Suite struct PortMappingTests {
    @Test("sendToPort 130 (bits 1 and 7) goes to both ports", arguments: [130, 4095])
    func bothPorts(mask: Int) {
        #expect(Ports(sendToPort: mask) == [.port1, .port2])
    }

    @Test("Bit 1 alone goes to port 1, bit 7 alone to port 2")
    func singlePorts() {
        #expect(Ports(sendToPort: 1 << 1) == .port1)
        #expect(Ports(sendToPort: 1 << 7) == .port2)
    }

    @Test("A mask without bits 1 and 7 goes nowhere", arguments: [0, 1, 4095 & ~(1 << 1 | 1 << 7)])
    func noPorts(mask: Int) {
        #expect(Ports(sendToPort: mask).isEmpty)
    }
}

@MainActor @Suite struct RecordingSinkTests {
    @Test("RecordingSink records bytes, ports and the scheduler time")
    func records() throws {
        let scheduler = FakeScheduler()
        let sink = RecordingSink(scheduler: scheduler)
        try sink.send([0xB0, 60, 107], to: .port1)
        scheduler.advance(by: .milliseconds(50))
        try sink.send([0xC1, 3], to: [.port1, .port2])
        #expect(sink.sent == [
            .init(time: .zero, bytes: [0xB0, 60, 107], ports: .port1),
            .init(time: .milliseconds(50), bytes: [0xC1, 3], ports: [.port1, .port2]),
        ])
    }
}
