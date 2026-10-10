import MC6Core

/// A `Scheduler` whose time moves only through `advance(by:)`.
@MainActor
final class FakeScheduler: Scheduler {
    private struct Entry {
        let wakeup: Wakeup
        let due: Duration
        let action: @MainActor () -> Void
    }

    private(set) var now: Duration = .zero
    private var entries: [Entry] = []
    private var nextID = 0

    @discardableResult
    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> Wakeup {
        let wakeup = Wakeup(id: nextID)
        nextID += 1
        entries.append(Entry(wakeup: wakeup, due: now + delay, action: action))
        return wakeup
    }

    func cancel(_ wakeup: Wakeup) {
        entries.removeAll { $0.wakeup == wakeup }
    }

    /// Fires every wake-up due within `duration` in time order, ties in scheduling order,
    /// including wake-ups scheduled by the ones that fire. `now` is each wake-up's due time while it runs.
    func advance(by duration: Duration) {
        let end = now + duration
        while let index = entries.indices.filter({ entries[$0].due <= end }).min(by: { entries[$0].due < entries[$1].due }) {
            let entry = entries.remove(at: index)
            now = entry.due
            entry.action()
        }
        now = end
    }
}
