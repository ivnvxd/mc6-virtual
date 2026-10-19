import Testing
@testable import MC6Core

/// A scroll over the pedal (V17). Positive device direction is a wheel turned away or fingers moved up.
@Suite struct ScrollStepsTests {
    @Test("V17: each wheel event moves one arrow step in the direction of its sign")
    func wheel() {
        var steps = ScrollSteps()
        #expect(steps.add(deltaY: 1, precise: false, inverted: false, arrowStep: 8) == 8)
        #expect(steps.add(deltaY: -1, precise: false, inverted: false, arrowStep: 8) == -8)
        #expect(steps.add(deltaY: 0, precise: false, inverted: false, arrowStep: 8) == 0)
    }

    @Test("V17: an accelerated wheel event still moves one step")
    func acceleratedWheel() {
        var steps = ScrollSteps()
        #expect(steps.add(deltaY: 9.5, precise: false, inverted: false, arrowStep: 4) == 4)
        #expect(steps.add(deltaY: -0.1, precise: false, inverted: false, arrowStep: 4) == -4)
    }

    @Test("V17: the value follows the finger with natural scrolling on and off")
    func inverted() {
        var steps = ScrollSteps()
        #expect(steps.add(deltaY: -1, precise: false, inverted: true, arrowStep: 8) == 8)
        #expect(steps.add(deltaY: 1, precise: false, inverted: true, arrowStep: 8) == -8)
        #expect(steps.add(deltaY: -8, precise: true, inverted: true, arrowStep: 8) == 2)
        #expect(steps.add(deltaY: 8, precise: true, inverted: false, arrowStep: 8) == 2)
    }

    @Test("V17: a trackpad moves 1 step for each 4 points, and the rest carries over")
    func trackpad() {
        var steps = ScrollSteps()
        #expect(steps.add(deltaY: 3, precise: true, inverted: false, arrowStep: 8) == 0)
        #expect(steps.add(deltaY: 3, precise: true, inverted: false, arrowStep: 8) == 1)
        #expect(steps.add(deltaY: 2, precise: true, inverted: false, arrowStep: 8) == 1)
        #expect(steps.add(deltaY: 10, precise: true, inverted: false, arrowStep: 8) == 2)
        // 2 points are left over: 2 down cancels them.
        #expect(steps.add(deltaY: -2, precise: true, inverted: false, arrowStep: 8) == 0)
        #expect(steps.add(deltaY: -4, precise: true, inverted: false, arrowStep: 8) == -1)
        #expect(steps.add(deltaY: -3, precise: true, inverted: false, arrowStep: 8) == 0)
        #expect(steps.add(deltaY: -1, precise: true, inverted: false, arrowStep: 8) == -1)
    }
}
