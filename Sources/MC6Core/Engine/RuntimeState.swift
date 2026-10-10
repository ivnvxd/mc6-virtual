/// A switch preset: bank ID and stored preset index (0 = A).
public struct PresetAddress: Hashable, Sendable {
    public let bank: Int
    public let preset: Int

    public init(bank: Int, preset: Int) {
        self.bank = bank
        self.preset = preset
    }
}

/// The emulator state that the engine changes. The start values follow U12 and U06.
public struct RuntimeState: Sendable, Equatable {
    /// The shown bank. U12: bank 0.
    public var bank = 0
    /// The shown page index (0 = page 1). U12: page 1.
    public var page = 0
    /// The position of every switch preset, indexed `[bank][preset]`. U12: all Position 1.
    public var positions: [[Position]]
    /// The selected messages of expression inputs 1 to 4; bit 0 is message 0. U06: message 0 only.
    public var expressionMasks: [UInt32] = Array(repeating: 1, count: 4)

    public init(backup: Backup) {
        positions = backup.banks.map { Array(repeating: .one, count: $0.presets.count) }
    }

    public subscript(position address: PresetAddress) -> Position {
        get { positions[address.bank][address.preset] }
        set { positions[address.bank][address.preset] = newValue }
    }
}
