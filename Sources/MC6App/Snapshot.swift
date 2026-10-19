import AppKit
import MC6Core
import SwiftUI

/// Renders the panel of a backup to a PNG and quits, so an agent can look at it without the Screen Recording
/// permission. It creates no ports, no key input and no `Preferences`.
///
/// `MC6_SNAPSHOT` is the output path and `MC6_BACKUP` the backup. `MC6_SNAPSHOT_STATE` holds optional
/// comma-separated values: `bank=2,page=1,pos2=8,last=1,exp=64,bpm=120,letters=1,brightness=50`.
@MainActor
enum Snapshot {
    /// Runs a snapshot if the environment asks for one. Returns the exit code, or nil to start the app.
    static func runIfRequested() -> Int32? {
        let environment = ProcessInfo.processInfo.environment
        guard let output = environment["MC6_SNAPSHOT"] else { return nil }
        do {
            let backup = try Importer.load(try Data(contentsOf: URL(fileURLWithPath: environment["MC6_BACKUP"] ?? "")))
            try render(backup, values: parse(environment["MC6_SNAPSHOT_STATE"] ?? ""), to: URL(fileURLWithPath: output))
            return 0
        } catch let error as ImportError {
            FileHandle.standardError.write(Data("snapshot: the backup did not load: \(error.problems)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("snapshot: \(error)\n".utf8))
        }
        return 1
    }

    private static func parse(_ text: String) -> [(key: String, value: Int)] {
        text.split(separator: ",").compactMap { pair in
            let parts = pair.split(separator: "=")
            guard parts.count == 2, let value = Int(parts[1]) else { return nil }
            return (String(parts[0]), value)
        }
    }

    private static func render(_ backup: Backup, values: [(key: String, value: Int)], to url: URL) throws {
        var state = RuntimeState(backup: backup)
        var lastPressed: PresetAddress?
        var expression = 0
        var bpm: Int?
        var letters = backup.showPresetLabels
        var brightness = 30 + 10 * backup.brightnessValue
        for (key, value) in values {
            switch key {
            case "bank": state.bank = value
            case "page": state.page = value
            case "pos2": state[position: PresetAddress(bank: state.bank, preset: value)] = .two
            case "last": lastPressed = PresetAddress(bank: state.bank, preset: value)
            case "exp": expression = value
            case "bpm": bpm = value
            case "letters": letters = value != 0
            case "brightness": brightness = value
            default: throw SnapshotError(text: "unknown state key \(key)")
            }
        }
        let panel = PanelView(
            screens: ScreenDisplay.screens(
                state, in: backup, lastPressed: lastPressed, expression: expression, bpm: bpm, showLetters: letters),
            brightness: Double(brightness) / 100, held: [], longPress: .milliseconds(700))
            .padding(24)
            .background(Color(white: 0.93))
        let renderer = ImageRenderer(content: panel)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { throw SnapshotError(text: "rendering failed") }
        try png.write(to: url)
    }

    struct SnapshotError: Error, CustomStringConvertible {
        let text: String
        var description: String { text }
    }
}
