import Foundation
import MC6Core

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

    /// A file of the spec package's `inventory` directory.
    static func inventory(_ name: String) throws -> Data {
        let url = url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("inventory/\(name)")
        guard let data = FileManager.default.contents(atPath: url.path) else { throw MissingFile(path: url.path) }
        return data
    }

    static let sha256 = "08f82cf27afcd57cf3ec8044643138f5966f616d7c00e5e1286fd17704075503"

    private static let cached: Result<Data, MissingFile> = {
        guard let data = FileManager.default.contents(atPath: url.path) else {
            return .failure(MissingFile(path: url.path))
        }
        return .success(data)
    }()

    /// The raw fixture bytes. Throws a descriptive error when the file is missing.
    static func data() throws -> Data { try cached.get() }

    private static let cachedBackup: Result<Backup, any Error> = Result { try Importer.load(try data()) }

    /// The fixture imported once.
    static func backup() throws -> Backup { try cachedBackup.get() }

    /// One change to an in-memory copy of the fixture JSON, addressed by JSON Pointer.
    enum Edit: Sendable {
        case set(String, Int)
        case setBool(String, Bool)
        case setString(String, String)
        case removeLast(String)
        /// Removes the key that the pointer names from its object.
        case removeKey(String)
    }

    /// A copy of the fixture JSON with the edits applied.
    static func mutated(_ edits: [Edit]) throws -> Data {
        let root = try JSONSerialization.jsonObject(with: data(), options: .mutableContainers)
        for edit in edits {
            switch edit {
            case .set(let pointer, let value): try assign(value as NSNumber, at: pointer, in: root)
            case .setBool(let pointer, let value): try assign(value as NSNumber, at: pointer, in: root)
            case .setString(let pointer, let value): try assign(value as NSString, at: pointer, in: root)
            case .removeLast(let pointer):
                (try resolve(pointer.split(separator: "/").map(String.init), in: root) as! NSMutableArray).removeLastObject()
            case .removeKey(let pointer):
                var tokens = pointer.split(separator: "/").map(String.init)
                let key = tokens.removeLast()
                (try resolve(tokens, in: root) as! NSMutableDictionary).removeObject(forKey: key)
            }
        }
        return try JSONSerialization.data(withJSONObject: root)
    }

    struct BadPointer: Error { let token: String }

    /// The value at the tokens of a JSON Pointer.
    static func resolve(_ tokens: [String], in root: Any) throws -> Any {
        try tokens.reduce(root) { node, token in
            if let dict = node as? NSDictionary, let child = dict[token] { return child }
            if let array = node as? NSArray, let index = Int(token), index < array.count { return array[index] }
            throw BadPointer(token: token)
        }
    }

    private static func assign(_ value: Any, at pointer: String, in root: Any) throws {
        var tokens = pointer.split(separator: "/").map(String.init)
        let last = tokens.removeLast()
        switch try resolve(tokens, in: root) {
        case let dict as NSMutableDictionary: dict[last] = value
        case let array as NSMutableArray: array[Int(last)!] = value
        default: throw BadPointer(token: last)
        }
    }
}
