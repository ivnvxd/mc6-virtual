/// The tempo of MIDI Clock Tap messages, for screen 3 (V10).
public struct TapTempo: Sendable {
    /// A longer pause starts a new count.
    public static let maxGap = Duration.seconds(2)
    /// The BPM is the mean of this many last intervals.
    public static let intervals = 4

    private var taps: [Duration] = []

    public init() {}

    public mutating func tap(at time: Duration) {
        if let last = taps.last, time - last > Self.maxGap { taps.removeAll() }
        taps.append(time)
        if taps.count > Self.intervals + 1 { taps.removeFirst(taps.count - Self.intervals - 1) }
    }

    /// Beats per minute, rounded; nil before the second tap of a count.
    public var bpm: Int? {
        guard let first = taps.first, let last = taps.last, taps.count > 1 else { return nil }
        let mean = (last - first) / (taps.count - 1)
        return Int((Duration.seconds(60) / mean).rounded())
    }
}
