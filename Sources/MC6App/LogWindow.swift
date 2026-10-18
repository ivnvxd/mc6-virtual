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
            List(Array(session.log.suffix(Self.shownLogLines).enumerated().reversed()), id: \.offset) { _, entry in
                Text(verbatim: describe(entry)).font(.caption.monospaced())
            }
            .frame(minHeight: 200)
            if let backup = session.backup, let state = session.engine?.state {
                activeMessages(ExpressionDisplay.selected(input: 0, state, in: backup))
                if !backup.notes.isEmpty { importNotes(backup.notes) }
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

    /// What the importer accepted with a remark, for example inert values (U01) and banks that never run.
    private func importNotes(_ notes: [ImportNote]) -> some View {
        DisclosureGroup {
            pointerList(notes.map { ($0.pointer, $0.text) })
                .frame(maxHeight: 160)
        } label: {
            Text(verbatim: "Import notes: \(notes.count)")
                .foregroundStyle(.secondary)
        }
    }
}

/// Rows of a JSON Pointer and its text, selectable, in a scroll view.
func pointerList(_ rows: [(pointer: String, text: String)]) -> some View {
    ScrollView {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: row.pointer).font(.caption.monospaced())
                    Text(verbatim: row.text).font(.caption)
                }
                .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

func describe(_ fault: EngineFault) -> String {
    "\(fault.reason) at \(fault.pointer)"
}

/// One log line: time, kind, bytes in hex, ports and the source message.
private func describe(_ entry: LogEntry) -> String {
    let time = String(format: "%10.1f ms", entry.milliseconds)
    switch entry.event {
    case .output(let bytes, let ports, let pointer, let live):
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        let to = ports.isEmpty ? "no port" : "port " + ports.numbers.map(String.init).joined(separator: "+")
        return "\(time)  \(live ? "sent" : "dry ")  \(hex)  \(to)  \(pointer)"
    case .tap:
        return "\(time)  tap"
    case .fault(let fault):
        return "\(time)  fault: \(describe(fault))"
    }
}
