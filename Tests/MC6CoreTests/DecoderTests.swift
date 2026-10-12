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
        #expect(try decode(t: 13, [1, 0, 6]).0 == .bankJump(.bank(1, page: 0)))
    }

    @Test("Bank Jump [1,0,7] goes to bank 1 page 2")
    func bankJumpPage2() throws {
        #expect(try decode(t: 13, [1, 0, 7]).0 == .bankJump(.bank(1, page: 1)))
    }

    /// SEMANTICS.md: page index `(d2&1) | ((d2>>3)&1)<<1`. Bits 1 and 2 (Enter, Exit) do not change the page.
    /// 14 and 15 are pages 3 and 4 with Enter and Exit on.
    @Test("Bank Jump d2 selects pages 1 to 4, with and without the Enter and Exit bits",
          arguments: zip([0, 1, 8, 9, 6, 7, 14, 15, 2, 4], [0, 1, 2, 3, 0, 1, 2, 3, 0, 0]))
    func bankJumpPages(d2: Int, page: Int) throws {
        #expect(try decode(t: 13, [1, 0, d2]).0 == .bankJump(.bank(1, page: page)))
    }

    @Test("Bank Jump [0,126,6] goes to the last bank and page")
    func bankJumpBack() throws {
        #expect(try decode(t: 13, [0, 126, 6]).0 == .bankJump(.lastBankAndPage))
        #expect(try decode(t: 13, [0, 127, 0]).0 == .bankJump(.lastBank))
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
    @Test("Set Toggle with c other than 1 or 2 is a load error at c, not a crash", arguments: [0, 3, 17, -1, Int.min, Int.max])
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

    @Test("PC 3 on channel 2 gives [193,3]")
    func programChange() throws {
        #expect(try decode(t: 1, c: 2, [3]).0 == .midi([193, 3]))
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

    @Test("Rename keeps only bytes 32 to 127")
    func rename() throws {
        #expect(try decode(t: 44, [72, 0, 73, 10, 32, 92, 64]).0 == .rename("HI \\@"))
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
