import MC6Core
import SwiftUI

/// The main window: the toolbar, the bank sidebar, banners for what blocks playing, the panel with the pedal,
/// and the Sent pane under them. Compact mode shows only the banners and the panel.
struct MainWindow: View {
    @Bindable var model: AppModel

    private var session: Session { model.session }
    private var preferences: Preferences { model.preferences }
    /// The notes popover of the skipped line. Plain storage, because the `@State` macro is not available.
    private let showNotes = State(initialValue: false)
    /// The size of the panel at zoom 1. The full layout scales the panel to fit its space.
    private let panelSize = State(initialValue: CGSize.zero)

    /// Compact mode shows only the banners and the panel, and only while a backup is loaded.
    private var compact: Bool { preferences.compact && session.backup != nil }

    var body: some View {
        content
            .modifier(WindowSize(compact: compact))
            .toolbar { toolbar }
            .toolbar(compact ? .hidden : .automatic, for: .windowToolbar)
            .modifier(DocumentTitle(url: session.backup == nil ? nil : model.backupURL))
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
                    It runs the On Enter Bank messages of the first bank in Dry Run, so the receiving app keeps its current state.
                    """)
            }
    }

    @ViewBuilder private var content: some View {
        if let backup = session.backup, let engine = session.engine, let longPress = session.longPress {
            if compact {
                VStack(alignment: .leading, spacing: 12) {
                    banners
                    panel(backup, engine, longPress, zoom: Double(preferences.zoomPercent) / 100)
                }
                .padding()
            } else {
                NavigationSplitView {
                    BankSidebar(backup: backup, shownBank: engine.state.bank) { session.navigate(.select($0)) }
                } detail: {
                    VStack(spacing: 0) {
                        if hasBanners {
                            VStack(alignment: .leading, spacing: 8) { banners }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding([.horizontal, .top])
                        }
                        fittedPanel(backup, engine, longPress)
                        PaneDivider(preferences: preferences)
                        SentStrip(
                            outputs: session.groupOutputs, total: session.groupCount, start: session.groupTime,
                            backup: backup, onArm: session.mode == .live || model.portError != nil ? nil : { session.arm() })
                            .frame(height: CGFloat(preferences.sentHeight))
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                banners
                emptyState
            }
            .padding()
        }
    }

    // MARK: - Panel

    private func panel(_ backup: Backup, _ engine: Engine, _ longPress: Duration, zoom: Double) -> some View {
        ZoomedPanel(zoom: zoom) {
            PanelView(
                screens: ScreenDisplay.screens(
                    engine.state, in: backup, lastPressed: session.lastPressed, expression: model.expression,
                    bpm: session.bpm, showLetters: preferences.showLetters(backup)),
                brightness: preferences.brightness(backup),
                held: Set(model.held.keys),
                longPress: longPress,
                mode: ActivityMode(session.mode),
                modeLabel: compact ? ModeText.label(session.mode) : nil,
                flash: model.activityFlash,
                page: engine.state.page,
                pageCount: backup.banks[engine.state.bank].pageCount,
                keys: preferences.keys,
                onNavigate: { session.navigate($0) },
                onDown: { model.down($0, source: .mouse) },
                onUp: { model.up($0, source: .mouse) })
            .onGeometryChange(for: CGSize.self, of: \.size) { panelSize.wrappedValue = $0 }
        }
    }

    /// The panel and the pedal, scaled together to fill the space above the Sent pane.
    private func fittedPanel(_ backup: Backup, _ engine: Engine, _ longPress: Duration) -> some View {
        GeometryReader { geometry in
            let scale = fitScale(geometry.size)
            HStack(spacing: Self.pedalGap * scale) {
                panel(backup, engine, longPress, zoom: scale)
                pedal(height: Self.pedalHeight * scale)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .padding(24)
        .frame(minHeight: 200)
    }

    private static let pedalGap: CGFloat = 24
    private static let pedalHeight: CGFloat = 260
    /// The pedal column: the slider, its labels and some air.
    private static let pedalWidth: CGFloat = 48

    /// The largest scale at which the panel and the pedal fit, from 0.5 to 2. It is 1 until the panel was measured.
    private func fitScale(_ space: CGSize) -> CGFloat {
        let natural = panelSize.wrappedValue
        guard natural.width > 0, natural.height > 0 else { return 1 }
        let width = space.width / (natural.width + Self.pedalGap + Self.pedalWidth)
        let height = space.height / natural.height
        return min(max(min(width, height), 0.5), 2)
    }

    // MARK: - Toolbar and banners

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            modeBadge
            Button(session.mode == .live ? "Disarm" : "Arm") {
                session.mode == .live ? session.disarm() : session.arm()
            }
            .help(session.mode == .live ? "Go back to Dry Run." : ModeText.armHelp)
            .disabled(session.backup == nil || model.portError != nil)
        }
        ToolbarItemGroup(placement: .primaryAction) {
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
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.25)))
            .overlay(Capsule().stroke(color))
    }

    /// What blocks playing or what the import skipped. Empty when all is well.
    @ViewBuilder private var banners: some View {
        if let portError = model.portError {
            notice("MIDI ports unavailable: \(portError). Quit any other MC6 Virtual and start again.")
        }
        if case .error(let fault) = session.mode { faultBanner(fault) }
        if let fileError = model.fileError { notice(fileError) }
        if !session.importProblems.isEmpty { problems }
        if let backup = session.backup, let headline = skippedHeadline { skippedLine(headline, backup) }
    }

    private var skippedHeadline: String? {
        guard let backup = session.backup, session.importProblems.isEmpty else { return nil }
        return ImportText.skippedHeadline(backup.notes)
    }

    private var hasBanners: Bool {
        if case .error = session.mode { return true }
        return model.portError != nil || model.fileError != nil || !session.importProblems.isEmpty || skippedHeadline != nil
    }

    // MARK: - Pedal, problems and empty state

    private func pedal(height: CGFloat) -> some View {
        VStack(spacing: 8) {
            Text("EXP 1").font(PanelFont.print(12))
            PedalSlider(value: Binding(get: { model.expression }, set: { model.setPedal($0) }), height: height)
                .onHover { model.pedalHovered = $0 }
            Text(verbatim: "\(model.expression)").font(PanelFont.print(13)).monospacedDigit()
            Text(verbatim: "\(KeyCommand.pedal(up: true, fine: false).label(in: preferences.keys)) \(KeyCommand.pedal(up: false, fine: false).label(in: preferences.keys))")
                .font(PanelFont.print(10))
                .foregroundStyle(.secondary)
        }
    }

    private var problems: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: ImportText.failure(session.importProblems)).font(.headline)
                Spacer()
                Button("Copy") { copyToClipboard(ImportText.copy(session.importProblems)) }
            }
            if session.backup != nil {
                Text("The previous backup stays loaded.").foregroundStyle(.secondary)
            }
            textList(session.importProblems.map(ImportText.line))
                .frame(maxHeight: 160)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.08)))
    }

    /// V18: the backup loaded, but the app skips some of its content. The marked bands belong to it.
    private func skippedLine(_ headline: String, _ backup: Backup) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
            Text(verbatim: "Loaded with \(headline). Marked bands have skipped content.")
            Button("Show Notes") { showNotes.wrappedValue = true }
                .buttonStyle(.link)
                .popover(isPresented: showNotes.projectedValue, arrowEdge: .bottom) {
                    ImportNotesView(notes: backup.notes, backup: backup)
                        .padding()
                        .frame(width: 640, height: 380)
                }
        }
        .foregroundStyle(.secondary)
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

    /// The press stopped and the session disarmed. Arm sends again; Back to Dry Run keeps it silent.
    private func faultBanner(_ fault: EngineFault) -> some View {
        HStack(spacing: 12) {
            notice(ModeText.fault(fault, in: session.backup))
            Button("Arm") { session.arm() }.help(ModeText.armHelp).disabled(model.portError != nil)
            Button("Back to Dry Run") { session.disarm() }
        }
    }

    private func notice(_ text: String) -> some View {
        Label { Text(verbatim: text) } icon: { Image(systemName: "exclamationmark.triangle") }
            .foregroundStyle(.red)
    }
}

/// The window title is the loaded file, with its proxy icon, so the user sees which export is open.
private struct DocumentTitle: ViewModifier {
    let url: URL?

    func body(content: Content) -> some View {
        if let url {
            content.navigationTitle(url.lastPathComponent).navigationDocument(url)
        } else {
            content.navigationTitle("MC6 Virtual")
        }
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
            content.frame(minWidth: 900, minHeight: 600, alignment: .topLeading)
        }
    }
}

/// The outputs of the last press, engage or pedal move in plain words, oldest first (V12):
/// the time since the press, sent or dry, ports, the message and its source.
private struct SentStrip: View {
    let outputs: [LogEntry]
    /// The size of the whole group, also outputs that the strip leaves out.
    let total: Int
    let start: Duration
    let backup: Backup
    /// Arms the session from the strip after a Dry Run press. Nil hides the button.
    let onArm: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            let header = ModeText.sentHeader(outputs, total: total)
            HStack(spacing: 8) {
                Text(verbatim: header).font(.caption.bold()).foregroundStyle(.secondary)
                if let onArm, header.hasPrefix("Dry Run") {
                    Button("Arm", action: onArm).controlSize(.small).help(ModeText.armHelp)
                }
            }
            if outputs.isEmpty {
                Text("Nothing sent. Press a switch or move the pedal.").font(.caption).foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(outputs.enumerated()), id: \.offset) { index, entry in
                            if case .output(let bytes, let ports, let pointer, let live) = entry.event {
                                HStack(spacing: 16) {
                                    Text(verbatim: "+\(Int((entry.time - start) / .milliseconds(1))) ms")
                                        .frame(width: 72, alignment: .trailing)
                                    Text(verbatim: live ? "sent" : "dry").foregroundStyle(live ? Color.green : Color.secondary)
                                        .frame(width: 36, alignment: .leading)
                                    Text(verbatim: Self.ports(ports)).frame(width: 80, alignment: .leading)
                                    Text(verbatim: MidiText.describe(bytes)).frame(width: 220, alignment: .leading)
                                    Text(verbatim: backup.source(of: pointer) ?? pointer).lineLimit(1).truncationMode(.middle)
                                }
                                .font(.system(size: 12, design: .monospaced))
                                .id(index)
                            }
                        }
                    }
                }
                // A long group follows its newest output, for example during a pedal sweep.
                .onChange(of: outputs.count) { proxy.scrollTo(outputs.count - 1, anchor: .bottom) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
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

/// The line between the panel and the Sent pane. A drag sets the pane height, which the app remembers.
private struct PaneDivider: View {
    let preferences: Preferences
    /// The pane height when the drag began.
    private let dragStart = State(initialValue: Int?.none)

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onHover { inside in inside ? NSCursor.resizeUpDown.push() : NSCursor.pop() }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let base = dragStart.wrappedValue ?? preferences.sentHeight
                        dragStart.wrappedValue = base
                        let range = Preferences.sentHeightRange
                        preferences.sentHeight = min(max(base - Int(drag.translation.height), range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in dragStart.wrappedValue = nil })
    }
}

/// A vertical pedal, 0 at the bottom and 127 at the top.
private struct PedalSlider: View {
    @Binding var value: Int
    let height: CGFloat

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
        .frame(width: 32, height: height)
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
