import Foundation

/// Reads an MC6 Pro `allBanks` backup and checks it against the v1 profile.
/// A backup outside the profile does not load; the error lists every reason with its JSON Pointer.
public enum Importer {
    static let bankCount = 128
    static let presetCount = 24
    static let expressionCount = 4
    static let slotCount = 32
    static let dataCount = 18
    static let channelCount = 16
    static let maxLongPressTime = 28
    /// SEMANTICS.md: 0 is no limit (four pages), 1 to 3 limit paging to that many pages.
    static let maxPageLimit = 3
    /// The two USB device ports that the two virtual ports replace (spec 8.2).
    static let midiCableCount = 2
    /// The MC6 Pro starts in bank 0 when `loadLastBankOnStartup` is off (U12).
    static let startBank = 0

    public static func load(_ data: Data) throws(ImportError) -> Backup {
        let file: RawFile
        do {
            file = try JSONDecoder().decode(RawFile.self, from: data)
        } catch {
            throw ImportError(problems: [problem(error)])
        }

        let shapeProblems = checkShape(file)
        guard shapeProblems.isEmpty else { throw ImportError(problems: shapeProblems) }

        var problems: [ImportProblem] = []
        var notes: [ImportNote] = []
        let banks = file.data.bankArray.enumerated().map { b, raw in
            decodeBank(raw, number: b, problems: &problems, notes: &notes)
        }
        let production = reachableBanks(banks)
        problems += checkSettings(file, production: production)
        if file.data.settings.data.general.data.loadLastBankOnStartup {
            notes.append(ImportNote(
                pointer: "\(generalPointer)/loadLastBankOnStartup",
                text: "loadLastBankOnStartup=true has no effect. The app always starts in bank \(startBank) (U12)."))
        }
        for bank in banks where !production.contains(bank.number) && bank.hasMessages {
            notes.append(ImportNote(
                pointer: "/data/bankArray/\(bank.number)",
                text: "Bank \(bank.number) is not reachable from bank \(startBank). Its messages never run, and its preset flags are not checked."))
        }
        guard problems.isEmpty else { throw ImportError(problems: problems) }
        notes += engageCycles(banks, production: production)

        let settings = file.data.settings.data
        return Backup(
            original: data,
            banks: banks,
            productionBanks: production,
            longPressTime: settings.general.data.longPressTime,
            sendToPort: settings.midiChannels.data.map(\.data.sendToPort),
            notes: notes)
    }

    // MARK: - Structure

    private static func checkShape(_ file: RawFile) -> [ImportProblem] {
        var problems: [ImportProblem] = []
        func expect(_ condition: Bool, _ pointer: @autoclosure () -> String, _ reason: @autoclosure () -> String) {
            if !condition { problems.append(ImportProblem(pointer: pointer(), reason: reason())) }
        }
        expect(file.schemaVersion == 1, "/schemaVersion", "schemaVersion \(file.schemaVersion) is not 1")
        expect(file.dumpType == "allBanks", "/dumpType", "dumpType \(file.dumpType) is not allBanks")
        expect(file.deviceModel == 6, "/deviceModel", "deviceModel \(file.deviceModel) is not the MC6 Pro (6)")

        let banks = file.data.bankArray
        expect(banks.count == bankCount, "/data/bankArray", "\(banks.count) banks instead of \(bankCount)")
        for (b, bank) in banks.enumerated() {
            let bankPointer = "/data/bankArray/\(b)"
            expect(bank.bankNumber == b, "\(bankPointer)/bankNumber", "bankNumber \(bank.bankNumber) is not \(b)")
            expect((0...maxPageLimit).contains(bank.pageLimit), "\(bankPointer)/pageLimit",
                   "pageLimit \(bank.pageLimit) is outside 0 to \(maxPageLimit)")
            checkMessages(bank.bankMsgArray, at: "\(bankPointer)/bankMsgArray", expect)
            for (namespace, presets, count) in [
                ("presetArray", bank.presetArray, presetCount), ("expPresetArray", bank.expPresetArray, expressionCount),
            ] {
                expect(presets.count == count, "\(bankPointer)/\(namespace)", "\(presets.count) presets instead of \(count)")
                for (p, preset) in presets.enumerated() {
                    let presetPointer = "\(bankPointer)/\(namespace)/\(p)"
                    expect(preset.presetNum == p, "\(presetPointer)/presetNum", "presetNum \(preset.presetNum) is not \(p)")
                    expect(preset.bankNum == b, "\(presetPointer)/bankNum", "bankNum \(preset.bankNum) is not \(b)")
                    checkMessages(preset.msgArray, at: "\(presetPointer)/msgArray", expect)
                }
            }
        }

        let channels = file.data.settings.data.midiChannels.data
        let channelsPointer = "/data/controller_settings/data/midi_channels/data"
        expect(channels.count == channelCount, channelsPointer, "\(channels.count) MIDI channels instead of \(channelCount)")
        for (i, channel) in channels.enumerated() {
            expect(channel.data.channel == i + 1, "\(channelsPointer)/\(i)/data/channel", "channel \(channel.data.channel) is not \(i + 1)")
        }
        return problems
    }

    private static func checkMessages(
        _ messages: [RawMessage], at pointer: String,
        _ expect: (Bool, @autoclosure () -> String, @autoclosure () -> String) -> Void
    ) {
        expect(messages.count == slotCount, pointer, "\(messages.count) message slots instead of \(slotCount)")
        for (k, message) in messages.enumerated() {
            expect(message.m == k, "\(pointer)/\(k)/m", "m \(message.m) is not the slot index \(k)")
            expect(message.data.count == dataCount, "\(pointer)/\(k)/data", "\(message.data.count) data bytes instead of \(dataCount)")
            for (i, value) in message.data.enumerated() {
                expect((0...127).contains(value), "\(pointer)/\(k)/data/\(i)", "data value \(value) is outside 0 to 127")
            }
        }
    }

    // MARK: - Messages

    private static func decodeBank(
        _ raw: RawBank, number b: Int, problems: inout [ImportProblem], notes: inout [ImportNote]
    ) -> Bank {
        let pointer = "/data/bankArray/\(b)"
        for (k, message) in raw.bankMsgArray.enumerated() where message.t != 0 {
            problems.append(ImportProblem(pointer: "\(pointer)/bankMsgArray/\(k)/t", reason: "bank messages are not supported"))
        }
        func presets(_ raws: [RawPreset], _ namespace: String, expression: Bool) -> [Preset] {
            raws.enumerated().map { p, preset in
                let messages = preset.msgArray.enumerated().compactMap { k, message -> Message? in
                    guard message.t != 0 else { return nil }
                    return decodeMessage(
                        message, slot: k, bank: b, expression: expression,
                        pointer: "\(pointer)/\(namespace)/\(p)/msgArray/\(k)", problems: &problems, notes: &notes)
                }
                return Preset(
                    shortName: preset.shortName, toggleName: preset.toggleName, toMsgScroll: preset.toMsgScroll,
                    messages: messages)
            }
        }
        return Bank(
            number: b, name: raw.bankName, pageLimit: raw.pageLimit,
            presets: presets(raw.presetArray, "presetArray", expression: false),
            expressions: presets(raw.expPresetArray, "expPresetArray", expression: true))
    }

    private static func decodeMessage(
        _ raw: RawMessage, slot: Int, bank: Int, expression: Bool, pointer: String,
        problems: inout [ImportProblem], notes: inout [ImportNote]
    ) -> Message? {
        let validAction = expression ? raw.a == 0 : (1...9).contains(raw.a)
        if !validAction { problems.append(ImportProblem(pointer: "\(pointer)/a", reason: "action \(raw.a) is not supported")) }
        let gate: Gate? = switch raw.tg {
        case 0: .position1
        case 1: .position2
        case 2: .both
        default: nil
        }
        if gate == nil { problems.append(ImportProblem(pointer: "\(pointer)/tg", reason: "position gate \(raw.tg) is not supported")) }
        do {
            let command = expression
                ? try decodeExpressionCommand(raw, pointer: pointer)
                : try decodeSwitchCommand(raw, bank: bank, pointer: pointer, notes: &notes)
            guard validAction, let gate else { return nil }
            return Message(slot: slot, action: raw.a, gate: gate, command: command, pointer: pointer)
        } catch {
            problems.append(error)
            return nil
        }
    }

    // MARK: - Reachability, Engage cycles and settings

    static let generalPointer = "/data/controller_settings/data/controller_settings/data"

    /// Banks reachable from the start bank through Bank Jump targets and Engage targets.
    private static func reachableBanks(_ banks: [Bank]) -> Set<Int> {
        var reached: Set<Int> = [startBank]
        var pending = [startBank]
        while let b = pending.popLast() {
            for preset in banks[b].presets {
                for message in preset.messages {
                    let target: Int? = switch message.command {
                    case .bankJump(.bank(let bank, _)): bank
                    case .engage(let bank, _, _): bank
                    default: nil
                    }
                    if let target, reached.insert(target).inserted { pending.append(target) }
                }
            }
        }
        return reached
    }

    /// Engage calls that can come back to a preset and action already on the call stack (spec 4.2).
    /// A position gate can end such a loop, so each one is a note. At run time the depth limit stops a loop that does not end.
    private static func engageCycles(_ banks: [Bank], production: Set<Int>) -> [ImportNote] {
        struct Node: Hashable {
            let address: PresetAddress
            let action: Int
        }
        var notes: [ImportNote] = []
        var done: Set<Node> = []
        var onStack: Set<Node> = []
        func visit(_ node: Node) {
            onStack.insert(node)
            for message in banks[node.address.bank].presets[node.address.preset].messages where message.action == node.action {
                guard case .engage(let bank, let preset, let action) = message.command else { continue }
                let target = Node(address: PresetAddress(bank: bank, preset: preset), action: action)
                if onStack.contains(target) {
                    notes.append(ImportNote(pointer: message.pointer, text: "This Engage closes an Engage cycle. The depth limit stops it at run time."))
                } else if !done.contains(target) {
                    visit(target)
                }
            }
            onStack.remove(node)
            done.insert(node)
        }
        for b in production.sorted() {
            for p in 0..<presetCount {
                for action in 1...9 where !done.contains(Node(address: PresetAddress(bank: b, preset: p), action: action)) {
                    visit(Node(address: PresetAddress(bank: b, preset: p), action: action))
                }
            }
        }
        return notes
    }

    private static func checkSettings(_ file: RawFile, production: Set<Int>) -> [ImportProblem] {
        var problems: [ImportProblem] = []
        func expect(_ condition: Bool, _ pointer: String, _ reason: String) {
            if !condition { problems.append(ImportProblem(pointer: pointer, reason: reason)) }
        }
        let settings = file.data.settings.data
        let general = settings.general.data
        expect(general.savePresetToggle, "\(generalPointer)/savePresetToggle", "savePresetToggle=false is not supported")
        expect((0...maxLongPressTime).contains(general.longPressTime), "\(generalPointer)/longPressTime",
               "longPressTime \(general.longPressTime) is outside 0 to \(maxLongPressTime)")
        expect(general.midiSendDelay == 0, "\(generalPointer)/midiSendDelay", "midiSendDelay is not supported")
        expect(general.bankChangeDelayTime == 0, "\(generalPointer)/bankChangeDelayTime", "bankChangeDelayTime is not supported")
        expect(general.midiClockOutputPorts == 0, "\(generalPointer)/midiClockOutputPorts", "MIDI clock output is not supported")
        expect(general.numMidiCable == midiCableCount, "\(generalPointer)/numMidiCable",
               "numMidiCable \(general.numMidiCable) is not \(midiCableCount)")

        for (i, channel) in settings.midiChannels.data.enumerated() {
            let pointer = "/data/controller_settings/data/midi_channels/data/\(i)/data"
            expect(channel.data.remap == 0, "\(pointer)/remap", "channel remap is not supported")
            expect(!channel.data.isMidiChannelOffset, "\(pointer)/isMidiChannelOffset", "channel offset is not supported")
            expect(!channel.data.engageEnabled, "\(pointer)/engageEnabled", "channel engage is not supported")
            expect(!channel.data.bypassEnabled, "\(pointer)/bypassEnabled", "channel bypass is not supported")
            for (k, attribute) in channel.data.dataAttributes.enumerated() {
                for (j, value) in attribute.enumerated() {
                    expect(value == 0, "\(pointer)/dataAttributes/\(k)/\(j)", "channel data attributes are not supported")
                }
            }
        }
        for (i, event) in settings.midiEvents.data.enumerated() {
            let pointer = "/data/controller_settings/data/midi_events/data/\(i)/data"
            expect(event.data.typeFrom == 0, "\(pointer)/typeFrom", "MIDI events are not supported")
            expect(event.data.typeTo == 0, "\(pointer)/typeTo", "MIDI events are not supported")
        }

        for (b, bank) in file.data.bankArray.enumerated() where production.contains(b) {
            let pointer = "/data/bankArray/\(b)"
            expect(!bank.bankClearToggle, "\(pointer)/bankClearToggle", "bankClearToggle=true is not supported")
            for (namespace, presets) in [("presetArray", bank.presetArray), ("expPresetArray", bank.expPresetArray)] {
                // A preset without messages sends nothing, so its toggle flags cannot change the output.
                for (p, preset) in presets.enumerated() where preset.msgArray.contains(where: { $0.t != 0 }) {
                    expect(!preset.toToggle, "\(pointer)/\(namespace)/\(p)/toToggle", "toToggle=true is not supported")
                    expect(preset.toggleGroup == 0, "\(pointer)/\(namespace)/\(p)/toggleGroup", "toggle groups are not supported")
                }
            }
        }
        return problems
    }

    private static func problem(_ error: any Error) -> ImportProblem {
        func pointer(_ path: [any CodingKey]) -> String {
            path.map { "/" + ($0.intValue.map(String.init) ?? $0.stringValue) }.joined()
        }
        guard let error = error as? DecodingError else { return ImportProblem(pointer: "", reason: "\(error)") }
        switch error {
        case .keyNotFound(let key, let context):
            return ImportProblem(pointer: pointer(context.codingPath + [key]), reason: "missing key \(key.stringValue)")
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return ImportProblem(pointer: pointer(context.codingPath), reason: context.debugDescription)
        @unknown default:
            return ImportProblem(pointer: "", reason: error.localizedDescription)
        }
    }
}

private extension Bank {
    var hasMessages: Bool { (presets + expressions).contains { !$0.messages.isEmpty } }
}
