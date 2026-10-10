import CoreMIDI
import MC6Core

/// A CoreMIDI call that returned a non-zero status.
public struct MIDIError: Error, CustomStringConvertible {
    public let call: String
    public let status: OSStatus

    public var description: String { "\(call) failed with OSStatus \(status)" }
}

/// Two CoreMIDI virtual sources, "MC6 Virtual 1" and "MC6 Virtual 2", that replace USB Device Port 1 and 2
/// of the MC6 Pro (spec 8.2, 8.3). Each source keeps the same unique ID across launches, so hosts such as
/// Ableton Live remember their settings.
@MainActor
public final class VirtualPorts: MidiSink {
    public static let names = ["MC6 Virtual 1", "MC6 Virtual 2"]
    /// Fixed IDs: "MC6" followed by the port number.
    public static let uniqueIDs: [MIDIUniqueID] = [0x4D43_3601, 0x4D43_3602]

    /// The sources for `.port1` and `.port2`, in that order.
    public let sources: [MIDIEndpointRef]
    private let client: MIDIClientRef

    public init() throws {
        var client = MIDIClientRef()
        try check(MIDIClientCreate("MC6 Virtual" as CFString, nil, nil, &client), "MIDIClientCreate")
        var sources: [MIDIEndpointRef] = []
        do {
            for (name, id) in zip(Self.names, Self.uniqueIDs) {
                var source = MIDIEndpointRef()
                try check(MIDISourceCreate(client, name as CFString, &source), "MIDISourceCreate")
                sources.append(source)
                try check(MIDIObjectSetIntegerProperty(source, kMIDIPropertyUniqueID, id), "MIDIObjectSetIntegerProperty")
            }
        } catch {
            sources.forEach { MIDIEndpointDispose($0) }
            MIDIClientDispose(client)
            throw error
        }
        self.client = client
        self.sources = sources
    }

    deinit {
        sources.forEach { MIDIEndpointDispose($0) }
        MIDIClientDispose(client)
    }

    /// Sends one message on each selected port, timestamped now.
    public func send(_ bytes: [UInt8], to ports: Ports) throws {
        for (port, source) in zip([Ports.port1, .port2], sources) where ports.contains(port) {
            try withUnsafeTemporaryAllocation(byteCount: 256, alignment: 4) { buffer in
                let list = buffer.baseAddress!.assumingMemoryBound(to: MIDIPacketList.self)
                let packet = MIDIPacketListInit(list)
                // A PC or CC message always fits the buffer.
                MIDIPacketListAdd(list, buffer.count, packet, 0, bytes.count, bytes)
                try check(MIDIReceived(source, list), "MIDIReceived")
            }
        }
    }
}

private func check(_ status: OSStatus, _ call: String) throws {
    guard status == noErr else { throw MIDIError(call: call, status: status) }
}
