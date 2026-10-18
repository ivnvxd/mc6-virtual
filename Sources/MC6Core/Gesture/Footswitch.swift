/// A physical footswitch on the shown page. Spec 6.1: D E F on top, A B C below.
public enum Footswitch: Int, CaseIterable, Sendable {
    case a, b, c, d, e, f

    /// The letter on the button.
    public var letter: String { ["A", "B", "C", "D", "E", "F"][rawValue] }
    /// The key that presses it.
    public var key: String { KeyCommand.footswitch(self).label }
}
