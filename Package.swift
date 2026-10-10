// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MC6Virtual",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MC6Core"),
        .target(name: "MC6MIDI", dependencies: ["MC6Core"]),
        .executableTarget(name: "MC6App", dependencies: ["MC6Core", "MC6MIDI"]),
        .testTarget(name: "MC6CoreTests", dependencies: ["MC6Core"]),
        .testTarget(name: "MC6MIDITests", dependencies: ["MC6MIDI"]),
    ]
)
