/// The modifier keys that decide whether a key belongs to the app or to the menus.
public struct KeyModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let control = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let shift = KeyModifiers(rawValue: 1 << 3)
}

/// What a key does. Keys go by physical key code (`kVK_*`), so the layout does not matter.
public enum KeyCommand: Equatable, Sendable {
    case footswitch(Footswitch)
    case navigate(NavigationStep)
    /// V04: a stored preset of the shown bank, run as a short tap.
    case engage(preset: Int)
    /// Expression 1 up or down by the arrow step, or by the fine step with Option.
    case pedal(up: Bool, fine: Bool)

    /// The command of a key in `map`; nil for other keys and for keys that the menus own: any key with Command or
    /// Control, and any key other than a pedal key with Option. Shift changes nothing.
    public init?(keyCode: UInt16, modifiers: KeyModifiers, map: KeyBindings) {
        guard modifiers.isDisjoint(with: [.command, .control]), let command = map.function(for: keyCode)?.command
        else { return nil }
        let option = modifiers.contains(.option)
        switch command {
        case .pedal(let up, _): self = .pedal(up: up, fine: option)
        default:
            guard !option else { return nil }
            self = command
        }
    }

    /// The key that does this in `map`, for the switches, the buttons and the menus. Empty without a key.
    public func label(in map: KeyBindings) -> String {
        guard let function = KeyFunction(self), let code = map.codes[function] else { return "" }
        return KeyBindings.label(for: code)
    }
}
