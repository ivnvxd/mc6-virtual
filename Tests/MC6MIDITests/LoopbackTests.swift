import CoreMIDI
import Testing
@testable import MC6Core
@testable import MC6MIDI

/// The two CoreMIDI virtual sources (spec 8.2, 8.3): names, unique IDs and an in-process loopback.
/// Serialized: each test owns the sources, and a second instance cannot take the same unique IDs.
@MainActor @Suite(.serialized) struct LoopbackTests {
    struct Received: Sendable, Equatable {
        /// 0 for "MC6 Virtual 1", 1 for "MC6 Virtual 2".
        let source: Int
        let bytes: [UInt8]
    }

    struct Timeout: Error {}

    /// Connects a test input port to both sources and streams what they send.
    final class Listener {
        private var client = MIDIClientRef()
        private var port = MIDIPortRef()
        let stream: AsyncStream<Received>

        init(_ sources: [MIDIEndpointRef]) throws {
            let (stream, continuation) = AsyncStream<Received>.makeStream()
            self.stream = stream
            #expect(MIDIClientCreate("MC6 Loopback Test" as CFString, nil, nil, &client) == noErr)
            let status = MIDIInputPortCreateWithBlock(client, "Loopback" as CFString, &port) { list, refCon in
                let source = Int(bitPattern: refCon) - 1
                for packet in list.unsafeSequence() {
                    let bytes = withUnsafeBytes(of: packet.pointee.data) { Array($0.prefix(Int(packet.pointee.length))) }
                    continuation.yield(Received(source: source, bytes: bytes))
                }
            }
            #expect(status == noErr)
            for (index, source) in sources.enumerated() {
                #expect(MIDIPortConnectSource(port, source, UnsafeMutableRawPointer(bitPattern: index + 1)) == noErr)
            }
        }

        /// The next `count` messages, or `Timeout` after `limit`.
        func next(_ count: Int, within limit: Duration = .seconds(2)) async throws -> [Received] {
            let stream = stream
            return try await withThrowingTaskGroup(of: [Received]?.self) { group in
                group.addTask {
                    var received: [Received] = []
                    for await message in stream {
                        received.append(message)
                        if received.count == count { break }
                    }
                    return received
                }
                group.addTask {
                    try await Task.sleep(for: limit)
                    return nil
                }
                defer { group.cancelAll() }
                guard let first = try await group.next(), let received = first else { throw Timeout() }
                return received
            }
        }

        deinit {
            MIDIPortDispose(port)
            MIDIClientDispose(client)
        }
    }

    @Test("The sources are named MC6 Virtual 1 and 2 and carry the stable unique IDs")
    func namesAndIDs() throws {
        let ports = try VirtualPorts()
        #expect(ports.sources.count == 2)
        for (index, source) in ports.sources.enumerated() {
            var name: Unmanaged<CFString>?
            #expect(MIDIObjectGetStringProperty(source, kMIDIPropertyName, &name) == noErr)
            #expect(name?.takeRetainedValue() as String? == ["MC6 Virtual 1", "MC6 Virtual 2"][index])
            var id: MIDIUniqueID = 0
            #expect(MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &id) == noErr)
            #expect(id == VirtualPorts.uniqueIDs[index])
        }
        #expect(VirtualPorts.uniqueIDs[0] != VirtualPorts.uniqueIDs[1])
    }

    @Test("Custom names from Settings keep the stable unique IDs")
    func customNames() throws {
        let ports = try VirtualPorts(names: ["Guitar Rig", "Looper"])
        for (index, source) in ports.sources.enumerated() {
            var name: Unmanaged<CFString>?
            #expect(MIDIObjectGetStringProperty(source, kMIDIPropertyName, &name) == noErr)
            #expect(name?.takeRetainedValue() as String? == ["Guitar Rig", "Looper"][index])
            var id: MIDIUniqueID = 0
            #expect(MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &id) == noErr)
            #expect(id == VirtualPorts.uniqueIDs[index])
        }
    }

    @Test("Bytes sent to each port arrive in-process on the matching source")
    func loopback() async throws {
        let ports = try VirtualPorts()
        let listener = try Listener(ports.sources)
        try ports.send([0xB0, 26, 127], to: .port1)
        try ports.send([0xC1, 5], to: .port2)
        try ports.send([0xB4, 51, 0], to: [.port1, .port2])
        let received = try await listener.next(4)
        #expect(received.filter { $0.source == 0 }.map(\.bytes) == [[0xB0, 26, 127], [0xB4, 51, 0]])
        #expect(received.filter { $0.source == 1 }.map(\.bytes) == [[0xC1, 5], [0xB4, 51, 0]])
    }

    @Test("Empty ports send nothing")
    func emptyPorts() async throws {
        let ports = try VirtualPorts()
        let listener = try Listener(ports.sources)
        try ports.send([0xB0, 1, 1], to: [])
        try ports.send([0xB0, 2, 2], to: .port1)
        #expect(try await listener.next(1) == [Received(source: 0, bytes: [0xB0, 2, 2])])
    }
}
