/// Turns scroll events over the pedal into pedal steps (V17). The result follows the finger or the wheel:
/// up raises the value, whatever the natural scrolling setting is.
public struct ScrollSteps: Sendable {
    /// Trackpad points for one step.
    public static let pointsPerStep = 4.0

    /// Trackpad points that did not make a whole step yet.
    private var rest = 0.0

    public init() {}

    /// Adds one scroll event and returns the steps to move now, positive for up.
    /// - `precise`: a trackpad or another device with point deltas. False for a mouse wheel.
    /// - `inverted`: natural scrolling is on, so the event's delta is the opposite of the device motion.
    /// A wheel event moves `arrowStep` in the direction of its sign, also when the system speeds the wheel up.
    public mutating func add(deltaY: Double, precise: Bool, inverted: Bool, arrowStep: Int) -> Int {
        let motion = inverted ? -deltaY : deltaY
        guard precise else {
            return motion > 0 ? arrowStep : motion < 0 ? -arrowStep : 0
        }
        rest += motion
        let steps = Int(rest / Self.pointsPerStep)
        rest -= Double(steps) * Self.pointsPerStep
        return steps
    }
}
