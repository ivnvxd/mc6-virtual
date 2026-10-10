import Dispatch

/// A `Scheduler` on the main queue, timed by the monotonic system clock.
@MainActor
public final class DispatchScheduler: Scheduler {
    private let start = ContinuousClock.now
    private var pending: [Wakeup: DispatchWorkItem] = [:]
    private var nextID = 0

    public init() {}

    public var now: Duration { ContinuousClock.now - start }

    @discardableResult
    public func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> Wakeup {
        let wakeup = Wakeup(id: nextID)
        nextID += 1
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.pending[wakeup] = nil
                action()
            }
        }
        pending[wakeup] = item
        let (seconds, attoseconds) = delay.components
        let nanoseconds = Int(seconds) * 1_000_000_000 + Int(attoseconds / 1_000_000_000)
        DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(nanoseconds), execute: item)
        return wakeup
    }

    public func cancel(_ wakeup: Wakeup) {
        pending.removeValue(forKey: wakeup)?.cancel()
    }
}
