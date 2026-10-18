import AppKit

// Snapshot mode renders the panel to a PNG and quits before the app starts.
if let status = Snapshot.runIfRequested() { exit(status) }

// A SwiftPM executable is not a bundle by default, so ask for a Dock icon and a menu bar.
NSApplication.shared.setActivationPolicy(.regular)
MC6VirtualApp.main()
