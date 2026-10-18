import Testing
@testable import MC6Core

/// The color palette of the MC6 Pro screens: names from the Morningstar SysEx document, RGB approximations (plan v2).
@Suite struct PaletteTests {
    @Test("Base colors: 0 is black, 7 is white, 62 is slate gray 708090")
    func baseColors() {
        #expect(Palette.color(0) == RGB(red: 0, green: 0, blue: 0))
        #expect(Palette.color(7) == RGB(red: 0xFF, green: 0xFF, blue: 0xFF))
        #expect(Palette.color(62) == RGB(red: 0x70, green: 0x80, blue: 0x90))
        #expect(Palette.name(62) == "Slate Gray")
    }

    @Test("The SysEx table names 50 base colors: 0 to 14 and 29 to 63")
    func names() {
        #expect((0...127).filter { Palette.name($0) != nil } == Array(0...14) + Array(29...63))
    }

    @Test("Dim colors: 15 to 28 dim 1 to 14, 64 is dim black, 93 to 127 dim 29 to 63")
    func dimColors() {
        #expect(Palette.color(15) == Palette.color(1).dimmed)
        #expect(Palette.color(28) == Palette.color(14).dimmed)
        #expect(Palette.color(64) == Palette.color(0))
        #expect(Palette.color(126) == Palette.color(62).dimmed)
        #expect(Palette.color(127) == Palette.color(63).dimmed)
        #expect(Palette.color(62).dimmed == RGB(red: 50, green: 58, blue: 65))
    }

    @Test("V06: an unnamed index 65 to 92 is the dim version of index - 64, never dimmed twice")
    func unnamedColors() {
        #expect(Palette.color(70) == Palette.color(6).dimmed)
        #expect(Palette.color(80) == Palette.color(2).dimmed)
    }

    @Test("Every index 0 to 127 has a color")
    func everyIndex() {
        for index in 0...127 { _ = Palette.color(index) }
        #expect(Set((0...127).map(Palette.color)).count > 50)
    }
}
