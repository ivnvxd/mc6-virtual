import Testing
@testable import MC6Core

/// Plain text for the outputs in the Sent strip and the Log window (V12).
@Suite struct MidiTextTests {
    @Test("V12: Control Change shows channel, number and value; channels count from 1")
    func controlChange() {
        #expect(MidiText.describe([0xB2, 20, 127]) == "ch 3  CC 20 = 127")
        #expect(MidiText.describe([0xB0, 0, 0]) == "ch 1  CC 0 = 0")
        #expect(MidiText.describe([0xBF, 64, 1]) == "ch 16  CC 64 = 1")
    }

    @Test("V12: Program Change shows channel and program")
    func programChange() {
        #expect(MidiText.describe([0xC0, 5]) == "ch 1  PC 5")
        #expect(MidiText.describe([0xCF, 127]) == "ch 16  PC 127")
    }

    @Test("V12: a short message or another status shows the bytes in hex", arguments: [
        ([UInt8](), ""), ([0xB0, 20], "B0 14"), ([0xC3], "C3"), ([0x90, 60, 100], "90 3C 64"), ([0xF8], "F8"),
    ])
    func hexFallback(_ bytes: [UInt8], _ text: String) {
        #expect(MidiText.describe(bytes) == text)
    }

    @Test("V12: a switch message names the preset letter, the name without icons, and the message from 1")
    func switchSource() throws {
        let backup = try Fixture.backup()
        // PEDALS A is "\v BOOST": the icon escape drops out.
        #expect(backup.source(of: "/data/bankArray/2/presetArray/0/msgArray/0") == "A BOOST, message 1")
        #expect(backup.source(of: "/data/bankArray/0/presetArray/0/msgArray/1") == "A TONES, message 2")
        #expect(backup.source(of: "/data/bankArray/2/presetArray/23/msgArray/31")?.hasPrefix("X ") == true)
    }

    @Test("V12: an expression message names the input from 1, not the preset name")
    func expressionSource() throws {
        let backup = try Fixture.backup()
        #expect(backup.source(of: "/data/bankArray/2/expPresetArray/0/msgArray/2") == "EXP 1, message 3")
        #expect(backup.source(of: "/data/bankArray/0/expPresetArray/3/msgArray/0") == "EXP 4, message 1")
    }

    @Test("V12: another pointer has no source", arguments: [
        "", "/data/bankArray/2/presetArray/0", "/data/bankArray/128/presetArray/0/msgArray/0",
        "/data/bankArray/2/presetArray/24/msgArray/0", "/data/bankArray/2/expPresetArray/4/msgArray/0",
        "/data/bankArray/2/presetArray/0/msgArray/32", "/data/bankArray/x/presetArray/0/msgArray/0",
        "/data/bankArray/2/presetArray/0/msgArray/0/d0",
    ])
    func noSource(_ pointer: String) throws {
        #expect(try Fixture.backup().source(of: pointer) == nil)
    }
}
