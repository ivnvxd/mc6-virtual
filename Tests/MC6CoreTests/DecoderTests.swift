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
