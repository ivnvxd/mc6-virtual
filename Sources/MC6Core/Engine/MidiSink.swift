/// The two virtual output ports that replace USB Device Port 1 and 2 of the MC6 Pro.
public struct Ports: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// "MC6 Virtual 1", for USB Device Port 1.
    public static let port1 = Ports(rawValue: 1 << 0)
    /// "MC6 Virtual 2", for USB Device Port 2.
    public static let port2 = Ports(rawValue: 1 << 1)

    /// Maps a channel's `sendToPort` mask (spec section 8.2): bit 1 is USB Device Port 1,
    /// bit 7 is USB Device Port 2. The other hardware ports have no virtual counterpart.
    public init(sendToPort mask: Int) {
        var ports: Ports = []
        if mask & 1 << 1 != 0 { ports.insert(.port1) }
        if mask & 1 << 7 != 0 { ports.insert(.port2) }
        self = ports
    }

    /// The port numbers for the log: 1 for "MC6 Virtual 1", 2 for "MC6 Virtual 2".
    public var numbers: [Int] {
        [(Ports.port1, 1), (Ports.port2, 2)].filter { contains($0.0) }.map(\.1)
    }
}

/// Where the engine sends MIDI. A thrown error stops output.
@MainActor
public protocol MidiSink: AnyObject {
    func send(_ bytes: [UInt8], to ports: Ports) throws
}
