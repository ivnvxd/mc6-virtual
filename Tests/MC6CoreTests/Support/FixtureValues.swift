/// Bank IDs of the fixture.
enum FixtureBank {
    static let home = 0, tones = 1, pedals = 2, looper = 3, daw = 4
    static let core = 5, vintage = 6, modern = 7, ambient = 8, nolly = 9, mayer = 10, rabea = 11, cory = 12
}

/// Control Change bytes on MIDI channel `channel` (1 to 16).
func cc(_ channel: UInt8, _ number: UInt8, _ value: UInt8) -> [UInt8] { [0xB0 | (channel - 1), number, value] }

/// Program Change bytes on MIDI channel `channel` (1 to 16).
func pc(_ channel: UInt8, _ program: UInt8) -> [UInt8] { [0xC0 | (channel - 1), program] }
