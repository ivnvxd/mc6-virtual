/// A held pedal key (V16): one step at the down, then after `delay` a steady sweep of 127 steps in the sweep time,
/// a quarter as fast with Option. The OS key repeat plays no part, so the speed does not depend on system settings.
public enum PedalRamp {
    public static let delay: Duration = .milliseconds(250)

    /// The value after `elapsed` of hold, from `start`, within 0 to 127. Part steps round down.
    public static func value(start: Int, up: Bool, step: Int, elapsed: Duration, sweep: Duration, fine: Bool) -> Int {
        var steps = Double(step)
        if elapsed > delay, sweep > .zero {
            steps += 127 * ((elapsed - delay) / sweep) / (fine ? 4 : 1)
        }
        let moved = Int(steps.rounded(.down))
        return min(127, max(0, start + (up ? moved : -moved)))
    }
}
