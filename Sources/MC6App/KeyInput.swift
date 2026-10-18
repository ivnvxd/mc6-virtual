import AppKit
import MC6Core

/// The keys of `KeyCommand` by physical key code, only while the main window is key and no text field, sheet or
/// modal panel has focus. Only the pedal keys repeat. When a window stops being key, held buttons get a focus loss.
@MainActor
final class KeyInput {
    private var monitor: Any?
    private var observer: (any NSObjectProtocol)?

    init(model: AppModel) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak model] event in
            let keyCode = event.keyCode
            let isDown = event.type == .keyDown
            let isRepeat = event.isARepeat
            let modifiers = event.modifierFlags
            let handled = MainActor.assumeIsolated {
                // A key-up ends a hold whatever the modifiers are now.
                let command = KeyCommand(keyCode: keyCode, modifiers: isDown ? Self.modifiers(modifiers) : [])
                guard let model, let command else { return false }
                if case .footswitch(let button) = command {
                    guard isDown else {
                        guard model.held[button] == .keyboard else { return false }
                        model.up(button, source: .keyboard)
                        return true
                    }
                    guard Self.acceptsKeys(model) else { return false }
                    if !isRepeat { model.down(button, source: .keyboard) }
                    return true
                }
                guard Self.acceptsKeys(model) else { return false }
                // The up of a function key and a held key that does not repeat do nothing, but stay with the app.
                guard isDown, !isRepeat || command.repeats else { return true }
                switch command {
                case .navigate(let step): model.session.navigate(step)
                case .engage(let preset): model.session.engage(preset: preset)
                case .pedal(let up, let fine): model.movePedal(up: up, fine: fine)
                case .footswitch: break
                }
                return true
            }
            return handled ? nil : event
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
        ) { [weak model] _ in
            MainActor.assumeIsolated { model?.focusLost() }
        }
    }

    /// The modifiers that `KeyCommand` reads. Shortcuts such as Command-Q stay with the menus.
    private static func modifiers(_ flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var modifiers: KeyModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }

    /// Keys belong to the main window: not to the Log or Settings window, a sheet, a modal panel or a text field.
    private static func acceptsKeys(_ model: AppModel) -> Bool {
        guard NSApp.modalWindow == nil, let window = model.mainWindow, window.isKeyWindow, window.attachedSheet == nil
        else { return false }
        return !(window.firstResponder is NSText)
    }
}
