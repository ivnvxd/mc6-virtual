import CoreMIDI
import MC6Core

/// A CoreMIDI call that returned a non-zero status.
public struct MIDIError: Error, CustomStringConvertible {
    public let call: String
    public let status: OSStatus

    public var description: String { "\(call) failed with OSStatus \(status)" }
}

/// Two CoreMIDI virtual sources, by default "MC6 Virtual 1" and "MC6 Virtual 2", that replace USB Device Port 1
/// and 2 of the MC6 Pro (spec 8.2, 8.3). Each source keeps the same unique ID across launches, so hosts such as
/// Ableton Live remember their settings. The names can change in Settings; the IDs never do.
@MainActor
public final class VirtualPorts: MidiSink {
    public static let defaultNames = ["MC6 Virtual 1", "MC6 Virtual 2"]
    /// Fixed IDs: "MC6" followed by the port number.
    public static let uniqueIDs: [MIDIUniqueID] = [0x4D43_3601, 0x4D43_3602]

    /// The sources for `.port1` and `.port2`, in that order.
    public let sources: [MIDIEndpointRef]
    /// The names of the sources, for error messages.
    public let names: [String]
    private let client: MIDIClientRef

    /// `names` are the names of port 1 and port 2.
    public init(names: [String] = VirtualPorts.defaultNames) throws {
        var client = MIDIClientRef()
        try check(MIDIClientCreate("MC6 Virtual" as CFString, nil, nil, &client), "MIDIClientCreate")
        var sources: [MIDIEndpointRef] = []
        do {
            for (name, id) in zip(names, Self.uniqueIDs) {
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
        self.names = names
    }

    deinit {
        sources.forEach { MIDIEndpointDispose($0) }
        MIDIClientDispose(client)
    }

    /// Sends one message on each selected port, timestamped now. An error names the port that failed.
    /// When an earlier port already got the message, the error is a `PartialSend`, so the log shows that output.
    public func send(_ bytes: [UInt8], to ports: Ports) throws {
        var delivered: Ports = []
        for (i, port) in [Ports.port1, .port2].enumerated() where ports.contains(port) {
            do {
                try withUnsafeTemporaryAllocation(byteCount: 256, alignment: 4) { buffer in
                    let list = buffer.baseAddress!.assumingMemoryBound(to: MIDIPacketList.self)
                    let packet = MIDIPacketListInit(list)
                    // A PC or CC message always fits the buffer.
                    MIDIPacketListAdd(list, buffer.count, packet, 0, bytes.count, bytes)
                    try check(MIDIReceived(sources[i], list), "MIDIReceived on \(names[i])")
                }
            } catch {
                throw delivered.isEmpty ? error : PartialSend(delivered: delivered, underlying: error)
            }
            delivered.insert(port)
        }
    }
}

private func check(_ status: OSStatus, _ call: String) throws {
    guard status == noErr else { throw MIDIError(call: call, status: status) }
}
