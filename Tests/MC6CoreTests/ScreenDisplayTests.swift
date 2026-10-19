import Testing
@testable import MC6Core

/// The three screens of the panel (V07), from the fixture.
/// HOME page 1: A "\H TONES", B "\X PEDALS", C "\| TAP", D "\W DAW", E "\V LOOPER", F "\g MUTE".
@Suite struct ScreenDisplayTests {
    static let white = Palette.color(7)
    static let black = Palette.color(0)

    static func screens(
        _ state: RuntimeState, _ backup: Backup, lastPressed: PresetAddress? = nil, expression: Int = 0,
        showLetters: Bool = false
    ) -> [Screen] {
        ScreenDisplay.screens(state, in: backup, lastPressed: lastPressed, expression: expression, showLetters: showLetters)
    }

    @Test("Screen 1 serves D and A, screen 2 E and B, screen 3 F and C")
    func layout() throws {
        let backup = try Fixture.backup()
        let screens = Self.screens(RuntimeState(backup: backup), backup)
        #expect(screens.map(\.top.button) == [.d, .e, .f])
        #expect(screens.map(\.bottom.button) == [.a, .b, .c])
        #expect(screens.map(\.bottom.address.preset) == [0, 1, 2])
    }

    @Test("HOME page 1: names with icons and the Position 1 colors of the backup")
    func homeBands() throws {
        let backup = try Fixture.backup()
        let screens = Self.screens(RuntimeState(backup: backup), backup)
        let daw = screens[0].top
        #expect(daw.parts == [.icon("slider.horizontal.3"), .text(" DAW")])
        #expect(daw.strip == Palette.color(29))
        #expect(daw.text == Self.white)
        #expect(daw.background == Self.black)
        #expect(daw.position == .one)
        #expect(daw.letter == nil)
        #expect(screens[0].bottom.parts == [.icon("waveform"), .text(" TONES")])
        #expect(screens[1].bottom.background == Palette.color(126))
        #expect(screens[2].top.parts == [.icon("speaker.slash.fill"), .text(" MUTE")])
    }

    @Test("Position 2 uses the toggle name and the toggle colors (PEDALS BOOST: black on yellow)")
    func positionTwo() throws {
        let backup = try Fixture.backup()
        var state = RuntimeState(backup: backup)
        state.bank = 2
        state[position: PresetAddress(bank: 2, preset: 0)] = .two
        let boost = Self.screens(state, backup)[0].bottom
        #expect(boost.position == .two)
        #expect(boost.parts == [.icon("bolt.fill"), .text(" BOOST")])
        #expect(boost.text == Self.black)
        #expect(boost.background == Palette.color(4))
        #expect(boost.strip == Self.black)
    }

    @Test("U09: a temporary name wins over both names")
    func temporaryName() throws {
        let backup = try Fixture.backup()
        var state = RuntimeState(backup: backup)
        state.names[PresetAddress(bank: 0, preset: 0)] = "\\@ CLEAR"
        #expect(Self.screens(state, backup)[0].bottom.parts == [.icon("record.circle"), .text(" CLEAR")])
    }

    @Test("Switch letters show only when they are on")
    func letters() throws {
        let backup = try Fixture.backup()
        let screens = Self.screens(RuntimeState(backup: backup), backup, showLetters: true)
        #expect(screens.map(\.top.letter) == ["D", "E", "F"])
        #expect(screens.map(\.bottom.letter) == ["A", "B", "C"])
    }

    @Test("Center bands: long name of the last press, bank name, pedal percent and bank and page")
    func centers() throws {
        let backup = try Fixture.backup()
        var state = RuntimeState(backup: backup)
        var screens = Self.screens(state, backup, lastPressed: PresetAddress(bank: 0, preset: 1), expression: 64)
        #expect(screens[0].center == [[.text("GLOBAL PEDALS")]])
        #expect(screens[1].center == [[.icon("house.fill"), .text(" HOME")]])
        #expect(screens[2].center == [[.text("EXP 1: 50%")], [.text("B001 PG1")]])
        state.bank = 2
        state.page = 1
        screens = Self.screens(state, backup, expression: 127)
        #expect(screens[0].center == [])
        #expect(screens[2].center == [[.text("EXP 1: 100%")], [.text("B003 PG2")]])
    }

    @Test("The center band falls back to the short name when the long name is empty")
    func shortNameFallback() throws {
        let backup = try Fixture.backup()
        let state = RuntimeState(backup: backup)
        // Every named preset of the fixture has a long name. HOME stored preset 6 is "EMPTY" with none.
        let screens = Self.screens(state, backup, lastPressed: PresetAddress(bank: 0, preset: 6))
        #expect(backup.banks[0].presets[6].longName.isEmpty)
        #expect(screens[0].center == [[.text("EMPTY")]])
    }

    @Test("A bank with colors off shows white on black")
    func colorsOff() throws {
        let backup = try Importer.load(try Fixture.mutated([.setBool("/data/bankArray/0/isColorEnabled", false)]))
        let band = Self.screens(RuntimeState(backup: backup), backup)[1].bottom
        #expect(band.text == Self.white)
        #expect(band.background == Self.black)
        #expect(band.strip == Self.black)
    }

    @Test("V07: no band of the fixture's production banks has text and background of the same color")
    func fixtureContrast() throws {
        let backup = try Fixture.backup()
        var state = RuntimeState(backup: backup)
        for bank in backup.sortedProductionBanks {
            for page in 0..<backup.banks[bank].pageCount {
                for position in [Position.one, .two] {
                    state.bank = bank
                    state.page = page
                    state.positions[bank] = state.positions[bank].map { _ in position }
                    for screen in Self.screens(state, backup) {
                        #expect(screen.top.text != screen.top.background)
                        #expect(screen.bottom.text != screen.bottom.background)
                    }
                }
            }
        }
    }

    @Test("V07: same text and background draws white text, or black text on white", arguments: [
        (0, 0, 7), (7, 7, 0), (0, 64, 7), (126, 126, 7),
    ])
    func contrastFallback(_ text: Int, _ background: Int, _ expected: Int) throws {
        let home = "/data/bankArray/0/presetArray/0"
        let backup = try Importer.load(try Fixture.mutated([
            .set("\(home)/nameColor", text), .set("\(home)/backgroundColor", background),
        ]))
        let band = Self.screens(RuntimeState(backup: backup), backup)[0].bottom
        #expect(band.text == Palette.color(expected))
        #expect(band.background == Palette.color(background))
    }

    @Test("Spec 6.1: PEDALS page 2 shows stored G to L on physical A to F")
    func secondPage() throws {
        let backup = try Fixture.backup()
        var state = RuntimeState(backup: backup)
        state.bank = 2
        state.page = 1
        let screens = Self.screens(state, backup)
        #expect(screens.map(\.bottom.address.preset) == [6, 7, 8])
        #expect(screens.map(\.top.address.preset) == [9, 10, 11])
        #expect(screens[2].bottom.parts == [.icon("chevron.right.2"), .text(" PAGE+")])
    }

    @Test("Position 2 with an empty toggle name falls back to the short name")
    func emptyToggleName() throws {
        let backup = try Fixture.backup()
        var state = RuntimeState(backup: backup)
        state.bank = 2
        // PEDALS C, "\\, PAGE+", has no toggle name.
        state[position: PresetAddress(bank: 2, preset: 2)] = .two
        #expect(Self.screens(state, backup)[2].bottom.parts == [.icon("chevron.right.2"), .text(" PAGE+")])
    }
}
