import AppKit

/// A native menu at the pointer, for a control that SwiftUI draws from shapes. A SwiftUI `Menu` does not scale
/// with `ZoomedPanel`, and `ImageRenderer` does not draw it.
@MainActor
final class PopUpMenu: NSObject {
    struct Item {
        let title: String
        var enabled = true
        let action: () -> Void
    }

    private var actions: [() -> Void] = []

    /// Shows the items and waits until the user picks one or closes the menu. Nil is a separator.
    static func show(_ items: [Item?]) {
        let holder = PopUpMenu()
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in items {
            guard let item else {
                menu.addItem(.separator())
                continue
            }
            let entry = NSMenuItem(title: item.title, action: #selector(run(_:)), keyEquivalent: "")
            entry.target = holder
            entry.tag = holder.actions.count
            entry.isEnabled = item.enabled
            holder.actions.append(item.action)
            menu.addItem(entry)
        }
        // With no view, the point is in screen coordinates. The call returns after the menu closed, so `holder` lives long enough.
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func run(_ sender: NSMenuItem) {
        actions[sender.tag]()
    }
}
