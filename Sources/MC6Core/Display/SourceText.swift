import Foundation

extension Backup {
    /// The preset and message of an output's pointer, for the Sent strip and the Log window (V12):
    /// "A BOOST, message 4" or "EXP 1, message 2". Messages count from 1, as in the Morningstar editor.
    /// Icons drop out of the name. An expression preset shows its input, because the editor names
    /// expression presets "EMPTY" by default. Nil for any other pointer.
    public func source(of pointer: String) -> String? {
        // "", "data", "bankArray", B, "presetArray" or "expPresetArray", P, "msgArray", M
        let parts = pointer.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 8, parts[0].isEmpty, parts[1] == "data", parts[2] == "bankArray", parts[6] == "msgArray",
              let bank = Int(parts[3]), banks.indices.contains(bank),
              let index = Int(parts[5]),
              let slot = Int(parts[7]), (0..<32).contains(slot)
        else { return nil }
        let message = "message \(slot + 1)"
        switch parts[4] {
        case "presetArray":
            guard banks[bank].presets.indices.contains(index) else { return nil }
            let letter = String(UnicodeScalar(UInt8(ascii: "A") + UInt8(index)))
            let name = NamePart.parts(banks[bank].presets[index].shortName)
                .compactMap { if case .text(let text) = $0 { text } else { nil } }
                .joined()
                .trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? "\(letter), \(message)" : "\(letter) \(name), \(message)"
        case "expPresetArray":
            guard banks[bank].expressions.indices.contains(index) else { return nil }
            return "EXP \(index + 1), \(message)"
        default:
            return nil
        }
    }
}
