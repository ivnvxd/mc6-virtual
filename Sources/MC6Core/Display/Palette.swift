/// A color as 8-bit red, green and blue. Plain numbers, so the core needs no UI framework.
public struct RGB: Hashable, Sendable {
    public let red: Int
    public let green: Int
    public let blue: Int

    public init(red: Int, green: Int, blue: Int) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(hex: Int) {
        self.init(red: hex >> 16 & 0xFF, green: hex >> 8 & 0xFF, blue: hex & 0xFF)
    }

    /// The same color at `Palette.dimFactor` brightness.
    public var dimmed: RGB {
        func dim(_ value: Int) -> Int { Int((Double(value) * Palette.dimFactor).rounded()) }
        return RGB(red: dim(red), green: dim(green), blue: dim(blue))
    }
}

/// The palette of preset colors, indexes 0 to 127.
///
/// The names come from the Morningstar SysEx document. Morningstar publishes no RGB values, so the values are
/// CSS-style approximations. Indexes 15 to 28 dim 1 to 14, and indexes 64 to 127 dim `index - 64` (V06).
public enum Palette {
    /// The brightness of a dim color.
    public static let dimFactor = 0.45

    private static let base: [Int: (name: String, hex: Int)] = [
        0: ("Black", 0x000000), 1: ("Green", 0x00FF00), 2: ("Blue", 0x0000FF), 3: ("Purple", 0x8000FF),
        4: ("Yellow", 0xFFFF00), 5: ("Pink", 0xFF80C0), 6: ("Gray", 0x808080), 7: ("White", 0xFFFFFF),
        8: ("Orange", 0xFF8000), 9: ("Red", 0xFF0000), 10: ("Light Blue", 0x40A0FF), 11: ("Dark Pink", 0xFF1493),
        12: ("Pale Green", 0x98FB98), 13: ("Pale Purple", 0xC8A2FF), 14: ("Dark Green", 0x006400),
        29: ("Aqua", 0x00FFFF), 30: ("Turquoise", 0x40E0D0), 31: ("Cadet Blue", 0x5F9EA0), 32: ("Steel Blue", 0x4682B4),
        33: ("Light Steel Blue", 0xB0C4DE), 34: ("Tan", 0xD2B48C), 35: ("Brown", 0xA52A2A), 36: ("Cornsilk", 0xFFF8DC),
        37: ("Maroon", 0x800000), 38: ("Lavender", 0xE6E6FA), 39: ("Teal", 0x008080), 40: ("Dark Sea Green", 0x8FBC8F),
        41: ("Forest Green", 0x228B22), 42: ("Olive", 0x808000), 43: ("Indigo", 0x4B0082), 44: ("Blue Violet", 0x8A2BE2),
        45: ("Thistle", 0xD8BFD8), 46: ("Rebecca Purple", 0x663399), 47: ("Gold", 0xFFD700), 48: ("Khaki", 0xF0E68C),
        49: ("Dark Khaki", 0xBDB76B), 50: ("Light Yellow", 0xFFFFE0), 51: ("Light Salmon", 0xFFA07A),
        52: ("Tomato", 0xFF6347), 53: ("Orange Red", 0xFF4500), 54: ("Dark Orange", 0xFF8C00),
        55: ("Indian Red", 0xCD5C5C), 56: ("Salmon", 0xFA8072), 57: ("Fire Brick", 0xB22222), 58: ("Dark Red", 0x8B0000),
        59: ("Light Pink", 0xFFB6C1), 60: ("Hot Pink", 0xFF69B4), 61: ("Pale Violet Red", 0xDB7093),
        62: ("Slate Gray", 0x708090), 63: ("Light Gray", 0xD3D3D3),
    ]

    /// The SysEx name of a base color; nil for a dim index.
    public static func name(_ index: Int) -> String? { base[index]?.name }

    /// The color of a palette index. An index outside 0 to 127 is black; the importer refuses those.
    public static func color(_ index: Int) -> RGB {
        guard (0...127).contains(index) else { return RGB(hex: 0) }
        var index = index
        var dim = false
        if index >= 64 {
            index -= 64
            dim = true
        }
        if (15...28).contains(index) {
            index -= 14
            dim = true
        }
        let color = RGB(hex: base[index]?.hex ?? 0)
        return dim ? color.dimmed : color
    }
}
