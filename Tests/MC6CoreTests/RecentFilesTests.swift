import Testing
@testable import MC6Core

/// The Open Recent list (plan v2, Task 8, V11).
@Suite struct RecentFilesTests {
    @Test("V11: newest first, at most 5 paths")
    func newestFirst() {
        var recent = RecentFiles()
        for n in 1...7 { recent.opened("/b\(n).json") }
        #expect(recent.paths == ["/b7.json", "/b6.json", "/b5.json", "/b4.json", "/b3.json"])
    }

    @Test("V11: opening a listed path moves it to the top, with no duplicate")
    func moveToTop() {
        var recent = RecentFiles(paths: ["/a.json", "/b.json", "/c.json"])
        recent.opened("/c.json")
        #expect(recent.paths == ["/c.json", "/a.json", "/b.json"])
    }

    @Test("V11: a stored list with duplicates or more than 5 paths is cleaned on load")
    func cleanOnLoad() {
        let recent = RecentFiles(paths: ["/a", "/b", "/a", "/c", "/d", "/e", "/f"])
        #expect(recent.paths == ["/a", "/b", "/c", "/d", "/e"])
    }

    @Test("Clear empties the list")
    func clear() {
        var recent = RecentFiles(paths: ["/a"])
        recent.clear()
        #expect(recent.paths.isEmpty)
    }
}
