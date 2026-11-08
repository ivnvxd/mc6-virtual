/// The plain text of import notes and problems, for the main window, the Log window, snapshot errors and the
/// Copy buttons (V18). Banks, presets and messages count from 1, as in the Morningstar editor.
public enum ImportText {
    /// Where a pointer points: "Bank 3 VERSE, A LEAD, message 4". Field names after the message, preset or bank drop out.
    /// Without a backup, banks and presets have numbers only.
    public static func place(of pointer: String, in backup: Backup?) -> String {
        let parts = pointer.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] == "data" else { return pointer.isEmpty || parts.count == 1 ? "The file" : pointer }
        switch parts[1] {
        case "bankArray":
            guard parts.count >= 3, let b = Int(parts[2]) else { return pointer }
            let bank = backup.flatMap { $0.banks.indices.contains(b) ? $0.banks[b] : nil }
            var place = [bank.flatMap { plainName($0.name) }.map { "Bank \(b + 1) \($0)" } ?? "Bank \(b + 1)"]
            if parts.count >= 5, let index = Int(parts[4]) {
                switch parts[3] {
                case "presetArray":
                    let letter = String(UnicodeScalar(UInt8(ascii: "A") + UInt8(index % 26)))
                    let name = bank.flatMap { $0.presets.indices.contains(index) ? plainName($0.presets[index].shortName) : nil }
                    place.append(name.map { "\(letter) \($0)" } ?? letter)
                case "expPresetArray": place.append("EXP \(index + 1)")
                case "bankMsgArray": place.append("bank message \(index + 1)")
                default: break
                }
                if parts.count >= 7, parts[5] == "msgArray", let slot = Int(parts[6]) { place.append("message \(slot + 1)") }
            }
            return place.joined(separator: ", ")
        case "controller_settings":
            if parts.count >= 6, let index = Int(parts[5]) {
                if parts[3] == "midi_channels" { return "MIDI channel \(index + 1)" }
                if parts[3] == "midi_events" { return "MIDI event \(index + 1)" }
            }
            return "Controller settings"
        default:
            return pointer
        }
    }

    /// "Bank 1 HOME, A LEAD, message 1: Note On is not supported."
    public static func line(_ note: ImportNote, in backup: Backup) -> String {
        "\(place(of: note.pointer, in: backup)): \(note.text)"
    }

    /// A header problem is one sentence; any other problem has its place first.
    public static func line(_ problem: ImportProblem) -> String {
        headerPointers.contains(problem.pointer) ? problem.reason : "\(place(of: problem.pointer, in: nil)): \(problem.reason)"
    }

    /// "The backup did not load: 2 problems."
    public static func failure(_ problems: [ImportProblem]) -> String {
        "The backup did not load: \(count(problems.count, "problem"))."
    }

    /// "3 items skipped", or nil when the import skipped nothing.
    public static func skippedHeadline(_ notes: [ImportNote]) -> String? {
        let skipped = notes.filter(\.isSkipped).count
        return skipped == 0 ? nil : "\(count(skipped, "item")) skipped"
    }

    /// One line per group, in the order of `ImportNote.Kind`. Skipped messages group by their type, in order of appearance:
    /// "Note On: 14 messages in 3 banks".
    public static func summary(_ notes: [ImportNote]) -> [String] {
        var groups: [(kind: ImportNote.Kind, label: String, notes: [ImportNote])] = []
        for note in notes {
            let label = label(of: note)
            if let i = groups.firstIndex(where: { $0.kind == note.kind && $0.label == label }) {
                groups[i].notes.append(note)
            } else {
                groups.append((note.kind, label, [note]))
            }
        }
        let order = ImportNote.Kind.allCases
        return groups
            .enumerated()
            .sorted { (order.firstIndex(of: $0.element.kind)!, $0.offset) < (order.firstIndex(of: $1.element.kind)!, $1.offset) }
            .map { "\($0.element.label): \(amount(of: $0.element.notes, kind: $0.element.kind))" }
    }

    /// The note lines for the lists and the clipboard. Unused values with the same text join in one line with their
    /// counts, because a backup can have hundreds of them (U01): "114 messages in 8 banks: The Engage has ...".
    /// Every other note has its own line with its place. Lines keep the order of their first note.
    public static func lines(_ notes: [ImportNote], in backup: Backup) -> [String] {
        var groups: [String: [ImportNote]] = [:]
        for note in notes where note.kind == .unusedValue { groups[note.text, default: []].append(note) }
        var lines: [String] = []
        var joined: Set<String> = []
        for note in notes {
            guard note.kind == .unusedValue, let group = groups[note.text], group.count > 1 else {
                lines.append(line(note, in: backup))
                continue
            }
            guard joined.insert(note.text).inserted else { continue }
            let banks = Set(group.compactMap { bank(of: $0.pointer) }).count
            lines.append("\(count(group.count, "message")) in \(count(banks, "bank")): \(note.text)")
        }
        return lines
    }

    /// The summary, a blank line and the note lines: plain text for the clipboard.
    public static func copy(_ notes: [ImportNote], in backup: Backup) -> String {
        summary(notes).joined(separator: "\n") + "\n\n" + lines(notes, in: backup).joined(separator: "\n") + "\n"
    }

    /// The failure headline and every problem line: plain text for the clipboard and the snapshot error.
    public static func copy(_ problems: [ImportProblem]) -> String {
        ([failure(problems)] + problems.map(line)).joined(separator: "\n") + "\n"
    }

    // MARK: - Helpers

    private static let headerPointers: Set<String> = ["", "/schemaVersion", "/dumpType", "/deviceModel"]

    /// "1 bank", "2 banks".
    private static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

    private static func label(of note: ImportNote) -> String {
        switch note.kind {
        case .skippedMessage:
            let namespace: TypeNames.Namespace = note.pointer.contains("/expPresetArray/") ? .expression : .switchMessage
            return note.messageType.map { TypeNames.name($0, in: namespace) } ?? "Messages"
        case .toggleMode: return "Toggle Mode"
        case .toggleGroup: return "Toggle groups"
        case .bankMessage: return "Bank messages"
        case .bankClear: return "Bank clear"
        case .setting: return "Settings"
        case .color: return "Colors out of range"
        case .unusedValue: return "Unused message values"
        case .engageCycle: return "Engage cycles"
        case .unreachableBank: return "Banks not reachable from bank \(Importer.startBank + 1)"
        case .startBank: return "Start bank"
        case .unnamedColor: return "Colors without a name"
        case .colorsOff: return "Banks with colors off"
        }
    }

    private static func amount(of notes: [ImportNote], kind: ImportNote.Kind) -> String {
        let banks = Set(notes.compactMap { bank(of: $0.pointer) }).count
        switch kind {
        case .skippedMessage, .bankMessage: return "\(count(notes.count, "message")) in \(count(banks, "bank"))"
        case .toggleMode, .toggleGroup: return count(notes.count, "preset")
        case .bankClear: return count(notes.count, "bank")
        default: return "\(notes.count)"
        }
    }

    private static func bank(of pointer: String) -> Int? {
        let parts = pointer.split(separator: "/")
        return parts.count >= 3 && parts[1] == "bankArray" ? Int(parts[2]) : nil
    }
}

/// A name without its icons and outer spaces, or nil when nothing is left.
func plainName(_ name: String) -> String? {
    let text = NamePart.parts(name)
        .compactMap { if case .text(let text) = $0 { text } else { nil } }
        .joined()
        .trimmingCharacters(in: .whitespaces)
    return text.isEmpty ? nil : text
}
