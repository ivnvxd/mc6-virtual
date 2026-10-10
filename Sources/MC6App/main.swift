import AppKit

// A SwiftPM executable is not a bundle by default, so ask for a Dock icon and a menu bar.
NSApplication.shared.setActivationPolicy(.regular)
MC6VirtualApp.main()
