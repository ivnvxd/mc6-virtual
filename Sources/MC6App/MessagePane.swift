import MC6Core
import SwiftUI

/// The pane under the panel, with two views in the same columns. "Last Press" shows the outputs of the last press,
/// engage or pedal move (V12): the time since the press, sent or dry, the ports, the message and its source.
/// "History" shows the newest entries of the whole log with the time since the launch. Both list the oldest entry
/// first and follow the newest. The pane is in the main window, so the keys play while the user reads it.
struct MessagePane: View {
    let session: Session
    let backup: Backup
    @Bindable var preferences: Preferences
    /// Arms the session after a Dry Run press. Nil hides the button.
    let onArm: (() -> Void)?
    let onExport: () -> Void

    /// The newest log entries that History shows. The session keeps up to `Session.logLimit`, for the export.
    private static let historyLimit = 500

    /// One log entry as the texts of its columns.
    private struct Row: Identifiable {
        let id: Int
        let time: String
        /// "sent", "dry", "tap" or "fault".
        let state: String
        var ports = ""
        var message = ""
        var source = ""

        /// The row as one line of text, for Copy.
        var line: String {
            [time, state, ports.isEmpty ? "" : "port \(ports)", message, source].filter { !$0.isEmpty }.joined(separator: "  ")
        }
    }

    private func row(_ entry: LogEntry, id: Int, time: String) -> Row {
        switch entry.event {
        case .output(let bytes, let ports, let pointer, let live):
            Row(
                id: id, time: time, state: live ? "sent" : "dry",
                ports: ports.isEmpty ? "none" : ports.numbers.map(String.init).joined(separator: "+"),
                message: MidiText.describe(bytes), source: backup.source(of: pointer) ?? pointer)
        case .tap:
            Row(id: id, time: time, state: "tap", message: "MIDI Clock Tap")
        case .fault(let fault):
            Row(id: id, time: time, state: "fault", message: ModeText.fault(fault, in: backup))
        }
    }

    private var lastPress: [Row] {
        let start = session.groupTime
        return session.groupOutputs.enumerated().map { index, entry in
            row(entry, id: index, time: "+\(Int((entry.time - start) / .milliseconds(1))) ms")
        }
    }

    private var history: [Row] {
        let log = session.log
        return (max(log.count - Self.historyLimit, 0)..<log.count).map { index in
            row(log[index], id: session.logID(at: index), time: String(format: "%.3f s", log[index].milliseconds / 1000))
        }
    }

    /// What the shown view holds, in words. Empty when there is nothing to say.
    private var title: String {
        if preferences.paneHistory {
            let count = session.log.count
            return count > Self.historyLimit
                ? "The newest \(Self.historyLimit) of \(count.formatted()) entries"
                : "\(count.formatted()) \(count == 1 ? "entry" : "entries") since the launch"
        }
        return session.groupCount > 0 ? ModeText.sentHeader(session.groupOutputs, total: session.groupCount) : ""
    }

    var body: some View {
        let rows = preferences.paneHistory ? history : lastPress
        VStack(alignment: .leading, spacing: 6) {
            header
            if rows.isEmpty {
                Text(preferences.paneHistory ? "The log is empty." : "Nothing yet. Press a switch or move the pedal.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                columns(time: "Time", state: Text(verbatim: ""), ports: "Port", message: "Message", source: "Source")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                list(rows)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Picker("View", selection: $preferences.paneHistory) {
                Text("Last Press").tag(false)
                Text("History").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
            Text(verbatim: title).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            if !preferences.paneHistory, let onArm, title.hasPrefix("Dry Run") {
                Button("Arm", action: onArm).controlSize(.small).help(ModeText.armHelp)
            }
            Spacer(minLength: 0)
            if preferences.paneHistory {
                Button("Export…", action: onExport).controlSize(.small).disabled(session.log.isEmpty)
            }
        }
        .frame(height: 22)
    }

    private func list(_ rows: [Row]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(rows) { row in
                        line(row)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button("Copy Line") { copyToClipboard(row.line) }
                                Button("Copy All Lines") { copyToClipboard(rows.map(\.line).joined(separator: "\n")) }
                            }
                    }
                }
            }
            // The list follows its newest entry, for example during a pedal sweep.
            .onChange(of: rows.last?.id) { _, last in
                if let last { proxy.scrollTo(last, anchor: .bottom) }
            }
            .onAppear {
                if let last = rows.last?.id { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
        // A change of the view builds the list again, so it opens at its newest entry.
        .id(preferences.paneHistory)
    }

    @ViewBuilder private func line(_ row: Row) -> some View {
        switch row.state {
        case "sent", "dry":
            columns(
                time: row.time,
                state: Text(verbatim: row.state).foregroundStyle(row.state == "sent" ? Color.green : Color.secondary),
                ports: row.ports, message: row.message, source: row.source)
        default:
            // A tap and a fault have no port and no source: their text takes the rest of the line.
            HStack(spacing: Self.gap) {
                Text(verbatim: row.time).frame(width: Self.timeWidth, alignment: .trailing)
                Text(verbatim: "\(row.state)  \(row.message)")
                    .foregroundStyle(row.state == "fault" ? Color.red : Color.secondary)
                    .lineLimit(1)
            }
        }
    }

    private static let gap: CGFloat = 14
    private static let timeWidth: CGFloat = 76

    /// One line of the table. The header and the rows use it, so their columns line up.
    private func columns(time: String, state: Text, ports: String, message: String, source: String) -> some View {
        HStack(spacing: Self.gap) {
            Text(verbatim: time).frame(width: Self.timeWidth, alignment: .trailing)
            state.frame(width: 32, alignment: .leading)
            Text(verbatim: ports).frame(width: 36, alignment: .leading)
            Text(verbatim: message).frame(width: 200, alignment: .leading)
            Text(verbatim: source).lineLimit(1).truncationMode(.middle)
        }
    }
}
