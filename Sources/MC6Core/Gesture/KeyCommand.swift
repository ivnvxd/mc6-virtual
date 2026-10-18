/// The modifier keys that decide whether a key belongs to the app or to the menus.
public struct KeyModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let control = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let shift = KeyModifiers(rawValue: 1 << 3)
}

/// What a key does (plan v2, Keys table). Keys go by physical key code (`kVK_*`), so the layout does not matter.
public enum KeyCommand: Equatable, Sendable {
    case footswitch(Footswitch)
    case navigate(NavigationStep)
    /// V04: a stored preset of the shown bank, run as a short tap.
    case engage(preset: Int)
    /// Expression 1 up or down by the arrow step, or by the fine step with Option.
    case pedal(up: Bool, fine: Bool)

    /// Every key, with its virtual key code and label. Pedal keys stand for both step sizes.
    private static let keys: [(code: UInt16, label: String, command: KeyCommand)] = [
        (0x00, "A", .footswitch(.a)), (0x01, "S", .footswitch(.b)), (0x02, "D", .footswitch(.c)),
        (0x0C, "Q", .footswitch(.d)), (0x0D, "W", .footswitch(.e)), (0x0E, "E", .footswitch(.f)),
        (0x12, "1", .engage(preset: 8)), (0x13, "2", .engage(preset: 9)), (0x14, "3", .engage(preset: 10)),
        (0x06, "Z", .navigate(.bankDown)), (0x07, "X", .navigate(.bankUp)),
        (0x21, "[", .navigate(.pageDown)), (0x1E, "]", .navigate(.pageUp)),
        (0x7E, "↑", .pedal(up: true, fine: false)), (0x7D, "↓", .pedal(up: false, fine: false)),
    ]

    /// The command of a key; nil for other keys and for keys that the menus own: any key with Command or Control,
    /// and any key other than an arrow with Option. Shift changes nothing.
    public init?(keyCode: UInt16, modifiers: KeyModifiers) {
        guard modifiers.isDisjoint(with: [.command, .control]),
              let command = Self.keys.first(where: { $0.code == keyCode })?.command
        else { return nil }
        let option = modifiers.contains(.option)
        switch command {
        case .pedal(let up, _): self = .pedal(up: up, fine: option)
        default:
            guard !option else { return nil }
            self = command
        }
    }

    /// Only the pedal moves again while its key is held. Every other key acts once per press.
    public var repeats: Bool {
        if case .pedal = self { true } else { false }
    }

    /// The key that does this, for the buttons and the menus.
    public var label: String {
        let plain: KeyCommand = if case .pedal(let up, _) = self { .pedal(up: up, fine: false) } else { self }
        return Self.keys.first { $0.command == plain }?.label ?? ""
    }
}
