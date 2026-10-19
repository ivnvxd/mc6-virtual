import MC6Core
import SwiftUI

/// The main window: a slim toolbar, banners for what blocks playing, the panel and the pedal.
struct MainWindow: View {
    @Bindable var model: AppModel

    private var session: Session { model.session }
    private var preferences: Preferences { model.preferences }

    /// Compact mode shows only the banners and the panel, and only while a backup is loaded.
    private var compact: Bool { preferences.compact && session.backup != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !compact { toolbar }
            if let portError = model.portError {
                notice("MIDI ports unavailable: \(portError). Quit any other MC6 Virtual and start again.")
            }
            if case .error(let fault) = session.mode {
                notice("Stopped: \(describe(fault)). Bytes already sent cannot be taken back. Arm to continue.")
            }
            if let fileError = model.fileError { notice(fileError) }
            if !session.importProblems.isEmpty { problems }
            if let backup = session.backup, let engine = session.engine, let longPress = session.longPress {
                let panel = ZoomedPanel(zoom: Double(preferences.zoomPercent) / 100) {
                    PanelView(
                        screens: ScreenDisplay.screens(
                            engine.state, in: backup, lastPressed: session.lastPressed, expression: model.expression,
                            bpm: session.bpm, showLetters: preferences.showLetters(backup)),
                        brightness: preferences.brightness(backup),
                        held: Set(model.held.keys),
                        longPress: longPress,
                        mode: activityMode,
                        flash: model.activityFlash,
                        page: engine.state.page,
                        pageCount: backup.banks[engine.state.bank].pageCount,
                        keys: preferences.keys,
                        onNavigate: { session.navigate($0) },
                        onDown: { model.down($0, source: .mouse) },
                        onUp: { model.up($0, source: .mouse) })
                }
                if compact {
                    panel
                } else {
                    VStack(spacing: 16) {
                        HStack(alignment: .center, spacing: 24) {
                            BankSidebar(backup: backup, shownBank: engine.state.bank) { session.navigate(.select($0)) }
                            panel
                            pedal
                        }
                        SentStrip(outputs: session.groupOutputs, start: session.groupTime, backup: backup)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                emptyState
            }
        }
        .padding()
        .modifier(WindowSize(compact: compact))
        .background(WindowReader { model.attach($0) })
        .onChange(of: session.outputCount) { model.flashActivity() }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == "json" }) else { return false }
            model.open(url)
            return true
        }
        .alert("Reset MC6 Virtual?", isPresented: $model.confirmReset) {
            Button("Reset", role: .destructive) { session.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("""
                The app goes back to the first bank, page 1, with every preset at Position 1, and disarms. \
                Reset sends no MIDI, so the receiving app keeps its current state.
                """)
        }
    }

    private var activityMode: ActivityMode {
        switch session.mode {
        case .dryRun: .dryRun
        case .live: .live
        case .error: .error
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            modeBadge
            Button(session.mode == .live ? "Disarm" : "Arm") {
                session.mode == .live ? session.disarm() : session.arm()
            }
            .disabled(session.backup == nil || model.portError != nil)
            Spacer()
            Button("Open…") { model.openPanel() }
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

    // MARK: - Pedal, problems and empty state

    private var pedal: some View {
        VStack(spacing: 8) {
            Text("EXP 1").font(PanelFont.print(12))
            PedalSlider(value: Binding(get: { model.expression }, set: { model.setPedal($0) }))
                .onHover { model.pedalHovered = $0 }
            Text(verbatim: "\(model.expression)").font(PanelFont.print(13)).monospacedDigit()
            Text(verbatim: "\(KeyCommand.pedal(up: true, fine: false).label(in: preferences.keys)) \(KeyCommand.pedal(up: false, fine: false).label(in: preferences.keys))")
                .font(PanelFont.print(10))
                .foregroundStyle(.secondary)
        }
    }

    private var problems: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "The backup did not load: \(session.importProblems.count) problems.").font(.headline)
            if session.backup != nil {
                Text("The previous backup stays loaded.").foregroundStyle(.secondary)
            }
            pointerList(session.importProblems.map { ($0.pointer.isEmpty ? "(file)" : $0.pointer, $0.reason) })
                .frame(maxHeight: 160)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.08)))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No backup loaded").font(.title3)
            Text("Open an MC6 Pro All Banks backup (.json), or drop it on this window.").foregroundStyle(.secondary)
            Button("Open…") { model.openPanel() }
            if !preferences.recent.paths.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent").font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(preferences.recent.paths, id: \.self) { path in
                        Button(URL(fileURLWithPath: path).lastPathComponent) { model.open(URL(fileURLWithPath: path)) }
                            .buttonStyle(.link)
                            .help(path)
                    }
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func notice(_ text: String) -> some View {
        Label { Text(verbatim: text) } icon: { Image(systemName: "exclamationmark.triangle") }
            .foregroundStyle(.red)
    }
}

/// Outside compact mode the window has a minimum size and grows with the user. In compact mode the window fits
/// the banners and the panel, because the window's content size sets the window size.
private struct WindowSize: ViewModifier {
    let compact: Bool

    func body(content: Content) -> some View {
        if compact {
            content.fixedSize()
        } else {
            content.frame(minWidth: 1100, minHeight: 560, alignment: .topLeading)
        }
    }
}

/// The outputs of the last press, engage or pedal move in plain words, oldest first (V12):
/// the time since the press, sent or dry, ports, the message and its source.
private struct SentStrip: View {
    let outputs: [LogEntry]
    let start: Duration
    let backup: Backup

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: outputs.isEmpty ? "Sent" : "Sent (\(outputs.count))").font(.caption.bold()).foregroundStyle(.secondary)
            if outputs.isEmpty {
                Text("Nothing sent. Press a switch or move the pedal.").font(.caption).foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(outputs.enumerated()), id: \.offset) { index, entry in
                            if case .output(let bytes, let ports, let pointer, let live) = entry.event {
                                HStack(spacing: 12) {
                                    Text(verbatim: "+\(Int((entry.time - start) / .milliseconds(1))) ms")
                                        .frame(width: 64, alignment: .trailing)
                                    Text(verbatim: live ? "sent" : "dry").foregroundStyle(live ? Color.green : Color.secondary)
                                        .frame(width: 32, alignment: .leading)
                                    Text(verbatim: Self.ports(ports)).frame(width: 72, alignment: .leading)
                                    Text(verbatim: MidiText.describe(bytes)).frame(width: 150, alignment: .leading)
                                    Text(verbatim: backup.source(of: pointer) ?? pointer).lineLimit(1).truncationMode(.middle)
                                }
                                .font(.caption.monospaced())
                                .id(index)
                            }
                        }
                    }
                }
                // A long group follows its newest output, for example during a pedal sweep.
                .onChange(of: outputs.count) { proxy.scrollTo(outputs.count - 1, anchor: .bottom) }
            }
        }
        .frame(width: 720, height: 118, alignment: .topLeading)
    }

    private static func ports(_ ports: Ports) -> String {
        let numbers = ports.numbers.map(String.init)
        return switch numbers.count {
        case 0: "no port"
        case 1: "Port \(numbers[0])"
        default: "Ports " + numbers.joined(separator: "+")
        }
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
        .frame(width: 32, height: 260)
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
