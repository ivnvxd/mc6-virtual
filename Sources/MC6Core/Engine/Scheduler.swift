/// A pending wake-up, used to cancel it.
public struct Wakeup: Hashable, Sendable {
    public let id: Int
    public init(id: Int) { self.id = id }
}

/// A monotonic clock with timed wake-ups on the main actor.
/// The app uses `DispatchScheduler`; tests use a fake that advances time by hand.
@MainActor
public protocol Scheduler: AnyObject {
    /// Monotonic time since the scheduler started.
    var now: Duration { get }

    /// Runs `action` once, `delay` from now.
    @discardableResult
    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> Wakeup

    /// Drops a pending wake-up. Cancelling a wake-up that already fired does nothing.
    func cancel(_ wakeup: Wakeup)
}
