/// A switch preset: bank ID and stored preset index (0 = A).
public struct PresetAddress: Hashable, Sendable {
    public let bank: Int
    public let preset: Int

    public init(bank: Int, preset: Int) {
        self.bank = bank
        self.preset = preset
    }
}

/// A temporary name of one kind of one switch preset (V24).
public struct NameKey: Hashable, Sendable {
    public let address: PresetAddress
    public let kind: NameKind

    public init(address: PresetAddress, kind: NameKind) {
        self.address = address
        self.kind = kind
    }
}

/// The emulator state that the engine changes. The start values follow U12 and U06.
public struct RuntimeState: Sendable, Equatable {
    /// The shown bank. U12: bank 0.
    public var bank = 0
    /// The shown page index (0 = page 1). U12: page 1.
    public var page = 0
    /// U04: the place shown before the last jump to a different bank, where BACK goes. U12: none at start.
    public var lastPlace: Place?
    /// The position of every switch preset, indexed `[bank][preset]`. U12: all Position 1.
    public var positions: [[Position]]
    /// The selected messages of expression inputs 1 to 4; bit 0 is message 0. U06: message 0 only.
    public var expressionMasks: [UInt32] = Array(repeating: 1, count: 4)
    /// Temporary names set by Rename (V24). U09: they last until reset or re-import.
    public var names: [NameKey: String] = [:]
    /// Temporary colors set by Utility 8 and 9, for both positions (V24). U09: they last until reset or re-import.
    public var colors: [PresetAddress: PresetColors] = [:]
    /// V21: the banks whose once-only On Enter Bank messages were queued since the last power-on (V22).
    public var enteredOnce: Set<Int> = []
    /// Message scroll state of the presets with `toMsgScroll`. U07: it survives bank changes.
    public var messageScroll: [PresetAddress: MessageScroll] = [:]

    public init(backup: Backup) {
        positions = backup.banks.map { Array(repeating: .one, count: $0.presets.count) }
    }

    /// The temporary name of `kind`, or `stored` when there is none.
    public func name(_ kind: NameKind, of address: PresetAddress, stored: String) -> String {
        names[NameKey(address: address, kind: kind)] ?? stored
    }

    public subscript(position address: PresetAddress) -> Position {
        get { positions[address.bank][address.preset] }
        set { positions[address.bank][address.preset] = newValue }
    }
}
