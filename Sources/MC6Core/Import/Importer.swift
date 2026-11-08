import Foundation

/// Reads an MC6 Pro `allBanks` backup and checks it against the v1 profile.
/// A file that is not an MC6 Pro All Banks backup, misses a key or breaks the structure does not load; the error lists
/// every reason with its JSON Pointer. Other content outside the profile loads: the importer skips it with a note (V18).
/// `JSONDecoder` stops at the first missing key or wrong JSON type, so a decode failure is one problem.
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
    /// A channel's `sendToPort` mask has 12 port bits, 0 to 11 (spec 8.2). Only bits 1 and 7 map to a virtual port.
    static let maxSendToPort = 4095
    /// The MC6 Pro starts in bank 0 when `loadLastBankOnStartup` is off (U12).
    static let startBank = 0
    /// V06: palette indexes are 0 to 127. The SysEx table names no color for 65 to 92.
    static let colorRange = 0...127
    static let unnamedColors = 65...92
    /// The editor's brightness options, 0 (30%) to 7 (100%).
    static let brightnessRange = 0...7

    private static let generalPointer = "/data/controller_settings/data/controller_settings/data"
    private static let channelsPointer = "/data/controller_settings/data/midi_channels/data"
    private static let eventsPointer = "/data/controller_settings/data/midi_events/data"
    private static func bankPointer(_ b: Int) -> String { "/data/bankArray/\(b)" }

    public static func load(_ data: Data) throws(ImportError) -> Backup {
        let header: ImportHeader
        do {
            header = try JSONDecoder().decode(ImportHeader.self, from: data)
        } catch {
            throw ImportError(problems: [ImportProblem(pointer: "", reason: "This file is not an MC6 Pro backup.")])
        }
        if let problem = checkHeader(header) { throw ImportError(problems: [problem]) }

        let file: RawFile
        do {
            file = try JSONDecoder().decode(RawFile.self, from: data)
        } catch {
            throw ImportError(problems: [problem(error)])
        }

        let shapeProblems = checkShape(file)
        guard shapeProblems.isEmpty else { throw ImportError(problems: shapeProblems) }

        var skips: [Skip] = []
        var notes: [ImportNote] = []
        let banks = file.data.bankArray.enumerated().map { b, raw in
            decodeBank(raw, number: b, skips: &skips, notes: &notes)
        }
        // Reachability uses only the kept messages: a skipped Bank Jump or Engage is no edge.
        // Skipped messages in other banks get no note, because the not-reachable note covers those banks.
        let production = reachableBanks(banks)
        notes += skips.filter { production.contains($0.bank) }.map(\.note)
        notes += settingNotes(file, production: production)
        notes += startNotes(file, banks: banks, production: production)
        notes += displayNotes(file, production: production)
        notes += engageCycles(banks, production: production)

        let settings = file.data.settings.data
        let general = settings.general.data
        return Backup(
            original: data,
            banks: banks,
            productionBanks: production,
            longPressTime: min(max(general.longPressTime, 0), maxLongPressTime),
            brightnessValue: min(max(general.brightnessValue, brightnessRange.lowerBound), brightnessRange.upperBound),
            showPresetLabels: general.showPresetLabels,
            sendToPort: settings.midiChannels.data.map(\.data.sendToPort),
            notes: notes)
    }

    // MARK: - Structure

    /// The first wrong header key. The model comes first, because a backup of another model can have any dump type.
    private static func checkHeader(_ header: ImportHeader) -> ImportProblem? {
        if header.deviceModel != 6 {
            return ImportProblem(pointer: "/deviceModel", reason: "This backup is from another Morningstar model, not the MC6 Pro.")
        }
        if header.dumpType != "allBanks" {
            return ImportProblem(pointer: "/dumpType", reason: "This is not an All Banks backup. Export All Banks in the Morningstar editor.")
        }
        if header.schemaVersion != 1 {
            return ImportProblem(pointer: "/schemaVersion", reason: "This backup has format version \(header.schemaVersion). MC6 Virtual reads version 1.")
        }
        return nil
    }

    private static func checkShape(_ file: RawFile) -> [ImportProblem] {
        var problems: [ImportProblem] = []
        func expect(_ condition: Bool, _ pointer: @autoclosure () -> String, _ reason: @autoclosure () -> String) {
            if !condition { problems.append(ImportProblem(pointer: pointer(), reason: reason())) }
        }
        let banks = file.data.bankArray
        expect(banks.count == bankCount, "/data/bankArray", "\(banks.count) banks instead of \(bankCount)")
        for (b, bank) in banks.enumerated() {
            let bankPointer = Self.bankPointer(b)
            expect(bank.bankNumber == b, "\(bankPointer)/bankNumber", "The bank number does not match its place in the file.")
            checkMessages(bank.bankMsgArray, at: "\(bankPointer)/bankMsgArray", expect)
            for (namespace, presets, count, expression) in [
                ("presetArray", bank.presetArray, presetCount, false), ("expPresetArray", bank.expPresetArray, expressionCount, true),
            ] {
                expect(presets.count == count, "\(bankPointer)/\(namespace)", "The bank has \(presets.count) presets instead of \(count).")
                for (p, preset) in presets.enumerated() {
                    let presetPointer = "\(bankPointer)/\(namespace)/\(p)"
                    expect(preset.presetNum == p, "\(presetPointer)/presetNum", "The preset number does not match its place in the bank.")
                    expect(preset.bankNum == b, "\(presetPointer)/bankNum", "The bank number of the preset does not match its bank.")
                    expect(preset.isExp == expression, "\(presetPointer)/isExp", "The preset is in the wrong list for its isExp value.")
                    checkMessages(preset.msgArray, at: "\(presetPointer)/msgArray", expect)
                }
            }
        }

        // The settings envelopes name their content in `type` (spec 4.1).
        func expectType<Value>(_ wrapped: Wrapped<Value>, _ type: String, at pointer: String) {
            expect(wrapped.type == type, "\(pointer)/type", "The settings type is \(wrapped.type) instead of \(type).")
        }
        let settings = file.data.settings
        expectType(settings, "controller_settings_all", at: "/data/controller_settings")
        expectType(settings.data.general, "general_configurations", at: "/data/controller_settings/data/controller_settings")
        expectType(settings.data.midiChannels, "midi_channels", at: "/data/controller_settings/data/midi_channels")
        expectType(settings.data.midiEvents, "midi_events", at: "/data/controller_settings/data/midi_events")
        for (i, event) in settings.data.midiEvents.data.enumerated() {
            expectType(event, "midi_event", at: "\(eventsPointer)/\(i)")
        }

        let channels = settings.data.midiChannels.data
        expect(channels.count == channelCount, channelsPointer, "The file has \(channels.count) MIDI channels instead of \(channelCount).")
        for (i, channel) in channels.enumerated() {
            expectType(channel, "midi_channel", at: "\(channelsPointer)/\(i)")
            expect(channel.data.channel == i + 1, "\(channelsPointer)/\(i)/data/channel", "MIDI channel \(channel.data.channel) is in place \(i + 1).")
        }
        return problems
    }

    private static func checkMessages(
        _ messages: [RawMessage], at pointer: String,
        _ expect: (Bool, @autoclosure () -> String, @autoclosure () -> String) -> Void
    ) {
        expect(messages.count == slotCount, pointer, "The message list has \(messages.count) slots instead of \(slotCount).")
        for (k, message) in messages.enumerated() {
            expect(message.m == k, "\(pointer)/\(k)/m", "The message number does not match its slot.")
            expect(message.data.count == dataCount, "\(pointer)/\(k)/data", "The message has \(message.data.count) data values instead of \(dataCount).")
            for (i, value) in message.data.enumerated() {
                expect((0...127).contains(value), "\(pointer)/\(k)/data/\(i)", "The data value \(value) is outside 0 to 127.")
            }
        }
    }

    // MARK: - Messages

    /// A skip note of a bank. It joins the notes only if the bank is a production bank.
    private struct Skip {
        let bank: Int
        let note: ImportNote
    }

    private static func decodeBank(
        _ raw: RawBank, number b: Int, skips: inout [Skip], notes: inout [ImportNote]
    ) -> Bank {
        let pointer = bankPointer(b)
        // V21: a bank message with the event Nothing (`a=0`) never runs, so it needs no note.
        var enterMessages: [BankMessage] = []
        for (k, message) in raw.bankMsgArray.enumerated() where message.t != 0 && message.a != 0 {
            do {
                enterMessages.append(try decodeBankMessage(
                    message, slot: k, bank: b, pointer: "\(pointer)/bankMsgArray/\(k)", notes: &notes))
            } catch {
                skips.append(Skip(bank: b, note: ImportNote(
                    pointer: error.pointer, text: error.reason, kind: .bankMessage, messageType: message.t)))
            }
        }
        // V06: a color outside the palette shows as the nearest color. `settingNotes` notes it in production banks.
        func color(_ value: Int) -> Int { min(max(value, colorRange.lowerBound), colorRange.upperBound) }
        func presets(_ raws: [RawPreset], _ namespace: String, expression: Bool) -> [Preset] {
            raws.enumerated().map { p, preset in
                let messages = preset.msgArray.enumerated().compactMap { k, message -> Message? in
                    guard message.t != 0 else { return nil }
                    return decodeMessage(
                        message, slot: k, bank: b, preset: expression ? nil : p, expression: expression,
                        pointer: "\(pointer)/\(namespace)/\(p)/msgArray/\(k)", skips: &skips, notes: &notes)
                }
                return Preset(
                    shortName: preset.shortName, toggleName: preset.toggleName, toMsgScroll: preset.toMsgScroll,
                    messages: messages, longName: preset.longName,
                    colors: PresetColors(
                        strip: color(preset.ledColor), text: color(preset.nameColor), background: color(preset.backgroundColor)),
                    toggleColors: PresetColors(
                        strip: color(preset.ledToggleColor), text: color(preset.nameToggleColor),
                        background: color(preset.toggleBackgroundColor)),
                    toggleMode: !expression && preset.toToggle)
            }
        }
        return Bank(
            number: b, name: raw.bankName, pageLimit: (0...maxPageLimit).contains(raw.pageLimit) ? raw.pageLimit : 0,
            presets: presets(raw.presetArray, "presetArray", expression: false),
            expressions: presets(raw.expPresetArray, "expPresetArray", expression: true),
            description: raw.bankDescription, colorEnabled: raw.isColorEnabled, enterMessages: enterMessages,
            nameColors: NameColors(text: color(raw.textColor ?? 0), background: color(raw.backgroundColor ?? 7)))
    }

    /// Decodes one message, or skips it with one note at its first bad field (V18). `preset` is nil for an expression preset.
    private static func decodeMessage(
        _ raw: RawMessage, slot: Int, bank: Int, preset: Int?, expression: Bool, pointer: String,
        skips: inout [Skip], notes: inout [ImportNote]
    ) -> Message? {
        func skip(_ problem: ImportProblem) -> Message? {
            skips.append(Skip(bank: bank, note: ImportNote(
                pointer: problem.pointer, text: problem.reason, kind: .skippedMessage,
                address: preset.map { PresetAddress(bank: bank, preset: $0) }, messageType: raw.t)))
            return nil
        }
        let validAction = expression ? raw.a == 0 : SwitchAction.targets.contains(raw.a)
        guard validAction else { return skip(ImportProblem(pointer: "\(pointer)/a", reason: "Action \(raw.a) is not supported.")) }
        // The spec defines `tg` only for switch messages; an expression preset has no position.
        let gate: Gate? = switch raw.tg {
        case 0 where !expression: .position1
        case 1 where !expression: .position2
        case 2: .both
        default: nil
        }
        guard let gate else { return skip(ImportProblem(pointer: "\(pointer)/tg", reason: "Position setting \(raw.tg) is not supported.")) }
        do {
            let command = expression
                ? try decodeExpressionCommand(raw, pointer: pointer)
                : try decodeSwitchCommand(raw, bank: bank, pointer: pointer, notes: &notes)
            return Message(slot: slot, action: raw.a, gate: gate, command: command, pointer: pointer)
        } catch {
            return skip(error)
        }
    }

    // MARK: - Reachability, Engage cycles and settings

    /// Banks reachable from the start bank through Bank Jump targets and Engage targets, bank Engage messages included.
    /// V25: a reachable Bank Up or Bank Down reaches every bank with messages, and the search goes on from them.
    private static func reachableBanks(_ banks: [Bank]) -> Set<Int> {
        var reached: Set<Int> = [startBank]
        var pending = [startBank]
        var stepped = false
        while let b = pending.popLast() {
            var targets = banks[b].enterMessages.map(\.target.bank)
            for preset in banks[b].presets {
                for message in preset.messages {
                    switch message.command {
                    case .bankJump(.bank(let bank, _), _): targets.append(bank)
                    case .engage(let bank, _, _): targets.append(bank)
                    case .bankStep where !stepped:
                        stepped = true
                        targets += banks.filter(\.hasMessages).map(\.number)
                    default: break
                    }
                }
            }
            for target in targets where reached.insert(target).inserted { pending.append(target) }
        }
        return reached
    }

    /// Engage calls that can come back to a preset and action already on the call stack (spec 4.2).
    /// A position gate can end such a loop, so each one is a note. At run time the depth limit stops a loop that does not end.
    static func engageCycles(_ banks: [Bank], production: Set<Int>) -> [ImportNote] {
        struct Node: Hashable {
            let address: PresetAddress
            let action: Int
        }
        var notes: [ImportNote] = []
        var done: Set<Node> = []
        var onStack: Set<Node> = []
        // A depth-first search with its own stack: a valid chain can pass every preset and action of all banks,
        // which is too deep for recursion. Each entry is a node and the index of its next message.
        var stack: [(node: Node, next: Int)] = []
        func push(_ node: Node) {
            onStack.insert(node)
            stack.append((node, 0))
        }
        for b in production.sorted() {
            for p in 0..<presetCount {
                for action in SwitchAction.targets where !done.contains(Node(address: PresetAddress(bank: b, preset: p), action: action)) {
                    push(Node(address: PresetAddress(bank: b, preset: p), action: action))
                    while let (node, next) = stack.last {
                        let messages = banks[node.address.bank].presets[node.address.preset].messages
                        guard next < messages.count else {
                            stack.removeLast()
                            onStack.remove(node)
                            done.insert(node)
                            continue
                        }
                        stack[stack.count - 1].next += 1
                        let message = messages[next]
                        guard message.action == node.action,
                              case .engage(let bank, let preset, let action) = message.command else { continue }
                        let target = Node(address: PresetAddress(bank: bank, preset: preset), action: action)
                        if onStack.contains(target) {
                            notes.append(ImportNote(
                                pointer: message.pointer,
                                text: "This Engage closes an Engage cycle. The app stops a cycle after \(Engine.maxDepth) nested presets.",
                                kind: .engageCycle))
                        } else if !done.contains(target) {
                            push(target)
                        }
                    }
                }
            }
        }
        return notes
    }

    /// Notes on values that change no output: `loadLastBankOnStartup` and banks that never run.
    private static func startNotes(_ file: RawFile, banks: [Bank], production: Set<Int>) -> [ImportNote] {
        var notes: [ImportNote] = []
        if file.data.settings.data.general.data.loadLastBankOnStartup {
            notes.append(ImportNote(
                pointer: "\(generalPointer)/loadLastBankOnStartup",
                text: "Load Last Bank on Startup is on. The app always starts in bank \(startBank + 1).", kind: .startBank))
        }
        for bank in banks where !production.contains(bank.number) && bank.hasMessages {
            notes.append(ImportNote(
                pointer: bankPointer(bank.number),
                text: "Bank \(bank.number + 1) is not reachable from bank \(startBank + 1) by Bank Jump, Engage Preset, Bank Up or Bank Down. The app does not show it.",
                kind: .unreachableBank))
        }
        return notes
    }

    /// Skip notes for the settings and the flags that the app does not run (V18, V19), and for values it replaces.
    private static func settingNotes(_ file: RawFile, production: Set<Int>) -> [ImportNote] {
        var notes: [ImportNote] = []
        func expect(
            _ condition: Bool, _ pointer: @autoclosure () -> String, _ reason: @autoclosure () -> String,
            _ kind: ImportNote.Kind = .setting, _ address: PresetAddress? = nil
        ) {
            if !condition { notes.append(ImportNote(pointer: pointer(), text: reason(), kind: kind, address: address)) }
        }
        let settings = file.data.settings.data
        let general = settings.general.data
        expect(general.savePresetToggle, "\(generalPointer)/savePresetToggle", "Remember Toggle States is off. The app always remembers the positions.")
        expect((0...maxLongPressTime).contains(general.longPressTime), "\(generalPointer)/longPressTime",
               "The long-press time \(general.longPressTime) is outside 0 to \(maxLongPressTime). The app uses the nearest value.")
        expect(general.midiSendDelay == 0, "\(generalPointer)/midiSendDelay", "MIDI send delay is not supported. The app sends without the delay.")
        expect(general.bankChangeDelayTime == 0, "\(generalPointer)/bankChangeDelayTime", "The bank change delay is not supported. The app changes banks at once.")
        expect(general.midiClockOutputPorts == 0, "\(generalPointer)/midiClockOutputPorts", "MIDI clock output is not supported. The app sends no clock.")
        expect(general.numMidiCable == midiCableCount, "\(generalPointer)/numMidiCable",
               "The backup uses \(general.numMidiCable) USB MIDI ports. The app has \(midiCableCount).")

        for (i, channel) in settings.midiChannels.data.enumerated() {
            let pointer = "\(channelsPointer)/\(i)/data"
            expect(channel.data.remap == 0, "\(pointer)/remap", "Channel remap is not supported. Messages go out on their own channel.")
            expect(!channel.data.isMidiChannelOffset, "\(pointer)/isMidiChannelOffset", "Channel offset is not supported.")
            expect(!channel.data.engageEnabled, "\(pointer)/engageEnabled", "Channel engage is not supported.")
            expect(!channel.data.bypassEnabled, "\(pointer)/bypassEnabled", "Channel bypass is not supported.")
            expect((0...maxSendToPort).contains(channel.data.sendToPort), "\(pointer)/sendToPort",
                   "Port setting \(channel.data.sendToPort) is outside 0 to \(maxSendToPort). The app reads only ports 1 and 2 from it.")
            for (k, attribute) in channel.data.dataAttributes.enumerated() {
                for (j, value) in attribute.enumerated() {
                    expect(value == 0, "\(pointer)/dataAttributes/\(k)/\(j)", "Channel data attributes are not supported.")
                }
            }
        }
        for (i, event) in settings.midiEvents.data.enumerated() {
            let pointer = "\(eventsPointer)/\(i)/data"
            expect(event.data.typeFrom == 0, "\(pointer)/typeFrom", "MIDI events are not supported.")
            expect(event.data.typeTo == 0, "\(pointer)/typeTo", "MIDI events are not supported.")
        }

        for (b, bank) in file.data.bankArray.enumerated() where production.contains(b) {
            let pointer = bankPointer(b)
            expect(!bank.bankClearToggle, "\(pointer)/bankClearToggle", "Bank clear is not supported. Other presets keep their positions.", .bankClear)
            expect((0...maxPageLimit).contains(bank.pageLimit), "\(pointer)/pageLimit",
                   "Page limit \(bank.pageLimit) is outside 0 to \(maxPageLimit). The bank shows all 4 pages.")
            for (namespace, presets) in [("presetArray", bank.presetArray), ("expPresetArray", bank.expPresetArray)] {
                // A preset without messages sends nothing, so its toggle flags cannot change the output.
                for (p, preset) in presets.enumerated() where preset.msgArray.contains(where: { $0.t != 0 }) {
                    let address = namespace == "presetArray" ? PresetAddress(bank: b, preset: p) : nil
                    // V30: Toggle Mode of a switch preset runs. An expression preset has no position.
                    expect(address != nil || !preset.toToggle, "\(pointer)/\(namespace)/\(p)/toToggle",
                           "Toggle Mode of an expression preset is not supported.", .toggleMode)
                    expect(preset.toggleGroup == 0, "\(pointer)/\(namespace)/\(p)/toggleGroup", "Toggle groups are not supported. The preset does not release the others in its group.",
                           .toggleGroup, address)
                }
            }
            // V06: the screens draw the switch presets and the bank name of production banks.
            for (key, value) in bank.colorFields {
                expect(colorRange.contains(value), "\(pointer)/\(key)", "Color \(value) is outside 0 to 127. The screen shows the nearest color.", .color)
            }
            for (p, preset) in bank.presetArray.enumerated() {
                for (key, value) in preset.colorFields {
                    expect(colorRange.contains(value), "\(pointer)/presetArray/\(p)/\(key)",
                           "Color \(value) is outside 0 to 127. The screen shows the nearest color.", .color)
                }
            }
        }
        return notes
    }

    /// Notes on display values that load with a remark: unnamed colors, colors off, brightness out of range.
    private static func displayNotes(_ file: RawFile, production: Set<Int>) -> [ImportNote] {
        var notes: [ImportNote] = []
        let brightness = file.data.settings.data.general.data.brightnessValue
        if !brightnessRange.contains(brightness) {
            notes.append(ImportNote(
                pointer: "\(generalPointer)/brightnessValue",
                text: "Brightness \(brightness) is outside 0 to 7. The screens use the nearest value.", kind: .setting))
        }
        for (b, bank) in file.data.bankArray.enumerated() where production.contains(b) {
            if !bank.isColorEnabled {
                notes.append(ImportNote(
                    pointer: "\(bankPointer(b))/isColorEnabled",
                    text: "Colors are off in this bank. Its presets show white on black.", kind: .colorsOff))
            }
            for (key, value) in bank.colorFields where unnamedColors.contains(value) {
                notes.append(ImportNote(
                    pointer: "\(bankPointer(b))/\(key)",
                    text: "Color \(value) has no name in the Morningstar table. It shows as the dim version of color \(value - 64).",
                    kind: .unnamedColor))
            }
            for (p, preset) in bank.presetArray.enumerated() {
                for (key, value) in preset.colorFields where unnamedColors.contains(value) {
                    notes.append(ImportNote(
                        pointer: "\(bankPointer(b))/presetArray/\(p)/\(key)",
                        text: "Color \(value) has no name in the Morningstar table. It shows as the dim version of color \(value - 64).",
                        kind: .unnamedColor))
                }
            }
        }
        return notes
    }

    private static func problem(_ error: any Error) -> ImportProblem {
        func pointer(_ path: [any CodingKey]) -> String {
            path.map { "/" + ($0.intValue.map(String.init) ?? $0.stringValue) }.joined()
        }
        guard let error = error as? DecodingError else { return ImportProblem(pointer: "", reason: "\(error)") }
        switch error {
        case .keyNotFound(let key, let context):
            return ImportProblem(pointer: pointer(context.codingPath + [key]), reason: "The file is missing the key \(key.stringValue) that the MC6 Pro editor writes.")
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return ImportProblem(pointer: pointer(context.codingPath), reason: context.debugDescription)
        @unknown default:
            return ImportProblem(pointer: "", reason: error.localizedDescription)
        }
    }
}

private extension RawPreset {
    /// The color keys of Position 1 and Position 2, in JSON key order.
    var colorFields: [(key: String, value: Int)] {
        [
            ("ledColor", ledColor), ("ledToggleColor", ledToggleColor), ("nameColor", nameColor),
            ("nameToggleColor", nameToggleColor), ("backgroundColor", backgroundColor),
            ("toggleBackgroundColor", toggleBackgroundColor),
        ]
    }
}

private extension RawBank {
    /// The bank name colors that the backup has, in JSON key order.
    var colorFields: [(key: String, value: Int)] {
        [("backgroundColor", backgroundColor), ("textColor", textColor)].compactMap { key, value in value.map { (key, $0) } }
    }
}

private extension Bank {
    var hasMessages: Bool { (presets + expressions).contains { !$0.messages.isEmpty } || !enterMessages.isEmpty }
}
