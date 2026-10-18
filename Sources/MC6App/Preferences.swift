import Foundation
import MC6Core
import MC6MIDI
import Observation

/// Where the switch letters come from (plan v2, Settings table).
enum LetterChoice: String, CaseIterable {
    case fromBackup, on, off
}

/// The Settings window values and the recent files, stored in UserDefaults (V11).
/// Every change calls `onChange`, so the app applies it at once.
@MainActor @Observable
final class Preferences {
    static let longPressRange = 300...1500
    static let doubleTapRange = 150...600
    static let pedalStepRange = 1...32
    static let pedalFineStepRange = 1...8
    static let brightnessRange = 30...100
    static let logLimitRange = 1_000...100_000

    /// False uses the backup's long-press time.
    var customLongPress: Bool { didSet { save() } }
    var longPressMs: Int { didSet { save() } }
    var doubleTapMs: Int { didSet { save() } }
    var pedalStep: Int { didSet { save() } }
    var pedalFineStep: Int { didSet { save() } }
    /// False uses the backup's `brightnessValue`.
    var customBrightness: Bool { didSet { save() } }
    var brightnessPercent: Int { didSet { save() } }
    var letters: LetterChoice { didSet { save() } }
    var logLimit: Int { didSet { save() } }
    /// Port 1 and port 2. They apply at the next launch.
    var portNames: [String] { didSet { save() } }
    var openLastAtLaunch: Bool { didSet { save() } }
    var keepOnTop: Bool { didSet { save() } }
    var recent: RecentFiles { didSet { save() } }

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func int(_ key: String, _ fallback: Int, _ range: ClosedRange<Int>) -> Int {
            let value = defaults.object(forKey: key) as? Int ?? fallback
            return min(max(value, range.lowerBound), range.upperBound)
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        customLongPress = bool("customLongPress", false)
        longPressMs = int("longPressMs", 700, Self.longPressRange)
        doubleTapMs = int("doubleTapMs", Int(GestureTiming.defaultDoubleTapWindow / .milliseconds(1)), Self.doubleTapRange)
        pedalStep = int("pedalStep", 8, Self.pedalStepRange)
        pedalFineStep = int("pedalFineStep", 1, Self.pedalFineStepRange)
        customBrightness = bool("customBrightness", false)
        brightnessPercent = int("brightnessPercent", 100, Self.brightnessRange)
        letters = defaults.string(forKey: "letters").flatMap(LetterChoice.init) ?? .fromBackup
        logLimit = int("logLimit", Session.defaultLogLimit, Self.logLimitRange)
        // A name left empty in Settings falls back to its default.
        let names = defaults.stringArray(forKey: "portNames") ?? []
        portNames = names.count == 2
            ? zip(names, VirtualPorts.defaultNames).map { $0.trimmingCharacters(in: .whitespaces).isEmpty ? $1 : $0 }
            : VirtualPorts.defaultNames
        openLastAtLaunch = bool("openLastAtLaunch", true)
        keepOnTop = bool("keepOnTop", false)
        recent = RecentFiles(paths: defaults.stringArray(forKey: "recentFiles") ?? [])
    }

    /// The gesture times for the session (V08).
    var timing: GestureTiming {
        GestureTiming(
            longPress: customLongPress ? .milliseconds(longPressMs) : nil,
            doubleTapWindow: .milliseconds(doubleTapMs))
    }

    /// The screen brightness, 0.3 to 1.
    func brightness(_ backup: Backup?) -> Double {
        let percent = customBrightness ? brightnessPercent : 30 + 10 * (backup?.brightnessValue ?? 7)
        return Double(percent) / 100
    }

    func showLetters(_ backup: Backup?) -> Bool {
        switch letters {
        case .fromBackup: backup?.showPresetLabels ?? false
        case .on: true
        case .off: false
        }
    }

    private func save() {
        defaults.set(customLongPress, forKey: "customLongPress")
        defaults.set(longPressMs, forKey: "longPressMs")
        defaults.set(doubleTapMs, forKey: "doubleTapMs")
        defaults.set(pedalStep, forKey: "pedalStep")
        defaults.set(pedalFineStep, forKey: "pedalFineStep")
        defaults.set(customBrightness, forKey: "customBrightness")
        defaults.set(brightnessPercent, forKey: "brightnessPercent")
        defaults.set(letters.rawValue, forKey: "letters")
        defaults.set(logLimit, forKey: "logLimit")
        defaults.set(portNames, forKey: "portNames")
        defaults.set(openLastAtLaunch, forKey: "openLastAtLaunch")
        defaults.set(keepOnTop, forKey: "keepOnTop")
        defaults.set(recent.paths, forKey: "recentFiles")
        onChange?()
    }
}
