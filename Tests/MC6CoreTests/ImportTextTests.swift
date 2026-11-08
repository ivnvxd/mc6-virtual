import Foundation
import Testing
@testable import MC6Core

/// The plain text of import notes and problems (V18): names from the fixture, numbers from 1.
@Suite(.needsSpec) struct ImportTextTests {
    static let general = "/data/controller_settings/data/controller_settings/data"

    @Test("Message type names come from the spec's three enums, which differ")
    func typeNames() {
        #expect(TypeNames.name(3, in: .switchMessage) == "Note On")
        #expect(TypeNames.name(6, in: .switchMessage) == "SysEx")
        #expect(TypeNames.name(29, in: .bankMessage) == "SysEx")
        #expect(TypeNames.name(6, in: .bankMessage) == "Set Toggle")
        #expect(TypeNames.name(2, in: .expression) == "Pedal CC on Toe Down")
        #expect(TypeNames.name(99, in: .switchMessage) == "Message type 99")
    }

    @Test("A place names the bank, the preset and the message, all from 1")
    func places() throws {
        let backup = try Fixture.backup()
        #expect(ImportText.place(of: "/data/bankArray/0/presetArray/0/msgArray/1", in: backup) == "Bank 1 HOME, A TONES, message 2")
        #expect(ImportText.place(of: "/data/bankArray/0/presetArray/0/msgArray/1/data/2", in: backup) == "Bank 1 HOME, A TONES, message 2")
        #expect(ImportText.place(of: "/data/bankArray/0/presetArray/0/toToggle", in: backup) == "Bank 1 HOME, A TONES")
        #expect(ImportText.place(of: "/data/bankArray/0/expPresetArray/1/msgArray/0/t", in: backup) == "Bank 1 HOME, EXP 2, message 1")
        #expect(ImportText.place(of: "/data/bankArray/0/bankMsgArray/2/t", in: backup) == "Bank 1 HOME, bank message 3")
        #expect(ImportText.place(of: "/data/bankArray/0/pageLimit", in: backup) == "Bank 1 HOME")
        #expect(ImportText.place(of: "/data/bankArray/20", in: backup).hasPrefix("Bank 21"))
        #expect(ImportText.place(of: "\(Self.general)/longPressTime", in: backup) == "Controller settings")
        #expect(ImportText.place(of: "/data/controller_settings/data/midi_channels/data/3/data/remap", in: backup) == "MIDI channel 4")
        #expect(ImportText.place(of: "/data/controller_settings/data/midi_events/data/0/data/typeFrom", in: backup) == "MIDI event 1")
        #expect(ImportText.place(of: "", in: backup) == "The file")
    }

    @Test("Without a backup, a place has numbers only")
    func placesWithoutBackup() {
        #expect(ImportText.place(of: "/data/bankArray/3/presetArray/2/msgArray/0/m", in: nil) == "Bank 4, C, message 1")
        #expect(ImportText.place(of: "/data/bankArray/3/bankNumber", in: nil) == "Bank 4")
    }

    @Test("A note line is its place and its sentence")
    func noteLine() throws {
        let pointer = "/data/bankArray/0/presetArray/0/msgArray/0/t"
        let backup = try Importer.load(Fixture.mutated([.set(pointer, 41)]))
        let note = try #require(backup.notes.first { $0.pointer == pointer })
        #expect(ImportText.line(note, in: backup) == "Bank 1 HOME, A TONES, message 1: MMC is not supported.")
    }

    @Test("A header problem is one sentence that names the fix")
    func headerSentences() throws {
        let other = try #require(#expect(throws: ImportError.self) {
            try Importer.load(Data(#"{"schemaVersion":1,"dumpType":"allBanks","deviceModel":8,"data":{}}"#.utf8))
        })
        #expect(ImportText.line(other.problems[0]) == "This backup is from another Morningstar model, not the MC6 Pro.")
        let single = try #require(#expect(throws: ImportError.self) {
            try Importer.load(Data(#"{"schemaVersion":1,"dumpType":"bank","deviceModel":6,"data":{}}"#.utf8))
        })
        #expect(ImportText.line(single.problems[0]) == "This is not an All Banks backup. Export All Banks in the Morningstar editor.")
        let notJSON = try #require(#expect(throws: ImportError.self) { try Importer.load(Data("{}".utf8)) })
        #expect(ImportText.line(notJSON.problems[0]) == "This file is not an MC6 Pro backup.")
    }

    @Test("A missing key names the key")
    func missingKey() throws {
        let error = try #require(#expect(throws: ImportError.self) {
            try Importer.load(Fixture.mutated([.removeKey("/data/bankArray/0/pageLimit")]))
        })
        #expect(ImportText.line(error.problems[0]) == "Bank 1: The file is missing the key pageLimit that the MC6 Pro editor writes.")
    }

    @Test("The failure headline counts the problems in words")
    func failureHeadline() {
        let problem = ImportProblem(pointer: "", reason: "x")
        #expect(ImportText.failure([problem]) == "The backup did not load: 1 problem.")
        #expect(ImportText.failure([problem, problem]) == "The backup did not load: 2 problems.")
    }

    @Test("The skipped headline counts skipped items; information notes do not count")
    func skippedHeadline() throws {
        #expect(ImportText.skippedHeadline(try Fixture.backup().notes) == nil)
        let one = try Importer.load(Fixture.mutated([.set("/data/bankArray/0/presetArray/0/msgArray/0/t", 41)]))
        #expect(ImportText.skippedHeadline(one.notes) == "1 item skipped")
        let two = try Importer.load(Fixture.mutated([
            .set("/data/bankArray/0/presetArray/0/msgArray/0/t", 41), .set("\(Self.general)/midiSendDelay", 1),
        ]))
        #expect(ImportText.skippedHeadline(two.notes) == "2 items skipped")
    }

    @Test("The summary groups skipped messages by type, with message and bank counts")
    func summary() throws {
        let backup = try Importer.load(Fixture.mutated([
            .set("/data/bankArray/0/presetArray/0/msgArray/0/t", 41),
            .set("/data/bankArray/0/presetArray/0/msgArray/1/t", 41),
            .set("/data/bankArray/5/presetArray/0/msgArray/3/t", 41),
            .set("/data/bankArray/2/presetArray/12/msgArray/0/t", 6),
            .setBool("/data/bankArray/0/expPresetArray/0/toToggle", true),
        ]))
        let lines = ImportText.summary(backup.notes)
        #expect(lines.prefix(3) == ["MMC: 3 messages in 2 banks", "SysEx: 1 message in 1 bank", "Toggle Mode: 1 preset"])
        #expect(lines.contains("Banks not reachable from bank 1: 1"))
    }

    @Test("Copy text lists the summary, then every note line")
    func copyText() throws {
        let backup = try Importer.load(Fixture.mutated([.set("/data/bankArray/0/presetArray/0/msgArray/0/t", 41)]))
        let text = ImportText.copy(backup.notes, in: backup)
        #expect(text.hasPrefix("MMC: 1 message in 1 bank\n"))
        #expect(text.contains("\nBank 1 HOME, A TONES, message 1: MMC is not supported.\n"))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == ImportText.summary(backup.notes).count + 1 + ImportText.lines(backup.notes, in: backup).count + 1)
        #expect(lines[ImportText.summary(backup.notes).count].isEmpty && lines.last?.isEmpty == true)
    }

    @Test("U01: an unused-value note says that the app does not use the value")
    func unusedValueText() throws {
        let unused = try Fixture.backup().notes.filter { $0.kind == .unusedValue }
        #expect(!unused.isEmpty)
        #expect(unused.allSatisfy { $0.text.hasSuffix(" The app does not use this value.") })
    }

    @Test("U01: the note lines join unused values with the same text, with a message and a bank count; other notes keep their own line")
    func groupedLines() throws {
        let backup = try Fixture.backup()
        func unused(_ bank: Int, _ text: String) -> ImportNote {
            ImportNote(pointer: "/data/bankArray/\(bank)/presetArray/0/msgArray/0/c", text: text, kind: .unusedValue)
        }
        let skip = ImportNote(pointer: "/data/bankArray/0/presetArray/1/msgArray/0/t", text: "Note On is not supported.", kind: .skippedMessage)
        let notes = [unused(0, "Seven."), skip, unused(0, "Seven."), unused(2, "Seven."), unused(1, "Two.")]
        #expect(ImportText.lines(notes, in: backup) == [
            "3 messages in 2 banks: Seven.",
            "Bank 1 HOME, B PEDALS, message 1: Note On is not supported.",
            "Bank 2 TONES, A CORE, message 1: Two.",
        ])
    }

    @Test("No note text has a policy ID or a bank number from 0")
    func plainNotes() throws {
        let backup = try Importer.load(Fixture.mutated([.setBool("\(Self.general)/loadLastBankOnStartup", true)]))
        for note in backup.notes {
            #expect(note.text.range(of: #"\b[UV]\d\d\b"#, options: .regularExpression) == nil, "\(note.text)")
            #expect(!note.text.contains("bank 0"), "\(note.text)")
            #expect(note.text.hasSuffix("."), "\(note.text)")
        }
    }
}
