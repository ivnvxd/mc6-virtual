import AppKit
import MC6Core
import MC6MIDI
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct MC6VirtualApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    private let model = AppModel()

    var body: some Scene {
        Window("MC6 Virtual", id: "main") {
            MainWindow(model: model)
        }
        .commands { AppCommands(model: model) }
        Window("Log", id: "log") {
            LogView(model: model)
        }
        .keyboardShortcut("l", modifiers: [.command, .option])
        Settings {
            SettingsView(preferences: model.preferences, backup: model.session.backup)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Quit with the window, so no hidden instance keeps the virtual ports.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// The app state around the session: the virtual ports, the held buttons for the hold ring, the pedal value,
/// the settings and the open file.
@MainActor @Observable
final class AppModel {
    let session: Session
    let preferences: Preferences
    /// The file of the loaded backup, for Reload.
    private(set) var backupURL: URL?
    /// Why the virtual ports could not be created. Arm stays off.
    let portError: String?
    /// The buttons held now, with the source that holds each. Only that source ends the hold.
    private(set) var held: [Footswitch: InputSource] = [:]
    /// Expression input 1, 0 to 127. The session does not store the pedal value.
    var expression = 0 {
        didSet { if expression != oldValue { session.moveExpression(input: 0, to: expression) } }
    }
    /// A log file that could not be written. A backup that could not be read is in `session.importProblems`.
    var fileError: String?
    /// The Reset confirmation is showing.
    var confirmReset = false
    @ObservationIgnored private var keys: KeyInput?
    /// The main window. Keys work only while it is key, and closing it quits the app.
    @ObservationIgnored private(set) weak var mainWindow: NSWindow?
    @ObservationIgnored private var closeObserver: (any NSObjectProtocol)?

    init() {
        preferences = Preferences()
        let output: any MidiSink
        do {
            output = try VirtualPorts(names: preferences.portNames)
            portError = nil
        } catch {
            output = NoPorts(error: error)
            portError = "\(error)"
        }
        session = Session(scheduler: DispatchScheduler(), output: output)
        keys = KeyInput(model: self)
        applyPreferences()
        preferences.onChange = { [weak self] in self?.applyPreferences() }
        // V09, V11: open the last backup, always in Dry Run.
        if preferences.openLastAtLaunch, let path = preferences.recent.paths.first {
            open(URL(fileURLWithPath: path))
        }
    }

    /// Takes the main window once SwiftUI has made it.
    func attach(_ window: NSWindow) {
        guard mainWindow !== window else { return }
        mainWindow = window
        // The ports must not stay taken by a hidden app, also while the Log window is open.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
        applyPreferences()
    }

    private func applyPreferences() {
        session.timing = preferences.timing
        session.logLimit = preferences.logLimit
        mainWindow?.level = preferences.keepOnTop ? .floating : .normal
    }

    /// Opens a backup file. A backup that loads goes to the top of the recent files.
    /// A file that fails stays where it is in the list, so a missing drive can come back.
    func open(_ url: URL) {
        session.load(contentsOf: url)
        fileError = nil
        guard session.importProblems.isEmpty else { return }
        backupURL = url
        preferences.recent.opened(url.path)
    }

    /// Reads the open backup file again (V09: in Dry Run).
    func reload() {
        if let backupURL { open(backupURL) }
    }

    /// Moves Expression 1 by the arrow step, or by the fine step.
    func movePedal(up: Bool, fine: Bool) {
        let step = fine ? preferences.pedalFineStep : preferences.pedalStep
        expression = min(127, max(0, expression + (up ? step : -step)))
    }

    func down(_ button: Footswitch, source: InputSource) {
        guard held[button] == nil else { return }
        held[button] = source
        session.down(button, source: source)
    }

    func up(_ button: Footswitch, source: InputSource) {
        guard held[button] == source else { return }
        held[button] = nil
        session.up(button, source: source)
    }

    func focusLost() {
        held = [:]
        session.focusLost()
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // A file that cannot be read is a failed import: the session lists it as the one problem.
        open(url)
    }

    func exportLog() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "jsonl") ?? .json]
        panel.nameFieldStringValue = "MC6 Virtual log.jsonl"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try session.exportLog().write(to: url)
            fileError = nil
        } catch {
            fileError = "Could not write \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}

/// Stands in for the virtual ports when they could not be created: every send fails.
private final class NoPorts: MidiSink {
    let error: any Error

    init(error: any Error) { self.error = error }

    func send(_ bytes: [UInt8], to ports: Ports) throws { throw error }
}
