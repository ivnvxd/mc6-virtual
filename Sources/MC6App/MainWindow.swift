import MC6Core
import SwiftUI

struct MainWindow: View {
    @Bindable var model: AppModel

    private var session: Session { model.session }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let portError = model.portError {
                notice("MIDI ports unavailable: \(portError). Quit any other MC6 Virtual and start again.")
            }
            if case .error(let fault) = session.mode {
                notice("Stopped: \(describe(fault)). Bytes already sent cannot be taken back. Arm to continue.")
            }
            if let fileError = model.fileError { notice(fileError) }
            if !session.importProblems.isEmpty { problems }
            if let notes = session.backup?.notes, !notes.isEmpty { importNotes(notes) }
            if let backup = session.backup, let engine = session.engine, let longPress = session.longPress {
                HStack(alignment: .top, spacing: 24) {
                    footswitches(ButtonDisplay.shown(engine.state, in: backup), longPress: longPress)
                    pedal(ExpressionDisplay.selected(input: 0, engine.state, in: backup))
                }
                logPanel
            } else {
                emptyState
            }
        }
        .padding()
        .frame(minWidth: 760, minHeight: 600, alignment: .topLeading)
        .alert("Reset the emulator?", isPresented: $model.confirmReset) {
            Button("Reset", role: .destructive) { session.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("""
                The emulator goes back to the first bank, page 1, with every preset at Position 1, and disarms. \
                Ableton is not reset: its tracks and devices keep their current state.
                """)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            if let backup = session.backup, let state = session.engine?.state {
                let bank = backup.banks[state.bank]
                Text(verbatim: ButtonDisplay.readable(bank.name)).font(.title2.bold())
                HStack(spacing: 4) {
                    ForEach(0..<bank.pageCount, id: \.self) { page in
                        Circle()
                            .fill(page == state.page ? Color.primary : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                Text(verbatim: "Page \(state.page + 1) of \(bank.pageCount)").foregroundStyle(.secondary)
            } else {
                Text("No backup").font(.title2.bold())
            }
            Spacer()
            modeBadge
            Button(session.mode == .live ? "Disarm" : "Arm") {
                session.mode == .live ? session.disarm() : session.arm()
            }
            .disabled(session.backup == nil || model.portError != nil)
            Button("Import…") { model.importBackup() }
            Button("Reset…") { model.confirmReset = true }.disabled(session.backup == nil)
        }
    }

    private var modeBadge: some View {
        let (text, symbol, color): (String, String, Color) =
            switch session.mode {
            case .dryRun: ("Dry Run", "pause.circle", .gray)
            case .live: ("Live", "dot.radiowaves.left.and.right", .green)
            case .error: ("Error", "exclamationmark.triangle", .red)
            }
        return Label(text, systemImage: symbol)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.25)))
            .overlay(Capsule().stroke(color))
    }

    // MARK: - Footswitches and pedal

    /// MC6 layout: D E F on top, A B C below.
    private func footswitches(_ shown: [ButtonDisplay], longPress: Duration) -> some View {
        VStack(spacing: 16) {
            ForEach([[Footswitch.d, .e, .f], [.a, .b, .c]], id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { button in
                        FootswitchView(
                            display: shown[button.rawValue],
                            isHeld: model.held[button] != nil,
                            longPress: longPress,
                            onDown: { model.down(button, source: .mouse) },
                            onUp: { model.up(button, source: .mouse) })
                    }
                }
            }
        }
    }

    private func pedal(_ selected: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Expression 1").font(.headline)
            HStack(alignment: .bottom, spacing: 12) {
                PedalSlider(value: $model.expression)
                Text(verbatim: "\(model.expression)").monospacedDigit()
            }
            Text("Active messages").font(.caption.bold())
            if selected.isEmpty {
                Text("None selected").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(selected, id: \.self) { Text(verbatim: $0).font(.caption.monospaced()) }
        }
        .frame(width: 200, alignment: .leading)
    }

    // MARK: - Log, problems and empty state

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Log").font(.headline)
                Text(verbatim: "\(session.log.count) entries, newest first").foregroundStyle(.secondary)
                Spacer()
                Button("Export…") { model.exportLog() }.disabled(session.log.isEmpty)
            }
            List(Array(session.log.suffix(200).enumerated().reversed()), id: \.offset) { _, entry in
                Text(verbatim: describe(entry)).font(.caption.monospaced())
            }
            .frame(minHeight: 140)
        }
    }

    private var problems: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "The backup did not load: \(session.importProblems.count) problems.").font(.headline)
            if session.backup != nil {
                Text("The previous backup stays loaded.").foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(session.importProblems.enumerated()), id: \.offset) { _, problem in
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: problem.pointer.isEmpty ? "(file)" : problem.pointer).font(.caption.monospaced())
                            Text(verbatim: problem.reason).font(.caption)
                        }
                        .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.08)))
    }

    /// What the importer accepted with a remark, for example inert values (U01) and banks that never run.
    private func importNotes(_ notes: [ImportNote]) -> some View {
        DisclosureGroup {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: note.pointer).font(.caption.monospaced())
                            Text(verbatim: note.text).font(.caption)
                        }
                        .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
        } label: {
            Text(verbatim: "Import notes: \(notes.count)")
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No backup loaded").font(.title3)
            Text("Import an MC6 Pro All Banks backup (.json) to start.").foregroundStyle(.secondary)
            Button("Import…") { model.importBackup() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func notice(_ text: String) -> some View {
        Label { Text(verbatim: text) } icon: { Image(systemName: "exclamationmark.triangle") }
            .foregroundStyle(.red)
    }
}

/// A vertical pedal, 0 at the bottom and 127 at the top.
private struct PedalSlider: View {
    @Binding var value: Int

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                RoundedRectangle(cornerRadius: 6).fill(Color.accentColor).frame(height: height * CGFloat(value) / 127)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                value = min(127, max(0, Int(((1 - drag.location.y / height) * 127).rounded())))
            })
        }
        .frame(width: 32, height: 220)
        .accessibilityElement()
        .accessibilityLabel("Expression 1")
        .accessibilityValue(String(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(127, value + 1)
            case .decrement: value = max(0, value - 1)
            @unknown default: break
            }
        }
    }
}

private func describe(_ fault: EngineFault) -> String {
    "\(fault.reason) at \(fault.pointer)"
}

/// One log line: time, kind, bytes in hex, ports and the source message.
private func describe(_ entry: LogEntry) -> String {
    let time = String(format: "%10.1f ms", entry.time / .milliseconds(1))
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
