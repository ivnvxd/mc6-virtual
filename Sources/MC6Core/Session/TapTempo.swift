/// The tempo of MIDI Clock Tap messages, for screen 3 (V10).
public struct TapTempo: Sendable {
    /// A longer pause starts a new count.
    public static let maxGap = Duration.seconds(2)
    /// The BPM is the mean of this many last intervals.
    public static let intervals = 4
    /// A shorter interval is no tap, for example two Clock Taps in one action, which the real clock puts
    /// microseconds apart. 100 ms is 600 BPM.
    public static let minInterval = Duration.milliseconds(100)

    private var taps: [Duration] = []
    /// V27: the BPM steps of Utility 2 and 3 since the count started.
    private var steps = 0

    public init() {}

    public mutating func tap(at time: Duration) {
        // Taps closer than `minInterval`, such as two Clock Tap messages in one action, count once.
        if let last = taps.last, time - last < Self.minInterval { return }
        if let last = taps.last, time - last > Self.maxGap {
            taps.removeAll()
            steps = 0
        }
        taps.append(time)
        if taps.count > Self.intervals + 1 { taps.removeFirst(taps.count - Self.intervals - 1) }
    }

    /// V27: changes the BPM by `step`, but not below 1. Without a BPM it does nothing.
    public mutating func step(_ step: Int) {
        guard let bpm else { return }
        steps += max(step, 1 - bpm)
    }

    /// Beats per minute, rounded, with the steps; nil before the second tap of a count.
    public var bpm: Int? {
        guard let first = taps.first, let last = taps.last, taps.count > 1 else { return nil }
        let mean = (last - first) / (taps.count - 1)
        return Int((Duration.seconds(60) / mean).rounded()) + steps
    }
}
