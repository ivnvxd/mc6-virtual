import Testing
@testable import MC6Core

/// The words for Dry Run, Live and Error in the window.
@Suite(.needsSpec) struct ModeTextTests {
    static let pointer = "/data/bankArray/0/presetArray/0/msgArray/1"
    static let place = "Bank 1 HOME, A TONES, message 2"

    @Test("The fault text names the preset and the message, and says what the receiving app may have", arguments: [
        (EngineFault.depthLimit(pointer: pointer), "goes deeper than 8 nested presets"),
        (EngineFault.budgetLimit(pointer: pointer), "one press ran more than 512 messages"),
        (EngineFault.sendFailed(pointer: pointer, reason: "port closed"), "could not be sent: port closed"),
    ])
    func faultText(_ fault: EngineFault, _ phrase: String) throws {
        let text = ModeText.fault(fault, in: try Fixture.backup())
        #expect(text.hasPrefix("Stopped at \(Self.place): "))
        #expect(text.contains(phrase))
        #expect(text.hasSuffix("Messages sent before it cannot be taken back."))
    }

    static func output(live: Bool) -> LogEntry {
        LogEntry(time: .zero, event: .output(bytes: [0xB0, 1, 2], ports: .port1, pointer: pointer, live: live))
    }

    @Test("The Sent header: empty, Live, and Dry Run, which says that nothing went to the ports")
    func sentHeader() {
        #expect(ModeText.sentHeader([], total: 0) == "Sent")
        #expect(ModeText.sentHeader([Self.output(live: true), Self.output(live: true)], total: 2) == "Sent (2)")
        #expect(ModeText.sentHeader([Self.output(live: false)], total: 1) == "Dry Run: 1 message, nothing went to the MIDI ports")
        #expect(ModeText.sentHeader([Self.output(live: false), Self.output(live: false)], total: 2)
            == "Dry Run: 2 messages, nothing went to the MIDI ports")
    }

    @Test("A group longer than the strip counts all its outputs")
    func sentHeaderTotal() {
        #expect(ModeText.sentHeader([Self.output(live: true)], total: 300) == "Sent (300)")
    }

    @Test("The mode label next to the activity light")
    func labels() {
        #expect(ModeText.label(.dryRun) == "DRY RUN")
        #expect(ModeText.label(.live) == "LIVE")
        #expect(ModeText.label(.error(.budgetLimit(pointer: ""))) == "ERROR")
    }
}
