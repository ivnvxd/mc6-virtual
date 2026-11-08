/// Plain text for one MIDI output, for the Sent strip and the Log window (V12).
public enum MidiText {
    /// "ch 3  CC 20 = 127", "ch 1  PC 5" or "ch 2  Note On 60 = 100". The importer produces only these, so any other
    /// message, and a message that is too short, shows its bytes in hex.
    public static func describe(_ bytes: [UInt8]) -> String {
        guard let status = bytes.first else { return "" }
        let channel = Int(status & 0x0F) + 1
        switch status & 0xF0 {
        case 0xB0 where bytes.count >= 3: return "ch \(channel)  CC \(bytes[1]) = \(bytes[2])"
        case 0xC0 where bytes.count >= 2: return "ch \(channel)  PC \(bytes[1])"
        case 0x90 where bytes.count >= 3: return "ch \(channel)  Note On \(bytes[1]) = \(bytes[2])"
        case 0x80 where bytes.count >= 3: return "ch \(channel)  Note Off \(bytes[1]) = \(bytes[2])"
        default: return hex(bytes)
        }
    }

    /// "B0 14 7F".
    public static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
