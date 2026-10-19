import Carbon.HIToolbox
import Testing
@testable import MC6Core

/// The key map, by physical key code, so the keyboard layout does not matter.
@Suite struct KeyCommandTests {
    static func command(_ key: Int, _ modifiers: KeyModifiers = [], map: KeyBindings = .defaults) -> KeyCommand? {
        KeyCommand(keyCode: UInt16(key), modifiers: modifiers, map: map)
    }

    @Test("Q W E press D E F and A S D press A B C")
    func footswitches() {
        let keys = [kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_E, kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_D]
        #expect(keys.map { Self.command($0) } == [.d, .e, .f, .a, .b, .c].map(KeyCommand.footswitch))
    }

    @Test("V01, V03: Z and X step banks, [ and ] turn pages")
    func navigation() {
        #expect(Self.command(kVK_ANSI_Z) == .navigate(.bankDown))
        #expect(Self.command(kVK_ANSI_X) == .navigate(.bankUp))
        #expect(Self.command(kVK_ANSI_LeftBracket) == .navigate(.pageDown))
        #expect(Self.command(kVK_ANSI_RightBracket) == .navigate(.pageUp))
    }

    @Test("V04: 1, 2 and 3 engage stored presets 8, 9 and 10")
    func engage() {
        #expect([kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3].map { Self.command($0) } == [8, 9, 10].map { .engage(preset: $0) })
    }

    @Test("Up and Down move the pedal; Option makes the step fine")
    func pedal() {
        #expect(Self.command(kVK_UpArrow) == .pedal(up: true, fine: false))
        #expect(Self.command(kVK_DownArrow) == .pedal(up: false, fine: false))
        #expect(Self.command(kVK_UpArrow, .option) == .pedal(up: true, fine: true))
        #expect(Self.command(kVK_DownArrow, [.option, .shift]) == .pedal(up: false, fine: true))
    }

    @Test("Command or Control on any key, and Option on a key other than an arrow, leave the key to the menus")
    func modifiers() {
        for key in [kVK_ANSI_Q, kVK_ANSI_Z, kVK_ANSI_1, kVK_UpArrow] {
            #expect(Self.command(key, .command) == nil)
            #expect(Self.command(key, .control) == nil)
        }
        #expect(Self.command(kVK_ANSI_Q, .option) == nil)
        #expect(Self.command(kVK_ANSI_Z, .option) == nil)
        #expect(Self.command(kVK_ANSI_Q, .shift) == .footswitch(.d))
    }

    @Test("Other keys do nothing")
    func otherKeys() {
        for key in [kVK_Space, kVK_ANSI_F, kVK_ANSI_4, kVK_LeftArrow, kVK_Return] { #expect(Self.command(key) == nil) }
    }

    @Test("Each command has the label of its key, for the buttons and the menus")
    func labels() {
        let map = KeyBindings.defaults
        #expect(Footswitch.allCases.map { KeyCommand.footswitch($0).label(in: map) } == ["A", "S", "D", "Q", "W", "E"])
        #expect(KeyCommand.navigate(.bankDown).label(in: map) == "Z")
        #expect(KeyCommand.navigate(.pageUp).label(in: map) == "]")
        #expect(KeyCommand.engage(preset: 10).label(in: map) == "3")
        #expect(KeyCommand.pedal(up: false, fine: false).label(in: map) == "↓")
        #expect(KeyCommand.pedal(up: true, fine: true).label(in: map) == "↑")
        #expect(KeyCommand.navigate(.select(2)).label(in: map) == "")
    }

    @Test("V15: a changed map moves the command to the new key; a cleared function has no key")
    func changedMap() {
        var map = KeyBindings.defaults
        map.assign(UInt16(kVK_F1), to: .switchA)
        map.assign(UInt16(kVK_ANSI_K), to: .pedalUp)
        map.clear(.bankUp)
        #expect(Self.command(kVK_F1, map: map) == .footswitch(.a))
        #expect(Self.command(kVK_ANSI_A, map: map) == nil)
        #expect(Self.command(kVK_ANSI_X, map: map) == nil)
        #expect(Self.command(kVK_ANSI_K, .option, map: map) == .pedal(up: true, fine: true))
        #expect(Self.command(kVK_F1, .option, map: map) == nil)
        #expect(Self.command(kVK_F1, .shift, map: map) == .footswitch(.a))
        #expect(KeyCommand.footswitch(.a).label(in: map) == "F1")
        #expect(KeyCommand.navigate(.bankUp).label(in: map) == "")
    }
}
