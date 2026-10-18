import Foundation
import Testing
@testable import MC6Core

/// The display fields of the backup: colors, long names and screen settings (plan v2, Task 1).
@Suite struct DisplayImportTests {
    static let general = "/data/controller_settings/data/controller_settings/data"
    static let homeA = "/data/bankArray/0/presetArray/0"

    @Test("HOME presets keep their Position 1 and Position 2 colors and their long names")
    func homeColors() throws {
        let home = try Fixture.backup().banks[0]
        #expect(home.presets[0].longName == "TONE BANKS")
        #expect(home.presets[1].colors == PresetColors(strip: 62, text: 7, background: 126))
        #expect(home.presets[1].longName == "GLOBAL PEDALS")
        #expect(home.presets[5].toggleColors == PresetColors(strip: 0, text: 7, background: 23))
        #expect(home.presets[6].longName == "")
    }

    @Test("PEDALS BOOST: white on black at Position 1, black on yellow at Position 2")
    func boostColors() throws {
        let boost = try Fixture.backup().banks[2].presets[0]
        #expect(boost.colors == PresetColors(strip: 4, text: 7, background: 0))
        #expect(boost.toggleColors == PresetColors(strip: 0, text: 0, background: 4))
    }

    @Test("Bank description, color switch and the screen settings come from the backup")
    func bankAndSettings() throws {
        let backup = try Fixture.backup()
        #expect(backup.banks[0].description == "GUITAR RIG HOME")
        #expect(backup.banks[0].colorEnabled)
        #expect(backup.brightnessValue == 2)
        #expect(!backup.showPresetLabels)
    }

    @Test("V06: a color outside 0 to 127 in a production bank is a load error at its pointer", arguments: [
        ("ledColor", 128), ("toggleBackgroundColor", -1), ("nameToggleColor", 300),
    ])
    func colorOutOfRange(_ key: String, _ value: Int) throws {
        let pointer = "\(Self.homeA)/\(key)"
        let data = try Fixture.mutated([.set(pointer, value)])
        let error = #expect(throws: ImportError.self) { try Importer.load(data) }
        #expect(error?.problems.map(\.pointer) == [pointer])
    }

    @Test("V06: a color of 65 to 92 loads with a note, because the SysEx table does not name it")
    func undefinedColorNote() throws {
        let pointer = "\(Self.homeA)/nameColor"
        let backup = try Importer.load(try Fixture.mutated([.set(pointer, 70)]))
        #expect(backup.banks[0].presets[0].colors.text == 70)
        #expect(backup.notes.filter { $0.pointer == pointer }.count == 1)
    }

    @Test("V06: colors of a bank that bank 0 cannot reach are not checked")
    func unreachableColors() throws {
        let backup = try Importer.load(try Fixture.mutated([.set("/data/bankArray/20/presetArray/0/ledColor", 500)]))
        #expect(backup.banks[20].presets[0].colors.strip == 500)
    }

    @Test("isColorEnabled=false in a production bank loads with a note")
    func colorDisabledNote() throws {
        let pointer = "/data/bankArray/0/isColorEnabled"
        let backup = try Importer.load(try Fixture.mutated([.setBool(pointer, false)]))
        #expect(!backup.banks[0].colorEnabled)
        #expect(backup.notes.filter { $0.pointer == pointer }.count == 1)
    }

    @Test("brightnessValue outside 0 to 7 loads with a note and is clamped", arguments: [(8, 7), (-1, 0)])
    func brightnessClamp(_ value: Int, _ clamped: Int) throws {
        let pointer = "\(Self.general)/brightnessValue"
        let backup = try Importer.load(try Fixture.mutated([.set(pointer, value)]))
        #expect(backup.brightnessValue == clamped)
        #expect(backup.notes.filter { $0.pointer == pointer }.count == 1)
    }

    @Test("The fixture has no display notes: all its production colors are in the SysEx table")
    func fixtureHasNoDisplayNotes() throws {
        let notes = try Fixture.backup().notes
        #expect(!notes.contains { $0.pointer.hasSuffix("Color") || $0.pointer.hasSuffix("isColorEnabled") })
        #expect(!notes.contains { $0.pointer.hasSuffix("brightnessValue") })
    }
}
