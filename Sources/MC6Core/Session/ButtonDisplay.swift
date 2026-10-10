/// What one physical footswitch shows on the shown page (spec 6.1, 6.3).
public struct ButtonDisplay: Sendable, Equatable {
    public let button: Footswitch
    /// The stored preset under the button: `page * 6 + button`.
    public let address: PresetAddress
    public let position: Position
    /// The readable name: the temporary name (U09), else the toggle name at Position 2, else the short name.
    public let name: String

    /// Physical A to F of the shown bank and page, in `Footswitch` order.
    public static func shown(_ state: RuntimeState, in backup: Backup) -> [ButtonDisplay] {
        Footswitch.allCases.map { button in
            let address = PresetAddress(bank: state.bank, preset: state.page * 6 + button.rawValue)
            let preset = backup.banks[address.bank].presets[address.preset]
            let position = state[position: address]
            let name = state.names[address]
                ?? (position == .two && !preset.toggleName.isEmpty ? preset.toggleName : preset.shortName)
            return ButtonDisplay(button: button, address: address, position: position, name: readable(name))
        }
    }

    /// Spec 6.3: an icon escape such as `\H` shows as the tag `[H]`. The model keeps the escape.
    public static func readable(_ name: String) -> String {
        var result = ""
        var escaped = false
        for character in name {
            if escaped {
                result += "[\(character)]"
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        return escaped ? result + "\\" : result
    }
}

extension Footswitch {
    /// The button for a macOS virtual key code (`kVK_ANSI_*`), by physical key so the layout does not matter:
    /// Q W E press D E F (top row), A S D press A B C (bottom row).
    public init?(keyCode: UInt16) {
        switch keyCode {
        case 0x0C: self = .d  // Q
        case 0x0D: self = .e  // W
        case 0x0E: self = .f  // E
        case 0x00: self = .a  // A
        case 0x01: self = .b  // S
        case 0x02: self = .c  // D
        default: return nil
        }
    }
}
