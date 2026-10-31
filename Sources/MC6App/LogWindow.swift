import AppKit
import MC6Core
import SwiftUI

/// The Log window: outputs, taps and faults, the import notes and the active pedal messages.
struct LogView: View {
    @Bindable var model: AppModel

    /// The newest log entries the window shows. The session keeps up to `Session.logLimit`.
    private static let shownLogLines = 200

    private var session: Session { model.session }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Log").font(.headline)
                Text(verbatim: "\(session.log.count) entries, newest first").foregroundStyle(.secondary)
                Spacer()
                Button("Export…") { model.exportLog() }.disabled(session.log.isEmpty)
            }
            if let fileError = model.fileError { Text(verbatim: fileError).foregroundStyle(.red) }
            // Stable ids, so an append or a trim does not move every row.
            let first = max(session.log.count - Self.shownLogLines, 0)
            let rows = (first..<session.log.count).reversed().map { (id: session.logID(at: $0), entry: session.log[$0]) }
            List(rows, id: \.id) { row in
                Text(verbatim: describe(row.entry, in: session.backup)).font(.caption.monospaced())
            }
            .frame(minHeight: 200)
            if let backup = session.backup, let state = session.engine?.state {
                activeMessages(ExpressionDisplay.selected(input: 0, state, in: backup))
                if !backup.notes.isEmpty { importNotes(backup.notes, backup) }
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 420, alignment: .topLeading)
    }

    private func activeMessages(_ selected: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Expression 1, active messages").font(.caption.bold())
            if selected.isEmpty {
                Text("None selected").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(selected, id: \.self) { Text(verbatim: $0).font(.caption.monospaced()) }
        }
    }

    /// What the importer skipped or replaced (V18), and remarks such as unused values and banks that never run.
    private func importNotes(_ notes: [ImportNote], _ backup: Backup) -> some View {
        DisclosureGroup {
            ImportNotesView(notes: notes, backup: backup).frame(maxHeight: 200)
        } label: {
            Text(verbatim: "Import notes: \(notes.count)")
                .foregroundStyle(.secondary)
        }
    }
}

/// The import notes: one summary line per kind, then every note with its place, and a Copy button (V18).
struct ImportNotesView: View {
    let notes: [ImportNote]
    let backup: Backup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(ImportText.summary(notes), id: \.self) { Text(verbatim: $0).font(.caption.bold()) }
                }
                Spacer()
                Button("Copy") { copyToClipboard(ImportText.copy(notes, in: backup)) }
            }
            textList(notes.map { ImportText.line($0, in: backup) })
        }
    }
}

/// Lines of plain text, selectable, in a scroll view.
func textList(_ lines: [String]) -> some View {
    ScrollView {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line).font(.caption).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Puts plain text on the clipboard.
func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

func describe(_ fault: EngineFault) -> String {
    "\(fault.reason) at \(fault.pointer)"
}

/// One log line: time, kind, bytes in hex, ports, the message as text and its source (V12).
/// Without a source name, the line shows the pointer.
private func describe(_ entry: LogEntry, in backup: Backup?) -> String {
    let time = String(format: "%10.1f ms", entry.milliseconds)
    switch entry.event {
    case .output(let bytes, let ports, let pointer, let live):
        let to = ports.isEmpty ? "no port" : "port " + ports.numbers.map(String.init).joined(separator: "+")
        let source = backup?.source(of: pointer) ?? pointer
        return "\(time)  \(live ? "sent" : "dry ")  \(MidiText.hex(bytes))  \(to)  \(MidiText.describe(bytes))  \(source)"
    case .tap:
        return "\(time)  tap"
    case .fault(let fault):
        return "\(time)  fault: \(describe(fault))"
    }
}
