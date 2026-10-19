/// The icon escapes of preset and bank names: a backslash and one ASCII character.
///
/// The Morningstar editor picks the icon whose number is the character's code, so the lookup is case-sensitive:
/// `\H` is a waveform and `\h` is a house. The values are SF Symbol names that look like the Morningstar icons.
public enum Icons {
    /// SF Symbol names by character code. The comment is the Morningstar icon file name.
    static let symbols: [UInt8: String] = [
        41: "mic.slash.fill", // mic_off
        42: "forward.end.fill", // resume
        43: "chevron.left.2", // keyboard_double_arrow_left
        44: "chevron.right.2", // keyboard_double_arrow_right
        45: "chevron.left", // keyboard_arrow_left
        46: "chevron.right", // keyboard_arrow_right
        47: "arrow.down", // arrow_down
        48: "arrow.up", // arrow_up
        49: "lock.open.fill", // lock_open
        50: "lock.fill", // lock
        51: "cable.connector", // settings_input
        52: "folder.fill", // folder_open
        53: "folder.fill", // folder
        54: "sportscourt.fill", // stadium
        55: "flame", // fire
        56: "slider.vertical.3", // instant_mix
        57: "megaphone.fill", // brand_awareness
        58: "speaker.wave.1.fill", // volume_down
        59: "repeat", // repeat
        60: "hifispeaker.fill", // speaker
        61: "square", // check_box_unchecked
        62: "checkmark.square.fill", // check_box
        63: "circle", // radio_button_unchecked
        64: "record.circle", // radioselect
        65: "triangle", // trianglewave
        66: "wave.3.right", // sinewave
        67: "backward.end.fill", // firstpage
        68: "forward.end.fill", // lastpage
        69: "arrow.up.to.line", // moveup
        70: "square.stack.3d.up.fill", // stack
        71: "pause.fill", // pause
        72: "waveform", // waveform
        73: "checkmark.circle.fill", // check_circle
        74: "wave.3.right", // sinewave
        75: "rectangle.portrait.and.arrow.right", // logout
        76: "rectangle.portrait.and.arrow.forward", // login
        77: "arrow.up.forward.square", // openinnew
        78: "arrow.triangle.2.circlepath", // sync
        79: "paintbrush.fill", // sweep
        80: "square.and.arrow.down", // install
        81: "face.smiling", // happy
        82: "airplane", // rocket
        83: "globe.americas.fill", // globe
        84: "eye.fill", // visibility
        85: "power", // power
        86: "infinity", // loop
        87: "slider.horizontal.3", // tune
        88: "square.grid.2x2.fill", // gridview
        89: "list.bullet", // list
        90: "music.note", // musicnote
        91: "speaker.slash", // musicnoteoff
        93: "birthday.cake.fill", // cake
        94: "arrow.left.arrow.right", // transition
        95: "backward.fill", // fast_rewind
        96: "forward.fill", // fast_forward
        97: "xmark.circle.fill", // cancel
        98: "playpause.fill", // playpause
        99: "circle.fill", // record
        100: "chevron.down", // down
        101: "arrowtriangle.down.fill", // statdown
        102: "speaker.wave.2.fill", // volume
        103: "speaker.slash.fill", // novolume
        104: "house.fill", // home
        105: "arrow.uturn.left", // undo
        106: "arrow.clockwise", // refresh
        107: "arrowtriangle.up.fill", // statup
        108: "arrowtriangle.left.fill", // left_arrow
        109: "trash", // trash
        111: "arrow.up.arrow.down", // updown
        112: "arrow.left.arrow.right", // leftright
        113: "mic.fill", // mic
        114: "play.fill", // play
        115: "stop.fill", // stop
        116: "heart.fill", // heart
        117: "chevron.up", // up
        118: "bolt.fill", // bolt
        119: "circle.circle", // center
        120: "star.fill", // star
        121: "square.split.2x1", // squarewave
        122: "bolt.horizontal", // sawtoothwave
        123: "xmark.octagon.fill", // skull
        124: "clock", // clock
    ]

    /// The SF Symbol name of an escape character; nil if the character has no icon.
    public static func symbol(for character: Character) -> String? {
        guard let code = character.asciiValue else { return nil }
        return symbols[code]
    }
}

/// A piece of a name: text, or an icon as an SF Symbol name.
public enum NamePart: Hashable, Sendable {
    case text(String)
    case icon(String)

    /// Splits a name into text and icons. An escape without an icon becomes the tag `[x]` (spec 6.3).
    /// A backslash at the end stays as it is.
    public static func parts(_ name: String) -> [NamePart] {
        var parts: [NamePart] = []
        var text = ""
        var escaped = false
        for character in name {
            if escaped {
                escaped = false
                if let symbol = Icons.symbol(for: character) {
                    if !text.isEmpty { parts.append(.text(text)) }
                    text = ""
                    parts.append(.icon(symbol))
                } else {
                    text += "[\(character)]"
                }
            } else if character == "\\" {
                escaped = true
            } else {
                text.append(character)
            }
        }
        if escaped { text.append("\\") }
        if !text.isEmpty { parts.append(.text(text)) }
        return parts
    }
}
