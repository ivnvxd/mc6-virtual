import AppKit
import MC6Core

/// Keyboard footswitches by physical key code (`Footswitch.init(keyCode:)`), only while the main window
/// is key and no text field, sheet or modal panel has focus. Key repeat is ignored. When a window stops
/// being key, held buttons get a focus loss.
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
                guard let model, let button = Footswitch(keyCode: keyCode) else { return false }
                guard isDown else {
                    guard model.held[button] == .keyboard else { return false }
                    model.up(button, source: .keyboard)
                    return true
                }
                // Leave shortcuts such as Command-Q to the menu.
                guard modifiers.isDisjoint(with: [.command, .control, .option]), Self.acceptsKeys else { return false }
                if !isRepeat { model.down(button, source: .keyboard) }
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

    private static var acceptsKeys: Bool {
        guard NSApp.modalWindow == nil, let window = NSApp.keyWindow, !window.isSheet, window.attachedSheet == nil
        else { return false }
        return !(window.firstResponder is NSText)
    }
}
