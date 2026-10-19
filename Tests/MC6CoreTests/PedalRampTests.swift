import Testing
@testable import MC6Core

/// A held pedal key: one step at once, then a steady sweep (V16).
@Suite struct PedalRampTests {
    static func value(
        _ start: Int, up: Bool = true, step: Int = 8, ms: Int, sweep: Int = 1000, fine: Bool = false
    ) -> Int {
        PedalRamp.value(
            start: start, up: up, step: step, elapsed: .milliseconds(ms), sweep: .milliseconds(sweep), fine: fine)
    }

    @Test("V16: the down moves one step at once, and nothing more happens before 250 ms")
    func firstStep() {
        #expect(Self.value(60, ms: 0) == 68)
        #expect(Self.value(60, ms: 249) == 68)
        #expect(Self.value(60, up: false, ms: 100) == 52)
        #expect(PedalRamp.delay == .milliseconds(250))
    }

    @Test("V16: after the delay the pedal sweeps 127 steps in the sweep time")
    func sweep() {
        // Half the sweep time after the delay: 63.5 steps, rounded down.
        #expect(Self.value(0, step: 1, ms: 750) == 64)
        #expect(Self.value(0, step: 1, ms: 1250) == 127)
        #expect(Self.value(0, step: 1, ms: 550, sweep: 300) == 127)
        #expect(Self.value(127, up: false, step: 8, ms: 750) == 56)
    }

    @Test("V16: with Option the sweep is a quarter as fast")
    func fine() {
        #expect(Self.value(0, step: 1, ms: 1250, fine: true) == 32)
        #expect(Self.value(127, up: false, step: 1, ms: 1250, fine: true) == 95)
    }

    @Test("V16: the value stays within 0 to 127", arguments: [
        (3, false, 0, 0), (125, true, 0, 127), (0, false, 5000, 0), (127, true, 5000, 127),
    ])
    func clamp(_ start: Int, _ up: Bool, _ ms: Int, _ expected: Int) {
        #expect(Self.value(start, up: up, ms: ms) == expected)
    }
}
