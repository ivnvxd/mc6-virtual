import MC6Core
import SwiftUI

/// The main window: the toolbar, the bank sidebar, banners for what blocks playing, the panel with the pedal,
/// and the message pane under them. Compact mode shows only the banners and the panel.
struct MainWindow: View {
    @Bindable var model: AppModel

    private var session: Session { model.session }
    private var preferences: Preferences { model.preferences }
    /// The notes popover of the skipped line. Plain storage, because the `@State` macro is not available.
    private let showNotes = State(initialValue: false)
    /// The size of the panel at zoom 1. The full layout scales the panel to fit its space.
    private let panelSize = State(initialValue: CGSize.zero)
    /// The height that the Sent pane has now. In a short window it is less than `Preferences.sentHeight`.
    private let paneHeight = State(initialValue: CGFloat.zero)

    /// Compact mode shows only the banners and the panel, and only while a backup is loaded.
    private var compact: Bool { preferences.compact && session.backup != nil }

    var body: some View {
        content
            .modifier(WindowSize(compact: compact))
            .toolbar { toolbar }
            .toolbar(compact ? .hidden : .automatic, for: .windowToolbar)
            // macOS 27 starts the toolbar background 5 pt left of the sidebar line, which shows as a step at the title.
            // Without the background the toolbar has the color of the content, so no edge shows.
            .toolbarBackground(.hidden, for: .windowToolbar)
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
                                .layoutPriority(2)
                        }
                        fittedPanel(backup, engine, longPress, state: engine.state)
                        PaneDivider(preferences: preferences, shown: paneHeight.wrappedValue)
                        // The pane takes its height first, but never the least height of the panel.
                        MessagePane(
                            session: session, backup: backup, preferences: preferences,
                            onArm: session.mode == .live || model.portError != nil ? nil : { session.arm() },
                            onExport: { model.exportLog() })
                            .frame(minHeight: CGFloat(Preferences.sentHeightRange.lowerBound), maxHeight: CGFloat(preferences.sentHeight))
                            .onGeometryChange(for: CGFloat.self, of: \.size.height) { paneHeight.wrappedValue = $0 }
                            .layoutPriority(1)
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
    private func fittedPanel(_ backup: Backup, _ engine: Engine, _ longPress: Duration, state: RuntimeState) -> some View {
        GeometryReader { geometry in
            let scale = fitScale(geometry.size)
            HStack(spacing: Self.pedalGap * scale) {
                panel(backup, engine, longPress, zoom: scale)
                ZoomedPanel(zoom: scale) {
                    PedalView(
                        value: Binding(get: { model.expression }, set: { model.setPedal($0) }),
                        height: naturalHeight,
                        upKey: KeyCommand.pedal(up: true, fine: false).label(in: preferences.keys),
                        downKey: KeyCommand.pedal(up: false, fine: false).label(in: preferences.keys),
                        targets: ExpressionDisplay.selected(input: 0, state, in: backup),
                        onHover: { model.pedalHovered = $0 })
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .padding(Self.panelPadding)
        .frame(minHeight: naturalHeight * Self.minScale + 2 * Self.panelPadding)
    }

    private static let pedalGap: CGFloat = 24
    private static let panelPadding: CGFloat = 24
    /// Below this scale the print of the panel is too small to read, so the Sent pane gives way first.
    private static let minScale: CGFloat = 0.7

    /// The height of the panel at zoom 1. A usual value stands in until the panel was measured.
    private var naturalHeight: CGFloat {
        let height = panelSize.wrappedValue.height
        return height > 0 ? height : 400
    }

    /// The largest scale at which the panel and the pedal fit, from 0.7 to 2. It is 1 until the panel was measured.
    private func fitScale(_ space: CGSize) -> CGFloat {
        let natural = panelSize.wrappedValue
        guard natural.width > 0, natural.height > 0 else { return 1 }
        let width = space.width / (natural.width + Self.pedalGap + PedalView.width)
        let height = space.height / natural.height
        return min(max(min(width, height), Self.minScale), 2)
    }

    // MARK: - Toolbar and banners

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.openPanel() } label: { Label("Open…", systemImage: "folder") }
                .labelStyle(.titleAndIcon)
                .help("Open an MC6 Pro All Banks backup.")
            Button { model.confirmReset = true } label: { Label("Reset…", systemImage: "arrow.counterclockwise") }
                .labelStyle(.titleAndIcon)
                .help("Go back to the first bank in Dry Run.")
                .disabled(session.backup == nil)
        }
        ToolbarItem(placement: .primaryAction) { modeStatus }
        ToolbarItem(placement: .primaryAction) { armButton }
    }

    /// The mode as plain text with a dot: a status, not a control. The button next to it changes the mode.
    private var modeStatus: some View {
        let (text, color, help): (String, Color, String) =
            switch session.mode {
            case .dryRun: ("Dry Run", .secondary, "Dry Run: the app shows each message, but sends nothing to the MIDI ports.")
            case .live: ("Live", .green, "Live: each message goes to the MIDI ports.")
            case .error: ("Error", .red, "A press stopped with an error. The app sends nothing until you arm again.")
            }
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(verbatim: text).fontWeight(.medium)
        }
        .padding(.horizontal, 6)
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Mode: \(text)"))
    }

    /// Arm is the one action that lets MIDI out, so it is the prominent button of the window.
    @ViewBuilder private var armButton: some View {
        if session.mode == .live {
            Button("Disarm") { session.disarm() }.help("Go back to Dry Run.")
        } else {
            // Drawn by hand: a toolbar gives every bordered button the same gray look.
            let off = session.backup == nil || model.portError != nil
            Button { session.arm() } label: {
                Text("Arm")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.green.opacity(off ? 0.35 : 0.85)))
            }
            .buttonStyle(.plain)
            .help(ModeText.armHelp)
            .disabled(off)
        }
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

    // MARK: - Problems and empty state

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
            // As high as its lines, up to 160 points.
            textList(session.importProblems.map(ImportText.line))
                .frame(maxHeight: 160)
                .fixedSize(horizontal: false, vertical: true)
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
            Image(systemName: "tray.and.arrow.down").font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
            Text("No backup loaded").font(.title2.weight(.semibold))
            Text("""
                Open an MC6 Pro All Banks backup, the .json file that the Morningstar editor exports.
                You can also drop the file on this window.
                """)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open…") { model.openPanel() }.controlSize(.large).buttonStyle(.borderedProminent)
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

/// The line between the panel and the Sent pane. A drag sets the pane height, which the app remembers.
private struct PaneDivider: View {
    let preferences: Preferences
    /// The height that the pane has now. A drag starts from it, because a short window shows less than the setting.
    let shown: CGFloat
    /// The pane height when the drag began.
    private let dragStart = State(initialValue: Int?.none)

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            // The line sits on the top edge of the pane. The drag area is taller than the line and lies over both sides.
            .overlay {
                Color.clear
                    .frame(height: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in inside ? NSCursor.resizeUpDown.push() : NSCursor.pop() }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { drag in
                                let base = dragStart.wrappedValue ?? (shown > 0 ? Int(shown) : preferences.sentHeight)
                                dragStart.wrappedValue = base
                                let range = Preferences.sentHeightRange
                                preferences.sentHeight = min(max(base - Int(drag.translation.height), range.lowerBound), range.upperBound)
                            }
                            .onEnded { _ in dragStart.wrappedValue = nil })
            }
            .zIndex(1)
    }
}
