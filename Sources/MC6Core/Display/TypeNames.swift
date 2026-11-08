/// Plain names of the message types, from `type_namespaces` in the spec's reference/semantics.json.
/// Switch, bank and expression messages use three different enums: switch type 6 is SysEx, bank type 6 is Set Toggle.
public enum TypeNames {
    public enum Namespace: Sendable {
        case switchMessage, bankMessage, expression
    }

    /// The name of type `t`, or "Message type N" for a type the spec does not name.
    public static func name(_ t: Int, in namespace: Namespace) -> String {
        let names = switch namespace {
        case .switchMessage: switchNames
        case .bankMessage: bankNames
        case .expression: expressionNames
        }
        return names[t] ?? "Message type \(t)"
    }

    /// The name of bank event `a` (SEMANTICS.md section 3), or "N" for an event the spec does not name.
    public static func bankEvent(_ a: Int) -> String { bankEventNames[a] ?? "\(a)" }

    private static let bankEventNames: [Int: String] = [
        0: "Nothing", 1: "On Enter Bank", 2: "On Exit Bank", 3: "On Enter Bank (Execute Once Only)",
        4: "On Exit Bank (Execute Once Only)", 5: "On Enter Bank, Page 1", 6: "On Enter Bank, Page 2",
        7: "On Toggle Page, Page 1", 8: "On Toggle Page, Page 2", 9: "On Toggle Page, Page 3", 10: "On Toggle Page, Page 4",
        11: "On Enter Bank, Page 3", 12: "On Enter Bank, Page 4",
    ]

    private static let switchNames: [Int: String] = [
        1: "PC", 2: "CC", 3: "Note On", 4: "Note Off", 5: "Real Time", 6: "SysEx", 7: "Clock Tap",
        8: "PC Scroll Up", 9: "PC Scroll Down", 10: "Bank Up", 11: "Bank Down", 12: "Bank Change Mode", 13: "Bank Jump",
        14: "Toggle Page", 15: "Set Toggle", 16: "MIDI Thru", 17: "Select Expression", 18: "Looper Mode",
        19: "Strymon Bank Up", 20: "Strymon Bank Down", 21: "Axe-Fx Tuner", 22: "Toggle Preset", 23: "Delay",
        24: "MIDI Clock Tap", 25: "Song Position", 26: "CC Waveform", 27: "Engage Preset", 28: "Kemper Tuner",
        29: "Song Select", 30: "Set Display", 31: "CC Sequencer", 32: "CC Scroll", 33: "PC Scroll", 34: "PC Multi Channel",
        35: "Keystrokes", 36: "Utility", 37: "Axe-Fx Integration", 38: "NRPN", 39: "ML10X", 40: "Omniport Relay",
        41: "MMC", 42: "Trigger Messages", 43: "Focus Mode", 44: "Preset Rename", 45: "ML5R", 46: "Device Engage/Bypass",
    ]

    private static let bankNames: [Int: String] = [
        1: "PC", 2: "CC", 3: "Note On", 4: "Note Off", 5: "Real Time", 6: "Set Toggle", 7: "Select Expression",
        8: "Strymon Bank Up", 9: "Strymon Bank Down", 10: "Delay", 11: "Song Position", 12: "Looper Mode",
        13: "PC Scroll Up", 14: "PC Scroll Down", 15: "Engage Preset", 16: "Utility", 17: "PC Multi Channel",
        18: "MIDI Clock", 19: "Omniport Relay", 20: "MMC", 21: "Focus Mode", 22: "Bank Jump", 23: "Song Select",
        24: "CC Waveform", 25: "CC Sequencer", 26: "ML10X", 27: "Toggle Page", 28: "ML5R", 29: "SysEx",
        30: "Device Engage/Bypass",
    ]

    private static let expressionNames: [Int: String] = [
        1: "Pedal CC", 2: "Pedal CC on Toe Down", 3: "Pedal CC on Heel Down", 4: "Pedal Toggle Channel on Toe Down",
        5: "Pedal Toggle CC on Toe Down", 6: "Pedal CC on Engage", 7: "Pedal CC on Disengage", 8: "Pedal PC on Engage",
        9: "Pedal PC on Disengage", 10: "Pedal PC on Toe Down", 11: "Pedal PC on Heel Down", 12: "Pedal Pitch Bend",
        13: "Pedal CC Custom Response", 14: "Pedal Waveform Engine Speed", 15: "Pedal Sequencer Engine Speed",
        16: "Pedal Utility",
    ]
}
