import Foundation

/// The acceptance fixture from the spec package, read once and cached.
enum Fixture {
    struct MissingFile: Error, CustomStringConvertible {
        let path: String
        var description: String {
            "Fixture not found at \(path). The spec package must sit next to this repository as mc6-virtual-spec."
        }
    }

    /// The spec package is a sibling of the repository root.
    static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // .../Tests/MC6CoreTests/Support
        .deletingLastPathComponent()  // .../Tests/MC6CoreTests
        .deletingLastPathComponent()  // .../Tests
        .deletingLastPathComponent()  // repository root
        .deletingLastPathComponent()  // parent of the repository
        .appendingPathComponent("mc6-virtual-spec/fixtures/Morningstar_MC6PRO_All_Banks_Backup_20261009_194950.json")

    static let sha256 = "08f82cf27afcd57cf3ec8044643138f5966f616d7c00e5e1286fd17704075503"

    private static let cached: Result<Data, MissingFile> = {
        guard let data = FileManager.default.contents(atPath: url.path) else {
            return .failure(MissingFile(path: url.path))
        }
        return .success(data)
    }()

    /// The raw fixture bytes. Throws a descriptive error when the file is missing.
    static func data() throws -> Data { try cached.get() }
}
