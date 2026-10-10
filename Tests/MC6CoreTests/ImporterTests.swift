import Foundation
import Testing
@testable import MC6Core

/// Fixture facts from spec section 3 and inventory/fixture-summary.json.
@Suite struct ImporterTests {
    @Test("The fixture has 128 banks with 24 presets and 4 expression presets each")
    func bankShape() throws {
        let backup = try Fixture.backup()
        #expect(backup.banks.count == 128)
        #expect(backup.banks.allSatisfy { $0.presets.count == 24 && $0.expressions.count == 4 })
        #expect(backup.original == (try Fixture.data()))
    }

    @Test("The fixture has 1306 non-empty messages: 1300 production, 1033 switch, 273 expression")
    func messageCounts() throws {
        let counts = try Fixture.backup().counts
        #expect(counts == MessageCounts(total: 1306, production: 1300, switchMessages: 1033, expression: 273))
    }

    @Test("Production banks are the banks reachable from bank 0: IDs 0 to 12")
    func productionBanks() throws {
        #expect(try Fixture.backup().productionBanks == Set(0...12))
    }

    @Test("Every operation keeps the JSON Pointer of its source message")
    func pointers() throws {
        let backup = try Fixture.backup()
        let json = try JSONSerialization.jsonObject(with: Fixture.data())
        var seen = 0
        for (b, bank) in backup.banks.enumerated() {
            for (namespace, presets) in [("presetArray", bank.presets), ("expPresetArray", bank.expressions)] {
                for (p, preset) in presets.enumerated() {
                    for message in preset.messages {
                        #expect(message.pointer == "/data/bankArray/\(b)/\(namespace)/\(p)/msgArray/\(message.slot)")
                        let raw = try Fixture.resolve(message.pointer.split(separator: "/").map(String.init), in: json) as! NSDictionary
                        #expect(raw["m"] as? Int == message.slot)
                        #expect(raw["a"] as? Int == message.action)
                        #expect(sourceType(message.command, raw: raw) == raw["t"] as? Int)
                        seen += 1
                    }
                }
            }
        }
        #expect(seen == 1306)
    }

    /// The message type that the decoded operation must come from.
    private func sourceType(_ command: Command, raw: NSDictionary) -> Int {
        switch command {
        case .midi(let bytes): bytes[0] & 0xF0 == 0xC0 ? 1 : 2
        case .bankJump: 13
        case .togglePage: 14
        case .setToggle: 15
        case .selectExpression: 17
        case .togglePreset: 22
        case .delay: 23
        case .clockTap: 24
        case .engage: 27
        case .scrollGroupSize: 36
        case .rename: 44
        case .expression: 1
        }
    }

    @Test("U01: 114 Engage calls with d3=7 and 1 Delay with d1=127 go to the notes")
    func notes() throws {
        let backup = try Fixture.backup()
        let json = try JSONSerialization.jsonObject(with: Fixture.data())
        func rawValue(_ note: ImportNote) throws -> Int? {
            try Fixture.resolve(note.pointer.split(separator: "/").map(String.init), in: json) as? Int
        }
        func type(_ note: ImportNote) throws -> Int? {
            let message = note.pointer.split(separator: "/").map(String.init).dropLast(2)
            return (try Fixture.resolve(Array(message), in: json) as? NSDictionary)?["t"] as? Int
        }
        let engageD3 = try backup.notes.filter { try $0.pointer.hasSuffix("/data/3") && type($0) == 27 }
        #expect(engageD3.count == 114)
        #expect(try engageD3.allSatisfy { try rawValue($0) == 7 })
        let delayD1 = try backup.notes.filter { try $0.pointer.hasSuffix("/data/1") && type($0) == 23 }
        #expect(delayD1.count == 1)
        #expect(try delayD1.allSatisfy { try rawValue($0) == 127 })
    }

    @Test("A bank that bank 0 cannot reach gets one note and its preset flags are not checked")
    func unreachableBankNote() throws {
        let notes = try Fixture.backup().notes.filter { !$0.pointer.contains("/msgArray/") }
        #expect(notes.map(\.pointer) == ["/data/bankArray/20"])
    }

    @Test("Invalid JSON is a load error at the root pointer")
    func invalidJSON() throws {
        let error = #expect(throws: ImportError.self) { try Importer.load(Data("{\"schemaVersion\":".utf8)) }
        #expect(error?.problems.map(\.pointer) == [""])
    }

    @Test("All problems are listed, not only the first")
    func severalProblems() throws {
        let data = try Fixture.mutated([
            .set("/data/bankArray/0/presetArray/0/msgArray/0/a", 11),
            .set("/data/controller_settings/data/controller_settings/data/longPressTime", 29),
        ])
        let error = #expect(throws: ImportError.self) { try Importer.load(data) }
        #expect(Set(error?.problems.map(\.pointer) ?? []) == [
            "/data/bankArray/0/presetArray/0/msgArray/0/a",
            "/data/controller_settings/data/controller_settings/data/longPressTime",
        ])
    }

    struct LoadErrorCase: Sendable, CustomTestStringConvertible {
        let name: String
        let edit: Fixture.Edit
        let pointer: String
        var testDescription: String { name }

        init(_ name: String, _ edit: Fixture.Edit, at pointer: String? = nil) {
            self.name = name
            self.edit = edit
            switch edit {
            case .set(let p, _), .setBool(let p, _), .setString(let p, _), .removeLast(let p): self.pointer = pointer ?? p
            }
        }
    }

    static let message = "/data/bankArray/0/presetArray/0/msgArray/0"  // Bank Jump
    static let general = "/data/controller_settings/data/controller_settings/data"
    static let channel0 = "/data/controller_settings/data/midi_channels/data/0/data"

    static let loadErrorCases: [LoadErrorCase] = [
        .init("wrong dumpType", .setString("/dumpType", "preset")),
        .init("wrong deviceModel", .set("/deviceModel", 5)),
        .init("wrong schemaVersion", .set("/schemaVersion", 2)),
        .init("missing bank", .removeLast("/data/bankArray")),
        .init("missing preset", .removeLast("/data/bankArray/0/presetArray")),
        .init("missing expression preset", .removeLast("/data/bankArray/0/expPresetArray")),
        .init("missing message slot", .removeLast("/data/bankArray/0/presetArray/0/msgArray")),
        .init("missing bank message slot", .removeLast("/data/bankArray/0/bankMsgArray")),
        .init("short data", .removeLast("\(message)/data")),
        .init("missing MIDI channel", .removeLast("/data/controller_settings/data/midi_channels/data")),
        .init("m not equal to the index", .set("/data/bankArray/0/presetArray/0/msgArray/3/m", 4)),
        .init("bankNumber not equal to the index", .set("/data/bankArray/3/bankNumber", 4)),
        .init("presetNum not equal to the index", .set("/data/bankArray/0/presetArray/3/presetNum", 4)),
        .init("value above 127", .set("/data/bankArray/0/presetArray/0/msgArray/31/data/5", 128)),
        .init("number where a string belongs", .set("/data/bankArray/0/bankName", 1)),
        .init("unknown type", .set("\(message)/t", 99)),
        .init("action 11", .set("\(message)/a", 11)),
        .init("action 0", .set("\(message)/a", 0)),
        .init("tg 3", .set("\(message)/tg", 3)),
        .init("Set Toggle operation 3", .set("/data/bankArray/2/presetArray/7/msgArray/6/c", 4)),
        .init("Bank Jump d1=125", .set("\(message)/data/1", 125)),
        .init("Toggle Page 0", .set("/data/bankArray/0/presetArray/2/msgArray/4/data/0", 0)),
        .init("Utility subtype 1", .set("/data/bankArray/2/presetArray/10/msgArray/6/data/0", 1)),
        .init("Rename c=3", .set("/data/bankArray/2/presetArray/10/msgArray/1/c", 3)),
        .init("CC with d2 bit 0", .set("/data/bankArray/0/presetArray/2/msgArray/0/data/2", 1)),
        .init("PC on channel 17", .set("/data/bankArray/5/presetArray/0/msgArray/3/c", 17)),
        .init("Engage preset 24", .set("/data/bankArray/2/presetArray/12/msgArray/0/data/1", 24)),
        .init("Engage action 10", .set("/data/bankArray/2/presetArray/12/msgArray/0/data/2", 10)),
        .init("non-empty bank message", .set("/data/bankArray/0/bankMsgArray/0/t", 2)),
        .init("expression type 2", .set("/data/bankArray/0/expPresetArray/0/msgArray/0/t", 2)),
        .init("expression action 1", .set("/data/bankArray/0/expPresetArray/0/msgArray/0/a", 1)),
        .init("toToggle", .setBool("/data/bankArray/0/presetArray/0/toToggle", true)),
        .init("bankClearToggle", .setBool("/data/bankArray/0/bankClearToggle", true)),
        .init("toggleGroup", .set("/data/bankArray/0/presetArray/0/toggleGroup", 1)),
        .init("channel remap", .set("\(channel0)/remap", 1)),
        .init("channel offset", .setBool("\(channel0)/isMidiChannelOffset", true)),
        .init("enabled MIDI event", .set("/data/controller_settings/data/midi_events/data/0/data/typeFrom", 1)),
        .init("midiSendDelay", .set("\(general)/midiSendDelay", 1)),
        .init("bankChangeDelayTime", .set("\(general)/bankChangeDelayTime", 1)),
        .init("midiClockOutputPorts", .set("\(general)/midiClockOutputPorts", 1)),
        .init("longPressTime above 28", .set("\(general)/longPressTime", 29)),
        .init("savePresetToggle false", .setBool("\(general)/savePresetToggle", false)),
    ]

    @Test("A backup outside the v1 profile does not load, and the error names the JSON Pointer", arguments: loadErrorCases)
    func loadError(_ testCase: LoadErrorCase) throws {
        let data = try Fixture.mutated([testCase.edit])
        let error = #expect(throws: ImportError.self) { try Importer.load(data) }
        #expect(error?.problems.map(\.pointer) == [testCase.pointer])
    }
}
