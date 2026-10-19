import AppKit
import MC6Core

/// The keys of `KeyCommand` by physical key code, only while the main window is key and no text field, sheet or
/// modal panel has focus. No key acts on the OS key repeat: a held pedal key sweeps on a timer (V16).
/// When a window stops being key, held buttons get a focus loss.
@MainActor
final class KeyInput {
    private var monitor: Any?
    private var observer: (any NSObjectProtocol)?

    init(model: AppModel) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .scrollWheel]) { [weak model] event in
            if event.type == .scrollWheel { return Self.scroll(event, model: model) ? nil : event }
            let keyCode = event.keyCode
            let isDown = event.type == .keyDown
            let isRepeat = event.isARepeat
            let modifiers = event.modifierFlags
            let handled = MainActor.assumeIsolated {
                guard let model else { return false }
                if model.recording != nil, isDown {
                    return Self.record(keyCode, Self.modifiers(modifiers), isRepeat: isRepeat, model: model)
                }
                // A key-up ends a hold whatever the modifiers are now.
                let map = model.preferences.keys
                let command = KeyCommand(keyCode: keyCode, modifiers: isDown ? Self.modifiers(modifiers) : [], map: map)
                guard let command else { return false }
                if case .pedal(let up, let fine) = command {
                    // The up of a pedal key ends its sweep, whatever has focus now.
                    guard isDown else {
                        model.stopPedal(up: up)
                        return true
                    }
                    guard Self.acceptsKeys(model) else { return false }
                    if !isRepeat { model.startPedal(up: up, fine: fine) }
                    return true
                }
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
                // The up of a function key and a repeat of a held key do nothing, but stay with the app.
                guard isDown, !isRepeat else { return true }
                switch command {
                case .navigate(let step): model.session.navigate(step)
                case .engage(let preset): model.session.engage(preset: preset)
                case .pedal, .footswitch: break
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

    /// V17: a scroll over the pedal of the main window moves the pedal, also while another app is in front.
    /// Returns whether the app keeps the event.
    private static func scroll(_ event: NSEvent, model: AppModel?) -> Bool {
        let deltaY = Double(event.scrollingDeltaY)
        let precise = event.hasPreciseScrollingDeltas
        let inverted = event.isDirectionInvertedFromDevice
        let window = event.window
        return MainActor.assumeIsolated {
            guard let model, model.pedalHovered, NSApp.modalWindow == nil, let main = model.mainWindow, window === main
            else { return false }
            model.scrollPedal(deltaY: deltaY, precise: precise, inverted: inverted)
            return true
        }
    }

    /// V15: the next key down goes to the function that Settings records. This runs before the key map and the
    /// focus check, because the Settings window is key while it records. Escape cancels. A key with Command or
    /// Control ends the recording and goes on to the menus, so Command-Q still quits. Option stays for the fine
    /// pedal step, so a key with Option does not record. Shift is ignored. Returns whether the app keeps the event.
    private static func record(_ keyCode: UInt16, _ modifiers: KeyModifiers, isRepeat: Bool, model: AppModel) -> Bool {
        guard let function = model.recording, !isRepeat else { return true }
        if !modifiers.isDisjoint(with: [.command, .control]) {
            model.recording = nil
            return false
        }
        if keyCode == escape {
            model.recording = nil
        } else if modifiers.contains(.option) {
            model.recordingNote = "Option is for the fine pedal step. Press the key without Option."
        } else {
            model.preferences.keys.assign(keyCode, to: function)
            model.recording = nil
        }
        return true
    }

    /// `kVK_Escape`.
    private static let escape: UInt16 = 0x35

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
