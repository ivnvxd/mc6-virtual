import MC6Core
import SwiftUI

/// The menu bar (plan v2, Shortcuts table). The key functions show their key in the title but have no menu
/// shortcut, so they act only through `KeyInput`, which listens only to the main window.
struct AppCommands: Commands {
    let model: AppModel

    private var session: Session { model.session }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…") { model.openPanel() }.keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(model.preferences.recent.paths, id: \.self) { path in
                    Button(URL(fileURLWithPath: path).lastPathComponent) { model.open(URL(fileURLWithPath: path)) }
                }
                Divider()
                Button("Clear Menu") { model.preferences.recent.clear() }
                    .disabled(model.preferences.recent.paths.isEmpty)
            }
            Button("Reload Backup") { model.reload() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.backupURL == nil)
        }
        CommandGroup(replacing: .importExport) {
            Button("Export Log…") { model.exportLog() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(session.log.isEmpty)
        }
        CommandMenu("Controls") {
            Button(session.mode == .live ? "Disarm" : "Arm") {
                session.mode == .live ? session.disarm() : session.arm()
            }
            .keyboardShortcut("l")
            .disabled(session.backup == nil || model.portError != nil)
            Button("Reset…") { model.confirmReset = true }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(session.backup == nil)
            Divider()
            ForEach(Self.steps, id: \.title) { step in
                Button("\(step.title)    \(KeyCommand.navigate(step.step).label)") { session.navigate(step.step) }
                    .disabled(session.backup == nil)
            }
        }
    }

    private static let steps: [(title: String, step: NavigationStep)] = [
        ("Bank Down", .bankDown), ("Bank Up", .bankUp), ("Page Down", .pageDown), ("Page Up", .pageUp),
    ]
}
