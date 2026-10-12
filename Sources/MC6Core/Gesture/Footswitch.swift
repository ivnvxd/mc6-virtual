/// A physical footswitch on the shown page. Spec 6.1: D E F on top, A B C below.
public enum Footswitch: Int, CaseIterable, Sendable {
    case a, b, c, d, e, f

    /// The key of each button, in `Footswitch` order: a macOS virtual key code (`kVK_ANSI_*`) and its label.
    /// By physical key, so the layout does not matter: A S D press A B C (bottom row), Q W E press D E F (top row).
    private static let keys: [(code: UInt16, label: String)] = [
        (0x00, "A"), (0x01, "S"), (0x02, "D"), (0x0C, "Q"), (0x0D, "W"), (0x0E, "E"),
    ]

    /// The button for a macOS virtual key code; nil for any other key.
    public init?(keyCode: UInt16) {
        guard let index = Self.keys.firstIndex(where: { $0.code == keyCode }) else { return nil }
        self.init(rawValue: index)
    }

    /// The letter on the button.
    public var letter: String { ["A", "B", "C", "D", "E", "F"][rawValue] }
    /// The key that presses it.
    public var key: String { Self.keys[rawValue].label }
}
