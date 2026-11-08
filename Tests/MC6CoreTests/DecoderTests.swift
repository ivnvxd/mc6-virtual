import Testing
@testable import MC6Core

/// Decodes one switch message in the given bank. Expected values come from spec section 7.
private func decode(t: Int, c: Int = 1, _ data: [Int], bank: Int = 0) throws -> (Command, [ImportNote]) {
    var notes: [ImportNote] = []
    let raw = RawMessage(data: data + Array(repeating: 0, count: 18 - data.count), m: 0, c: c, t: t, a: 2, tg: 2)
    let op = try decodeSwitchCommand(raw, bank: bank, pointer: "/x", notes: &notes)
    return (op, notes)
}

private func bits(_ indices: Int...) -> UInt32 { indices.reduce(0) { $0 | 1 << UInt32($1) } }

@Suite struct DecoderTests {
    @Test("Bank Jump [1,0,6] goes to bank 1 page 1")
    func bankJumpPage1() throws {
        #expect(try decode(t: 13, [1, 0, 6]).0 == .bankJump(.bank(1, page: 0), enter: true))
    }

    @Test("Bank Jump [1,0,7] goes to bank 1 page 2")
    func bankJumpPage2() throws {
        #expect(try decode(t: 13, [1, 0, 7]).0 == .bankJump(.bank(1, page: 1), enter: true))
    }

    /// SEMANTICS.md: page index `(d2&1) | ((d2>>3)&1)<<1`. Bits 1 and 2 (Enter, Exit) do not change the page.
    /// 14 and 15 are pages 3 and 4 with Enter and Exit on. V21: bit 1 runs the On Enter Bank messages.
    @Test("Bank Jump d2 selects pages 1 to 4, and bit 1 runs the On Enter Bank messages",
          arguments: zip([0, 1, 8, 9, 6, 7, 14, 15, 2, 4], [(page: 0, enter: false), (1, false), (2, false), (3, false), (0, true), (1, true), (2, true), (3, true), (0, true), (0, false)] as [(page: Int, enter: Bool)]))
    func bankJumpPages(d2: Int, expected: (page: Int, enter: Bool)) throws {
        #expect(try decode(t: 13, [1, 0, d2]).0 == .bankJump(.bank(1, page: expected.page), enter: expected.enter))
    }

    @Test("Bank Jump [0,126,6] goes to the last bank and page")
    func bankJumpBack() throws {
        #expect(try decode(t: 13, [0, 126, 6]).0 == .bankJump(.lastBankAndPage, enter: true))
        #expect(try decode(t: 13, [0, 127, 0]).0 == .bankJump(.lastBank, enter: false))
        #expect(try decode(t: 13, [0, 127, 2]).0 == .bankJump(.lastBank, enter: true))
        // V25: 125 is "Last used Bank / Page or Page".
        #expect(try decode(t: 13, [0, 125, 6]).0 == .bankJump(.previousPlace, enter: true))
    }

    /// The editor: messages 1 to 4 are bits 0 to 3 of data[5], 5 to 11 data[4], 12 to 18 data[3], 19 to 25 data[2],
    /// and 26 to 32 data[1].
    @Test("V26: Trigger Messages reads the preset from data[0] and messages 1 to 32 from data[5] to data[1]")
    func triggerMessages() throws {
        let slots = [0, 3, 4, 11, 18, 25, 31].reduce(UInt32(0)) { $0 | 1 << UInt32($1) }
        #expect(try decode(t: 42, [3, 1 | 64, 1, 1, 1, 1 | 8]).0 == .triggerMessages(preset: 3, slots: slots))
        let preset = #expect(throws: ImportProblem.self) { try decode(t: 42, [24, 0, 0, 0, 0, 1]) }
        #expect(preset?.pointer == "/x/data/0")
        let bits = #expect(throws: ImportProblem.self) { try decode(t: 42, [3, 0, 0, 0, 0, 16]) }
        #expect(bits?.pointer == "/x/data/5")
    }

    @Test("V25: Bank Up (t=10) and Bank Down (t=11) have no parameters")
    func bankSteps() throws {
        #expect(try decode(t: 10, []).0 == .bankStep(up: true))
        #expect(try decode(t: 11, [5, 9]).0 == .bankStep(up: false))
    }

    @Test("Set Toggle [0,96,6] c1 sets M N P Q to Position 1")
    func setToggleDisengage() throws {
        #expect(try decode(t: 15, c: 1, [0, 96, 6]).0 == .setToggle(.one, mask: bits(12, 13, 15, 16)))
    }

    @Test("Set Toggle [0,32,0] c2 sets M to Position 2")
    func setToggleEngage() throws {
        #expect(try decode(t: 15, c: 2, [0, 32, 0]).0 == .setToggle(.two, mask: bits(12)))
    }

    /// Spec 7: mask24 = (d0&127) | (d1&127)<<7 | (d2&127)<<14 | (d3&7)<<21. The data puts one bit in its byte.
    /// SEMANTICS.md: operation = (c - 1) & 15. c=17 would wrap to operation 0, and Int.min overflowed `c - 1`.
    /// SEMANTICS.md: `c - 1` is the operation. 0 Disengage, 1 Engage, 2 Toggle and 6 Set Toggle run; the Shift operations
    /// and the beta operations do not.
    @Test("V29: Set Toggle c=3 toggles and c=7 sets the checked presets to Position 2 and the others to Position 1")
    func setToggleOperations() throws {
        #expect(try decode(t: 15, c: 3, [0, 32, 0]).0 == .flipToggle(mask: bits(12)))
        #expect(try decode(t: 15, c: 7, [0, 32, 0]).0 == .setToggleOnly(mask: bits(12)))
    }

    @Test("Set Toggle with another c is skipped at c, not a crash", arguments: [0, 4, 5, 6, 8, 9, 10, 17, -1, Int.min, Int.max])
    func setToggleUnsupportedC(_ c: Int) {
        let error = #expect(throws: ImportProblem.self) { try decode(t: 15, c: c, [0, 32, 0]) }
        #expect(error?.pointer == "/x/c")
    }

    @Test("Set Toggle decodes each of the 24 preset bits", arguments: 0..<24)
    func setToggleBit(_ bit: Int) throws {
        var data = [0, 0, 0, 0]
        data[bit / 7] = 1 << (bit % 7)
        #expect(try decode(t: 15, c: 2, data).0 == .setToggle(.two, mask: 1 << UInt32(bit)))
    }

    /// Spec 7: mask32 = (d0>>2)<<27 | (d1&127)<<20 | (d2&127)<<13 | (d3&127)<<6 | (d4&63), input d0&3.
    @Test("Select Expression decodes each of the 32 message bits on each of the 4 inputs", arguments: 0..<32)
    func selectExpressionBit(_ bit: Int) throws {
        for input in 0..<4 {
            var data = [input, 0, 0, 0, 0]
            switch bit {
            case 0..<6: data[4] = 1 << bit
            case 6..<13: data[3] = 1 << (bit - 6)
            case 13..<20: data[2] = 1 << (bit - 13)
            case 20..<27: data[1] = 1 << (bit - 20)
            default: data[0] |= 1 << (bit - 27 + 2)
            }
            #expect(try decode(t: 17, data).0 == .selectExpression(input: input, mask: 1 << UInt32(bit)))
        }
    }

    @Test("Select Expression [0,0,17,8,34] selects messages 1 5 9 13 17 of input 0")
    func selectExpression() throws {
        #expect(try decode(t: 17, [0, 0, 17, 8, 34]).0 == .selectExpression(input: 0, mask: bits(1, 5, 9, 13, 17)))
        #expect(try decode(t: 17, [0, 0, 0, 0, 1]).0 == .selectExpression(input: 0, mask: bits(0)))
    }

    @Test("Select Expression sets mask bit 31 from d0 bit 6")
    func selectExpressionBit31() throws {
        #expect(try decode(t: 17, [64 | 1, 0, 0, 0, 0]).0 == .selectExpression(input: 1, mask: 0x8000_0000))
    }

    @Test("Engage [2,20,2] calls bank 2 preset U with Release")
    func engageOtherBank() throws {
        #expect(try decode(t: 27, [2, 20, 2]).0 == .engage(bank: 2, preset: 20, action: 2))
    }

    @Test("Engage [5,86,2,7] in bank 9 calls W of bank 9 and notes d3")
    func engageCurrentBank() throws {
        let (op, notes) = try decode(t: 27, [5, 86, 2, 7], bank: 9)
        #expect(op == .engage(bank: 9, preset: 22, action: 2))
        #expect(notes.map(\.pointer) == ["/x/data/3"])
    }

    @Test("Engage [7,86,2] in bank 8 calls W of bank 8")
    func engageCurrentBankIgnoresStoredBank() throws {
        let (op, notes) = try decode(t: 27, [7, 86, 2], bank: 8)
        #expect(op == .engage(bank: 8, preset: 22, action: 2))
        #expect(notes.isEmpty)
    }

    @Test("Engage with c other than 1 decodes and notes c")
    func engageChannelNote() throws {
        let (op, notes) = try decode(t: 27, c: 7, [2, 20, 2])
        #expect(op == .engage(bank: 2, preset: 20, action: 2))
        #expect(notes.map(\.pointer) == ["/x/c"])
    }

    @Test("V20: Engage [2,1,0] calls bank 2 preset B with No Action")
    func engageNoAction() throws {
        #expect(try decode(t: 27, [2, 1, 0]).0 == .engage(bank: 2, preset: 1, action: 0))
    }

    @Test("Engage with target action 10 is skipped at data/2")
    func engageAction10() {
        let problem = #expect(throws: ImportProblem.self) { try decode(t: 27, [2, 1, 10]) }
        #expect(problem?.pointer == "/x/data/2")
    }

    @Test("PC 3 on channel 2 gives [193,3]")
    func programChange() throws {
        #expect(try decode(t: 1, c: 2, [3]).0 == .midi([193, 3]))
    }

    @Test("V28: PC send type 0 sends one PC on its channel, and 127 sends it on channels 1 to 16")
    func programChangeSendTypes() throws {
        #expect(try decode(t: 1, c: 2, [3, 0, 0]).0 == .midi([0xC1, 3]))
        #expect(try decode(t: 1, c: 5, [3, 0, 127]).0 == .midiList((0..<16).map { [0xC0 | UInt8($0), 3] }))
    }

    @Test("V28: the last-sent PC send types and unknown send types are skipped at data/2", arguments: [122, 126, 1])
    func programChangeSendTypeSkipped(sendType: Int) {
        let problem = #expect(throws: ImportProblem.self) { try decode(t: 1, c: 1, [3, 0, sendType]) }
        #expect(problem?.pointer == "/x/data/2")
    }

    /// The editor: channels 1 to 7 in data[1], 8 to 14 in data[2], 15 and 16 in bits 0 and 1 of `c - 1`.
    @Test("V28: PC Multi Channel sends the PC on each checked channel, in channel order")
    func programChangeMultiChannel() throws {
        #expect(try decode(t: 34, c: 4, [9, 1, 1]).0 == .midiList([[0xC0, 9], [0xC7, 9], [0xCE, 9], [0xCF, 9]]))
        #expect(try decode(t: 34, c: 1, [9]).0 == .midiList([]))
        let problem = #expect(throws: ImportProblem.self) { try decode(t: 34, c: 5, [9, 1]) }
        #expect(problem?.pointer == "/x/c")
    }

    @Test("V28: Note On and Note Off send note and velocity; Note Off with All Notes sends notes 0 to 127")
    func notes() throws {
        #expect(try decode(t: 3, c: 2, [60, 100]).0 == .midi([0x91, 60, 100]))
        #expect(try decode(t: 4, c: 1, [60, 0]).0 == .midi([0x80, 60, 0]))
        #expect(try decode(t: 4, c: 1, [60, 64, 1]).0 == .midiList((0..<128).map { [0x80, UInt8($0), 64] }))
        let allNotes = #expect(throws: ImportProblem.self) { try decode(t: 4, c: 1, [60, 64, 2]) }
        #expect(allNotes?.pointer == "/x/data/2")
        let channel = #expect(throws: ImportProblem.self) { try decode(t: 3, c: 17, [60, 100]) }
        #expect(channel?.pointer == "/x/c")
    }

    @Test("V29: Real Time 1, 2 and 3 send Start, Stop and Continue; 0 (Nothing) sends nothing; 4 is skipped at data/0")
    func realTime() throws {
        #expect(try decode(t: 5, [1]).0 == .midi([0xFA]))
        #expect(try decode(t: 5, [2]).0 == .midi([0xFC]))
        #expect(try decode(t: 5, [3]).0 == .midi([0xFB]))
        #expect(try decode(t: 5, [0]).0 == .midiList([]))
        let problem = #expect(throws: ImportProblem.self) { try decode(t: 5, [4]) }
        #expect(problem?.pointer == "/x/data/0")
    }

    /// The editor: Song Position beats are `data[0] << 7 | data[1]`. MIDI sends the low 7 bits first.
    @Test("V29: Song Position [2,5] sends beat 261 as F2 05 02, and Song Select [7] sends F3 07")
    func songMessages() throws {
        #expect(try decode(t: 25, [2, 5]).0 == .midi([0xF2, 5, 2]))
        #expect(try decode(t: 29, [7]).0 == .midi([0xF3, 7]))
    }

    @Test("CC 60=107 on channel 1 gives [176,60,107]")
    func controlChange() throws {
        #expect(try decode(t: 2, c: 1, [60, 107, 6]).0 == .midi([176, 60, 107]))
    }

    @Test("Delay 5 gives 50 ms, and a non-zero d1 is a note")
    func delay() throws {
        #expect(try decode(t: 23, [5]).0 == .delay(ms: 50))
        let (op, notes) = try decode(t: 23, [5, 127])
        #expect(op == .delay(ms: 50))
        #expect(notes.map(\.pointer) == ["/x/data/1"])
    }

    @Test("Utility [6,4,2] sets the message scroll group size to 2")
    func utility() throws {
        #expect(try decode(t: 36, [6, 4, 2]).0 == .scrollGroupSize(2))
    }

    @Test("V27: Utility 1 clears all toggles, and Utility 2 and 3 step the BPM by +1 and -1")
    func utilitySimple() throws {
        #expect(try decode(t: 36, [1]).0 == .clearToggles)
        #expect(try decode(t: 36, [2]).0 == .tempoStep(1))
        #expect(try decode(t: 36, [3]).0 == .tempoStep(-1))
    }

    @Test("V23: Utility 0 [0,10,0] cues message 1 of preset K, and [0,127,127] resets the frame preset")
    func utilityScrollCounter() throws {
        #expect(try decode(t: 36, [0, 10, 0]).0 == .scrollCounter(preset: 10, slot: 0))
        #expect(try decode(t: 36, [0, 127, 127]).0 == .scrollCounter(preset: nil, slot: nil))
    }

    @Test("V23: Utility 0 with preset 24 to 126 is skipped at data/1, and with message 32 to 126 at data/2",
          arguments: [([0, 24, 0], "/x/data/1"), ([0, 126, 0], "/x/data/1"), ([0, 10, 32], "/x/data/2"), ([0, 10, 126], "/x/data/2")])
    func utilityScrollCounterSkipped(data: [Int], pointer: String) {
        let problem = #expect(throws: ImportProblem.self) { try decode(t: 36, data) }
        #expect(problem?.pointer == pointer)
    }

    @Test("V24: Utility 8 [8,0,7,8] sets background 0, text 7 and strip 8 of the frame preset")
    func utilityCurrentColors() throws {
        let (command, notes) = try decode(t: 36, [8, 0, 7, 8])
        #expect(command == .presetColors(preset: nil, PresetColors(strip: 8, text: 7, background: 0)))
        #expect(notes.isEmpty)
    }

    @Test("V24: Utility 9 [9,9,7,9,5] sets the colors of preset F of the frame bank")
    func utilitySelectedColors() throws {
        #expect(try decode(t: 36, [9, 9, 7, 9, 5]).0 == .presetColors(preset: 5, PresetColors(strip: 9, text: 7, background: 9)))
    }

    @Test("Utility 9 with preset 24 is skipped at data/4, and Utility 5 at data/0")
    func utilityColorsSkipped() {
        let preset = #expect(throws: ImportProblem.self) { try decode(t: 36, [9, 9, 7, 9, 24]) }
        #expect(preset?.pointer == "/x/data/4")
        let type = #expect(throws: ImportProblem.self) { try decode(t: 36, [5, 9, 7]) }
        #expect(type?.pointer == "/x/data/0")
    }

    @Test("V27: Utility 7 [7,9,7] sets background 9 and text 7 of the bank name; a color from 65 to 92 gets the remark")
    func utilityBankColors() throws {
        #expect(try decode(t: 36, [7, 9, 7]).0 == .bankColors(NameColors(text: 7, background: 9)))
        #expect(try decode(t: 36, [7, 9, 70]).1.map(\.pointer) == ["/x/data/2"])
    }

    @Test("V06: a Utility color from 65 to 92 gets the unnamed-color remark")
    func utilityUnnamedColor() throws {
        let notes = try decode(t: 36, [8, 70, 7, 8]).1
        #expect(notes.map(\.pointer) == ["/x/data/1"])
        #expect(notes.map(\.kind) == [.unnamedColor])
    }

    @Test("Rename keeps only bytes 32 to 127")
    func rename() throws {
        #expect(try decode(t: 44, [72, 0, 73, 10, 32, 92, 64]).0 == .rename(.current, "HI \\@"))
    }

    /// SEMANTICS.md section 4: `selector = c - 1`, bit 0 restores, bits 1 to 3 name the kind (0 current, 1 short,
    /// 2 toggle, 3 Shift, 4 long).
    @Test("V24: Rename c=1 to 10 writes or restores the current, short, toggle or long name",
          arguments: zip([1, 2, 3, 4, 5, 6, 9, 10], [
              Command.rename(.current, "HI"), .rename(.current, nil), .rename(.short, "HI"), .rename(.short, nil),
              .rename(.toggle, "HI"), .rename(.toggle, nil), .rename(.long, "HI"), .rename(.long, nil),
          ]))
    func renameKinds(c: Int, command: Command) throws {
        #expect(try decode(t: 44, c: c, [72, 73]).0 == command)
    }

    @Test("V24: Rename of the Shift name and Rename types outside 1 to 10 are skipped at c", arguments: [7, 8, 0, 11, Int.min, Int.max])
    func renameSkipped(c: Int) {
        let problem = #expect(throws: ImportProblem.self) { try decode(t: 44, c: c, [72, 73]) }
        #expect(problem?.pointer == "/x/c")
    }

    @Test("Toggle Page, Toggle Preset and Tap")
    func simpleOperations() throws {
        #expect(try decode(t: 14, [1]).0 == .togglePage(.up))
        #expect(try decode(t: 14, [2]).0 == .togglePage(.down))
        #expect(try decode(t: 14, [3]).0 == .togglePage(.go(0)))
        #expect(try decode(t: 14, [6]).0 == .togglePage(.go(3)))
        #expect(try decode(t: 22, []).0 == .togglePreset)
        #expect(try decode(t: 24, []).0 == .clockTap)
    }

    @Test("Expression t=1 decodes as a linear CC, not a PC")
    func expression() throws {
        let raw = RawMessage(data: [70, 0, 127] + Array(repeating: 0, count: 15), m: 0, c: 3, t: 1, a: 0, tg: 2)
        #expect(try decodeExpressionCommand(raw, pointer: "/x") == .expression(channel: 3, number: 70, min: 0, max: 127))
    }
}
