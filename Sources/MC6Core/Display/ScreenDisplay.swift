/// The band of one switch on a screen. Plain values, so a view only draws them.
public struct Band: Equatable, Sendable {
    public let button: Footswitch
    public let address: PresetAddress
    /// The temporary name (U09), else the toggle name at Position 2, else the short name.
    public let parts: [NamePart]
    public let position: Position
    public let text: RGB
    public let background: RGB
    /// The LED color, drawn as a strip on the outer edge of the screen.
    public let strip: RGB
    /// The switch letter, when switch letters are on.
    public let letter: String?
}

/// One of the three screens between the switch rows: the upper switch, the center lines and the lower switch.
public struct Screen: Equatable, Sendable {
    public let top: Band
    /// Black text on white, one entry per line.
    public let center: [[NamePart]]
    public let bottom: Band
}

/// The three screens of the MC6 Pro panel, from plain values, so snapshot mode needs no engine.
public enum ScreenDisplay {
    /// Screen 1 serves D and A, screen 2 E and B, screen 3 F and C.
    private static let columns: [(top: Footswitch, bottom: Footswitch)] = [(.d, .a), (.e, .b), (.f, .c)]

    public static func screens(
        _ state: RuntimeState, in backup: Backup, lastPressed: PresetAddress?, expression: Int, bpm: Int? = nil,
        showLetters: Bool
    ) -> [Screen] {
        let bank = backup.banks[state.bank]
        let centers: [[[NamePart]]] = [
            lastPressed.map { address in
                let preset = backup.banks[address.bank].presets[address.preset]
                let parts = NamePart.parts(preset.longName.isEmpty ? preset.shortName : preset.longName)
                return parts.isEmpty ? [] : [parts]
            } ?? [],
            [NamePart.parts(bank.name)],
            [
                [.text("EXP 1: \(Int((Double(expression) * 100 / 127).rounded()))%")],
                [.text("B\(String(format: "%03d", state.bank + 1)) PG\(state.page + 1)")],
            ] + (bpm.map { [[.text("\($0) BPM")]] } ?? []),
        ]
        return columns.enumerated().map { index, column in
            Screen(
                top: band(column.top, state, backup, showLetters),
                center: centers[index],
                bottom: band(column.bottom, state, backup, showLetters))
        }
    }

    private static func band(_ button: Footswitch, _ state: RuntimeState, _ backup: Backup, _ showLetters: Bool) -> Band {
        let address = state.address(of: button)
        let bank = backup.banks[address.bank]
        let preset = bank.presets[address.preset]
        let position = state[position: address]
        let name = state.names[address]
            ?? (position == .two && !preset.toggleName.isEmpty ? preset.toggleName : preset.shortName)
        let colors = position == .two ? preset.toggleColors : preset.colors
        var text = Palette.color(colors.text)
        var background = Palette.color(colors.background)
        var strip = Palette.color(colors.strip)
        if !bank.colorEnabled {
            (text, background, strip) = (Palette.color(7), Palette.color(0), Palette.color(0))
        }
        // V07: a name must never vanish into its background.
        if text == background { text = text == Palette.color(7) ? Palette.color(0) : Palette.color(7) }
        return Band(
            button: button, address: address, parts: NamePart.parts(name), position: position,
            text: text, background: background, strip: strip, letter: showLetters ? button.letter : nil)
    }
}
