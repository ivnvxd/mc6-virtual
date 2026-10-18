import AppKit
import Testing
@testable import MC6Core

/// Icon escapes in preset and bank names (plan v2, Icons table). The escape is a backslash and one ASCII character.
@Suite struct IconTests {
    @Test("The lookup is case-sensitive: \\H is a waveform, \\h is a house")
    func caseSensitive() {
        #expect(NamePart.parts("\\H TONES") == [.icon("waveform"), .text(" TONES")])
        #expect(NamePart.parts("\\h HOME") == [.icon("house.fill"), .text(" HOME")])
    }

    @Test("Several icons and text keep their order")
    func mixed() {
        #expect(NamePart.parts("A\\@B\\S") == [.text("A"), .icon("record.circle"), .text("B"), .icon("globe.americas.fill")])
        #expect(NamePart.parts("EMPTY") == [.text("EMPTY")])
        #expect(NamePart.parts("") == [])
    }

    @Test("An escape without an icon keeps the v1 tag; a backslash at the end stays as it is")
    func noIcon() {
        #expect(NamePart.parts("\\n X") == [.text("[n] X")])
        #expect(NamePart.parts("\\\\") == [.text("[\\]")])
        #expect(NamePart.parts("END\\") == [.text("END\\")])
    }

    @Test("The table has an icon for codes 41 to 124, except 92 and 110")
    func tableRange() {
        let codes = (0...127).filter { Icons.symbol(for: Character(UnicodeScalar(UInt8($0)))) != nil }
        #expect(codes == Array(41...124).filter { $0 != 92 && $0 != 110 })
    }

    @Test("Every icon escape in the names of the fixture's production banks has an icon")
    func fixtureEscapes() throws {
        let backup = try Fixture.backup()
        var names: [String] = []
        for b in backup.productionBanks {
            names.append(backup.banks[b].name)
            for preset in backup.banks[b].presets { names += [preset.shortName, preset.toggleName, preset.longName] }
        }
        var escapes: Set<Character> = []
        for name in names {
            var escaped = false
            for character in name {
                if escaped { escapes.insert(character) }
                escaped = !escaped && character == "\\"
            }
        }
        #expect(escapes.count >= 27)
        #expect(escapes.filter { Icons.symbol(for: $0) == nil }.isEmpty)
    }

    @Test("Every SF Symbol name in the table exists on the test Mac")
    func symbolsExist() {
        let missing = Icons.symbols.values.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        #expect(missing.isEmpty, "Missing SF Symbols: \(missing.sorted())")
    }
}
