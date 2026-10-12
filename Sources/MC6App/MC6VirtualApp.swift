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
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Quit with the window, so no hidden instance keeps the virtual ports.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// The app state around the session: the virtual ports, the held buttons for the hold ring, and the pedal value.
@MainActor @Observable
final class AppModel {
    let session: Session
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

    init() {
        let output: any MidiSink
        do {
            output = try VirtualPorts()
            portError = nil
        } catch {
            output = NoPorts(error: error)
            portError = "\(error)"
        }
        session = Session(scheduler: DispatchScheduler(), output: output)
        keys = KeyInput(model: self)
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

    func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // A file that cannot be read is a failed import: the session lists it as the one problem.
        session.load(contentsOf: url)
        fileError = nil
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
