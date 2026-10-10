import CryptoKit
import Foundation
import Testing

@Test("The fixture matches its SHA-256")
func fixtureHash() throws {
    let digest = SHA256.hash(data: try Fixture.data())
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    #expect(hex == Fixture.sha256)
}
