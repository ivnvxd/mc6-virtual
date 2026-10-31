import AppKit
import MC6Core
import SwiftUI

/// Renders the panel of a backup to a PNG and quits, so an agent can look at it without the Screen Recording
/// permission. It creates no ports, no key input and no `Preferences`.
///
/// `MC6_SNAPSHOT` is the output path and `MC6_BACKUP` the backup. `MC6_SNAPSHOT_STATE` holds optional
/// comma-separated values: `bank=2,page=1,pos2=8,last=1,exp=64,bpm=120,letters=1,brightness=50,held=9,activity=1,zoom=150,transparent=1`.
/// `held` is a bit mask by `Footswitch.rawValue` (A is 1, D is 8). `activity=1` draws the activity light bright.
/// `transparent=1` leaves the area around the panel transparent, for example for a README image.
/// `mode=0`, `1` or `2` is Dry Run, Live or Error, and `modelabel=1` prints the mode next to the light, as in compact mode.
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
            FileHandle.standardError.write(Data("snapshot: \(ImportText.copy(error.problems))".utf8))
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
        var held: Set<Footswitch> = []
        var flash = false
        var zoom = 100
        var transparent = false
        var mode = Session.Mode.dryRun
        var modeLabel = false
        func check(_ range: Range<Int>, _ key: String, _ value: Int) throws {
            guard range.contains(value) else {
                throw SnapshotError(text: "\(key)=\(value) is outside \(range.lowerBound) to \(range.upperBound - 1)")
            }
        }
        // The bank and the page come first, because pos2 and last name presets of the shown bank.
        let first = ["bank": 0, "page": 1]
        let ordered = values.enumerated()
            .sorted { (first[$0.element.key] ?? 2, $0.offset) < (first[$1.element.key] ?? 2, $1.offset) }
            .map(\.element)
        for (key, value) in ordered {
            switch key {
            case "bank":
                try check(backup.banks.indices, key, value)
                state.bank = value
            case "page":
                try check(0..<backup.banks[state.bank].pageCount, key, value)
                state.page = value
            case "pos2":
                try check(backup.banks[state.bank].presets.indices, key, value)
                state[position: PresetAddress(bank: state.bank, preset: value)] = .two
            case "last":
                try check(backup.banks[state.bank].presets.indices, key, value)
                lastPressed = PresetAddress(bank: state.bank, preset: value)
            case "exp": expression = value
            case "bpm": bpm = value
            case "letters": letters = value != 0
            case "brightness": brightness = value
            case "held": held = Set(Footswitch.allCases.filter { value & 1 << $0.rawValue != 0 })
            case "activity": flash = value != 0
            case "zoom": zoom = value
            case "transparent": transparent = value != 0
            case "mode": mode = [.dryRun, .live, .error(.budgetLimit(pointer: ""))][min(max(value, 0), 2)]
            case "modelabel": modeLabel = value != 0
            default: throw SnapshotError(text: "unknown state key \(key)")
            }
        }
        let panel = ZoomedPanel(zoom: Double(zoom) / 100) {
            PanelView(
            screens: ScreenDisplay.screens(
                state, in: backup, lastPressed: lastPressed, expression: expression, bpm: bpm, showLetters: letters),
            brightness: Double(brightness) / 100, held: held, longPress: .milliseconds(700), mode: ActivityMode(mode),
            modeLabel: modeLabel ? ModeText.label(mode) : nil, flash: flash,
            page: state.page, pageCount: backup.banks[state.bank].pageCount)
        }
            .padding(24)
            .background(transparent ? Color.clear : Color(white: 0.93))
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
