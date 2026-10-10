import Testing
@testable import MC6MIDI

@Test("The MIDI test target builds and links MC6MIDI")
func midiTargetBuilds() {
    #expect(String(describing: MC6MIDI.self) == "MC6MIDI")
}
