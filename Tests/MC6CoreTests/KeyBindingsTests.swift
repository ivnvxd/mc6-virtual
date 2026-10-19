import Carbon.HIToolbox
import Foundation
import Testing
@testable import MC6Core

/// The key map that Settings can change (V15). One plain key or no key per function.
@Suite struct KeyBindingsTests {
    static func code(_ key: Int) -> UInt16 { UInt16(key) }

    @Test("V15: the defaults are the v2 keys")
    func defaults() {
        let codes = KeyBindings.defaults.codes
        #expect(codes[.switchA] == Self.code(kVK_ANSI_A))
        #expect(codes[.switchB] == Self.code(kVK_ANSI_S))
        #expect(codes[.switchC] == Self.code(kVK_ANSI_D))
        #expect(codes[.switchD] == Self.code(kVK_ANSI_Q))
        #expect(codes[.switchE] == Self.code(kVK_ANSI_W))
        #expect(codes[.switchF] == Self.code(kVK_ANSI_E))
        #expect(codes[.bankDown] == Self.code(kVK_ANSI_Z))
        #expect(codes[.bankUp] == Self.code(kVK_ANSI_X))
        #expect(codes[.pageDown] == Self.code(kVK_ANSI_LeftBracket))
        #expect(codes[.pageUp] == Self.code(kVK_ANSI_RightBracket))
        #expect(codes[.engageI] == Self.code(kVK_ANSI_1))
        #expect(codes[.engageJ] == Self.code(kVK_ANSI_2))
        #expect(codes[.engageK] == Self.code(kVK_ANSI_3))
        #expect(codes[.pedalUp] == Self.code(kVK_UpArrow))
        #expect(codes[.pedalDown] == Self.code(kVK_DownArrow))
        #expect(codes.count == KeyFunction.allCases.count)
    }

    @Test("V15: a key that goes to a new function leaves its old function, which then has no key")
    func assignMoves() {
        var map = KeyBindings.defaults
        map.assign(Self.code(kVK_ANSI_Z), to: .switchA)
        #expect(map.codes[.switchA] == Self.code(kVK_ANSI_Z))
        #expect(map.codes[.bankDown] == nil)
        #expect(map.function(for: Self.code(kVK_ANSI_Z)) == .switchA)
        #expect(map.function(for: Self.code(kVK_ANSI_A)) == nil)
        // A free key changes only its own function.
        map.assign(Self.code(kVK_ANSI_J), to: .bankDown)
        #expect(map.codes[.bankDown] == Self.code(kVK_ANSI_J))
        #expect(map.codes[.switchA] == Self.code(kVK_ANSI_Z))
        // The same key again changes nothing.
        let before = map
        map.assign(Self.code(kVK_ANSI_J), to: .bankDown)
        #expect(map == before)
    }

    @Test("V15: clear leaves a function without a key")
    func clear() {
        var map = KeyBindings.defaults
        map.clear(.engageK)
        #expect(map.codes[.engageK] == nil)
        #expect(map.function(for: Self.code(kVK_ANSI_3)) == nil)
        #expect(map.codes.count == KeyFunction.allCases.count - 1)
    }

    @Test("The map survives the JSON round trip, also with a cleared function")
    func roundTrip() throws {
        var map = KeyBindings.defaults
        map.assign(Self.code(kVK_F5), to: .pageUp)
        map.clear(.engageI)
        #expect(KeyBindings.decoded(map.encoded()) == map)
        let object = try JSONSerialization.jsonObject(with: map.encoded()) as? [String: Int]
        #expect(object?["pageUp"] == kVK_F5)
        #expect(object?["engageI"] == nil)
    }

    @Test("Bad JSON, a code out of range and one code on two functions do not decode", arguments: [
        "", "[]", "{\"switchA\": \"A\"}", "{\"switchA\": 70000}", "{\"switchA\": -1}", "{\"switchA\": 0, \"switchB\": 0}",
    ])
    func badJSON(_ text: String) {
        #expect(KeyBindings.decoded(Data(text.utf8)) == nil)
    }

    @Test("A function missing from the JSON has no key, and an unknown name is skipped")
    func partialJSON() {
        let map = KeyBindings.decoded(Data("{\"switchA\": 12, \"shift\": 13}".utf8))
        #expect(map?.codes == [.switchA: Self.code(kVK_ANSI_Q)])
    }

    @Test("Key labels follow the US key positions")
    func labels() {
        let cases: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_Q, "Q"), (kVK_ANSI_M, "M"), (kVK_ANSI_1, "1"), (kVK_ANSI_0, "0"),
            (kVK_ANSI_LeftBracket, "["), (kVK_ANSI_RightBracket, "]"), (kVK_ANSI_Semicolon, ";"), (kVK_ANSI_Slash, "/"),
            (kVK_UpArrow, "↑"), (kVK_DownArrow, "↓"), (kVK_LeftArrow, "←"), (kVK_RightArrow, "→"),
            (kVK_Space, "Space"), (kVK_Return, "Return"), (kVK_Tab, "Tab"),
            (kVK_F1, "F1"), (kVK_F5, "F5"), (kVK_F12, "F12"), (kVK_ANSI_Keypad1, "Num 1"),
        ]
        for (code, label) in cases { #expect(KeyBindings.label(for: Self.code(code)) == label) }
        #expect(KeyBindings.label(for: 0x7F) == "Key 0x7F")
    }

    @Test("Each letter and digit key has its own label")
    func lettersAndDigits() {
        let labels = (0...0x32).map { KeyBindings.label(for: UInt16($0)) }.filter { $0.count == 1 }
        #expect(Set(labels).isSuperset(of: (65...90).map { String(UnicodeScalar($0)!) }))
        #expect(Set(labels).isSuperset(of: (0...9).map(String.init)))
    }
}
