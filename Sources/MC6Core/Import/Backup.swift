import Foundation

/// An imported MC6 Pro `allBanks` backup. The original bytes stay unchanged; the rest is decoded from them.
public struct Backup: Sendable {
    /// The file exactly as read. The app never writes it back.
    public let original: Data
    /// All banks, indexed by bank ID.
    public let banks: [Bank]
    /// Banks reachable from bank 0 through Bank Jump and Engage. Only these can run.
    public let productionBanks: Set<Int>
    /// The editor option index; the long-press time is `100 + 50 * index` ms.
    public let longPressTime: Int
    /// The editor option index 0 to 7; the screen brightness is `30 + 10 * index` percent.
    public var brightnessValue = 7
    /// The switch letters show on the screens.
    public var showPresetLabels = false
    /// `sendToPort` of MIDI channels 1 to 16, at index `channel - 1`.
    public let sendToPort: [Int]
    /// Inert bytes and skipped data that the profile allows, with their pointers.
    public let notes: [ImportNote]

    public var counts: MessageCounts {
        var counts = MessageCounts(total: 0, production: 0, switchMessages: 0, expression: 0)
        for bank in banks {
            let switches = bank.presets.reduce(0) { $0 + $1.messages.count }
            let expressions = bank.expressions.reduce(0) { $0 + $1.messages.count }
            counts.total += switches + expressions
            counts.switchMessages += switches
            counts.expression += expressions
            if productionBanks.contains(bank.number) { counts.production += switches + expressions }
        }
        return counts
    }
}

public struct MessageCounts: Sendable, Equatable {
    public var total: Int
    public var production: Int
    public var switchMessages: Int
    public var expression: Int
}

public struct Bank: Sendable {
    public let number: Int
    public let name: String
    /// 0 means no limit (four pages); 1 to 3 limit paging. The importer rejects other values.
    public let pageLimit: Int
    /// Switch presets A to X.
    public let presets: [Preset]
    /// Expression presets for inputs 1 to 4.
    public let expressions: [Preset]
    /// The bank description of the editor.
    public var description = ""
    /// False draws the bank's presets white on black.
    public var colorEnabled = true
}

public struct Preset: Sendable {
    public let shortName: String
    public let toggleName: String
    public let toMsgScroll: Bool
    /// Only the non-empty slots (`t != 0`), in slot order.
    public let messages: [Message]
    /// The name the center band shows after a press. Can be empty.
    public var longName = ""
    /// The palette colors at Position 1.
    public var colors = PresetColors()
    /// The palette colors at Position 2.
    public var toggleColors = PresetColors()
}

/// The palette indexes (0 to 127) of one preset position: the strip on the screen edge, the name and its background.
public struct PresetColors: Sendable, Equatable {
    public var strip = 0
    public var text = 7
    public var background = 0

    public init(strip: Int = 0, text: Int = 7, background: Int = 0) {
        self.strip = strip
        self.text = text
        self.background = background
    }
}

public struct Message: Sendable, Equatable {
    public let slot: Int
    /// Switch action 1 to 9; 0 for expression messages.
    public let action: Int
    public let gate: Gate
    public let command: Command
    /// JSON Pointer of the source message in the backup.
    public let pointer: String
}

/// The switch action numbers of `Message.action` (spec 6.2). Expression messages use 0.
public enum SwitchAction {
    public static let press = 1
    public static let release = 2
    public static let longPress = 3
    public static let longPressRelease = 4
    public static let doubleTap = 5
    public static let doubleTapRelease = 6
    public static let longDoubleTap = 7
    public static let longDoubleTapRelease = 8
    public static let releaseAll = 9
    /// Every switch action.
    public static let all = 1...9
    /// The actions of a second tap: Double Tap to Long Double Tap Release.
    public static let secondTap = 5...8
}

/// The `tg` position filter of a message.
public enum Gate: Sendable, Equatable {
    case position1, position2, both
}

/// A note about a value the v1 profile accepts but does not act on.
public struct ImportNote: Sendable, Equatable {
    public let pointer: String
    public let text: String
}

/// One reason a backup does not load.
public struct ImportProblem: Error, Sendable, Equatable {
    public let pointer: String
    public let reason: String
}

/// A backup that does not load, with every reason found.
public struct ImportError: Error, Sendable {
    public let problems: [ImportProblem]
}

// MARK: - Raw JSON shape (spec section 4.1). Unknown keys stay only in `Backup.original`.

struct RawFile: Decodable {
    let schemaVersion: Int
    let dumpType: String
    let deviceModel: Int
    let data: RawData
}

struct RawData: Decodable {
    let bankArray: [RawBank]
    let settings: Wrapped<RawSettings>

    enum CodingKeys: String, CodingKey {
        case bankArray
        case settings = "controller_settings"
    }
}

/// The `{"type": ..., "data": ...}` envelope used throughout the settings. The importer checks `type`.
struct Wrapped<Value: Decodable>: Decodable {
    let type: String
    let data: Value
}

struct RawBank: Decodable {
    let bankNumber: Int
    let bankName: String
    let bankDescription: String
    let isColorEnabled: Bool
    let bankClearToggle: Bool
    let pageLimit: Int
    let bankMsgArray: [RawMessage]
    let presetArray: [RawPreset]
    let expPresetArray: [RawPreset]
}

struct RawPreset: Decodable {
    let presetNum: Int
    let bankNum: Int
    let isExp: Bool
    let shortName: String
    let toggleName: String
    let longName: String
    let ledColor: Int
    let ledToggleColor: Int
    let nameColor: Int
    let nameToggleColor: Int
    let backgroundColor: Int
    let toggleBackgroundColor: Int
    let toToggle: Bool
    let toMsgScroll: Bool
    let toggleGroup: Int
    let msgArray: [RawMessage]
}

struct RawMessage: Decodable {
    let data: [Int]
    let m: Int
    let c: Int
    let t: Int
    let a: Int
    let tg: Int
}

struct RawSettings: Decodable {
    let general: Wrapped<RawGeneral>
    let midiChannels: Wrapped<[Wrapped<RawChannel>]>
    let midiEvents: Wrapped<[Wrapped<RawEvent>]>

    enum CodingKeys: String, CodingKey {
        case general = "controller_settings"
        case midiChannels = "midi_channels"
        case midiEvents = "midi_events"
    }
}

struct RawGeneral: Decodable {
    let savePresetToggle: Bool
    let longPressTime: Int
    let midiSendDelay: Int
    let bankChangeDelayTime: Int
    let midiClockOutputPorts: Int
    let loadLastBankOnStartup: Bool
    let numMidiCable: Int
    let brightnessValue: Int
    let showPresetLabels: Bool
}

struct RawChannel: Decodable {
    let channel: Int
    let sendToPort: Int
    let remap: Int
    let isMidiChannelOffset: Bool
    let engageEnabled: Bool
    let bypassEnabled: Bool
    let dataAttributes: [[Int]]
}

/// A MIDI event converter. A non-zero source or target type enables it.
struct RawEvent: Decodable {
    let typeFrom: Int
    let typeTo: Int
}
