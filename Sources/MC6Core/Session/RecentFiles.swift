/// The backups of File > Open Recent, newest first (V11).
public struct RecentFiles: Equatable, Sendable {
    public static let limit = 5

    public private(set) var paths: [String] = []

    /// A stored list. Duplicates and paths past the limit drop.
    public init(paths: [String] = []) {
        for path in paths where !self.paths.contains(path) && self.paths.count < Self.limit { self.paths.append(path) }
    }

    /// A backup that loaded: it moves to the top.
    public mutating func opened(_ path: String) {
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > Self.limit { paths.removeLast(paths.count - Self.limit) }
    }

    public mutating func clear() {
        paths.removeAll()
    }
}
