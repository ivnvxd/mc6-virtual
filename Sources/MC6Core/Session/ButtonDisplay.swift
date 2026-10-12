/// What one physical footswitch shows on the shown page (spec 6.1, 6.3).
public struct ButtonDisplay: Sendable, Equatable {
    public let button: Footswitch
    /// The stored preset under the button (`RuntimeState.address(of:)`).
    public let address: PresetAddress
    public let position: Position
    /// The readable name: the temporary name (U09), else the toggle name at Position 2, else the short name.
    public let name: String

    /// Physical A to F of the shown bank and page, in `Footswitch` order.
    public static func shown(_ state: RuntimeState, in backup: Backup) -> [ButtonDisplay] {
        Footswitch.allCases.map { button in
            let address = state.address(of: button)
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
