import Foundation

/// A function that a key can do. Settings lists one row for each.
public enum KeyFunction: String, CaseIterable, Codable, Sendable {
    case switchA, switchB, switchC, switchD, switchE, switchF
    case bankDown, bankUp, pageDown, pageUp
    case engageI, engageJ, engageK
    case pedalUp, pedalDown

    /// What the key does. Pedal keys stand for both step sizes: Option picks the fine step.
    public var command: KeyCommand {
        switch self {
        case .switchA: .footswitch(.a)
        case .switchB: .footswitch(.b)
        case .switchC: .footswitch(.c)
        case .switchD: .footswitch(.d)
        case .switchE: .footswitch(.e)
        case .switchF: .footswitch(.f)
        case .bankDown: .navigate(.bankDown)
        case .bankUp: .navigate(.bankUp)
        case .pageDown: .navigate(.pageDown)
        case .pageUp: .navigate(.pageUp)
        // V04: the stored presets I, J and K.
        case .engageI: .engage(preset: 8)
        case .engageJ: .engage(preset: 9)
        case .engageK: .engage(preset: 10)
        case .pedalUp: .pedal(up: true, fine: false)
        case .pedalDown: .pedal(up: false, fine: false)
        }
    }

    /// The function of a command, or nil for a command that no key does, such as a sidebar step.
    init?(_ command: KeyCommand) {
        let plain: KeyCommand = if case .pedal(let up, _) = command { .pedal(up: up, fine: false) } else { command }
        guard let function = Self.allCases.first(where: { $0.command == plain }) else { return nil }
        self = function
    }
}

/// Which key does which function (V15). Keys go by physical key code (`kVK_*`), so the layout does not matter.
/// Each function has one key or none, and a key belongs to one function at most.
public struct KeyBindings: Equatable, Sendable {
    public private(set) var codes: [KeyFunction: UInt16]

    /// The v2 keys: A S D, Q W E, Z X, [ ], 1 2 3 and the up and down arrows.
    public static let defaults = KeyBindings(codes: [
        .switchA: 0x00, .switchB: 0x01, .switchC: 0x02, .switchD: 0x0C, .switchE: 0x0D, .switchF: 0x0E,
        .bankDown: 0x06, .bankUp: 0x07, .pageDown: 0x21, .pageUp: 0x1E,
        .engageI: 0x12, .engageJ: 0x13, .engageK: 0x14,
        .pedalUp: 0x7E, .pedalDown: 0x7D,
    ])

    private init(codes: [KeyFunction: UInt16]) {
        self.codes = codes
    }

    /// Gives `code` to `function`. V15: the function that had the key before has no key after.
    public mutating func assign(_ code: UInt16, to function: KeyFunction) {
        if let owner = self.function(for: code) { codes[owner] = nil }
        codes[function] = code
    }

    public mutating func clear(_ function: KeyFunction) {
        codes[function] = nil
    }

    public func function(for code: UInt16) -> KeyFunction? {
        codes.first { $0.value == code }?.key
    }

    /// A JSON object of function names and key codes. A function without a key is left out.
    public func encoded() -> Data {
        let object = Dictionary(uniqueKeysWithValues: codes.map { ($0.key.rawValue, Int($0.value)) })
        // A dictionary of strings and integers always encodes.
        return try! JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
    }

    /// The map of `encoded()`. Nil for bad JSON, a code outside 0 to 65535, or one code on two functions.
    /// A name that is not a function is skipped, and a function that is missing has no key.
    public static func decoded(_ data: Data) -> KeyBindings? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var codes: [KeyFunction: UInt16] = [:]
        for (name, value) in object {
            guard let number = value as? Int, let code = UInt16(exactly: number) else { return nil }
            if let function = KeyFunction(rawValue: name) { codes[function] = code }
        }
        guard Set(codes.values).count == codes.count else { return nil }
        return KeyBindings(codes: codes)
    }

    /// The text of a key at its US position, for Settings, the switches, the buttons and the menus.
    public static func label(for code: UInt16) -> String {
        labels[code] ?? "Key 0x" + String(code, radix: 16, uppercase: true)
    }

    private static let labels: [UInt16: String] = {
        var labels: [UInt16: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C",
            0x09: "V", 0x0A: "§", 0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T",
            0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9", 0x1A: "7",
            0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]", 0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
            0x24: "Return", 0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";", 0x2A: "\\", 0x2B: ",",
            0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".", 0x30: "Tab", 0x31: "Space", 0x32: "`", 0x33: "Delete",
            0x35: "Esc", 0x41: "Num .", 0x43: "Num *", 0x45: "Num +", 0x47: "Clear", 0x4B: "Num /",
            0x4C: "Enter", 0x4E: "Num -", 0x51: "Num =", 0x72: "Help", 0x73: "Home", 0x74: "Page Up",
            0x75: "Fwd Delete", 0x77: "End", 0x79: "Page Down",
            0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        ]
        let keypad: [UInt16] = [0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C]
        for (digit, code) in keypad.enumerated() { labels[code] = "Num \(digit)" }
        let functionKeys: [UInt16] = [
            0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F,
            0x50, 0x5A,
        ]
        for (index, code) in functionKeys.enumerated() { labels[code] = "F\(index + 1)" }
        return labels
    }()
}
