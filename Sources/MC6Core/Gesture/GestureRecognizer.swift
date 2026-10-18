/// The input that pressed a footswitch. Only the source that started a gesture ends it.
public enum InputSource: Sendable {
    case mouse, keyboard
}

/// The gesture times of the Settings window (V08). A change applies from the next first down.
public struct GestureTiming: Equatable, Sendable {
    /// U08: the default wait for a second tap, on presets with double-tap messages.
    public static let defaultDoubleTapWindow = Duration.milliseconds(300)

    /// Replaces the backup's long-press time; nil uses the backup.
    public var longPress: Duration?
    /// How long a preset with double-tap messages waits for a second tap.
    public var doubleTapWindow: Duration

    public init(longPress: Duration? = nil, doubleTapWindow: Duration = Self.defaultDoubleTapWindow) {
        self.longPress = longPress
        self.doubleTapWindow = doubleTapWindow
    }
}

/// Turns footswitch downs and ups into switch actions (spec 6.2, U08) and sends them to the engine.
///
/// The preset address is captured at the first down and kept until the gesture ends.
/// A generation bump of the engine forgets every gesture: a button held across it fires nothing more.
@MainActor
public final class GestureRecognizer {
    /// The last actions of each gesture (spec 6.2).
    private static let tapEnd = [SwitchAction.release, SwitchAction.releaseAll]
    private static let holdEnd = [SwitchAction.longPressRelease, SwitchAction.releaseAll]
    private static let doubleTapEnd = [SwitchAction.doubleTap, SwitchAction.doubleTapRelease, SwitchAction.releaseAll]
    private static let longDoubleTapEnd = [SwitchAction.longDoubleTapRelease, SwitchAction.releaseAll]

    /// U08: the editor's long-press time, `100 + 50 * longPressTime` ms.
    public let backupLongPress: Duration
    /// The times for the next gesture. A gesture keeps the times of its first down (V08).
    public var timing = GestureTiming()
    /// The long-press time of the next gesture.
    public var longPress: Duration { timing.longPress ?? backupLongPress }

    private enum Phase {
        /// First down, before Long Press.
        case pressed
        /// Long Press has fired.
        case held
        /// The first tap ended on a preset with double-tap messages.
        case waiting
        /// Second down, before Long Double Tap.
        case secondPressed
        /// Long Double Tap has fired.
        case secondHeld
    }

    private struct Gesture {
        let address: PresetAddress
        var source: InputSource
        /// The engine generation at the first down.
        let generation: Int
        var phase: Phase
        var timer: Wakeup?
        /// The times at the first down (V08).
        let timing: (longPress: Duration, doubleTapWindow: Duration)
    }

    private let engine: Engine
    private let scheduler: any Scheduler
    private var gestures: [Footswitch: Gesture] = [:]

    public init(engine: Engine, scheduler: any Scheduler) {
        self.engine = engine
        self.scheduler = scheduler
        backupLongPress = .milliseconds(100 + 50 * engine.backup.longPressTime)
    }

    /// A footswitch went down. A down on a footswitch that is already down does nothing (key repeat, second source).
    public func down(_ button: Footswitch, source: InputSource) {
        forgetStale()
        if var gesture = gestures[button] {
            guard gesture.phase == .waiting else { return }
            stopTimer(of: button)
            gesture.phase = .secondPressed
            gesture.source = source
            gesture.timer = startTimer(button, after: gesture.timing.longPress)
            gestures[button] = gesture
            return
        }
        // The address of the page shown at the down, before a deferred Release below can change the page.
        let address = engine.state.address(of: button)
        // Another button ends a wait for a second tap as a single tap.
        for other in Footswitch.allCases where gestures[other]?.phase == .waiting {
            finish(other, Self.tapEnd)
        }
        gestures[button] = Gesture(
            address: address, source: source, generation: engine.generation, phase: .pressed,
            timer: startTimer(button, after: longPress), timing: (longPress, timing.doubleTapWindow))
        engine.enqueue(address, SwitchAction.press)
    }

    /// A footswitch went up. An up from another source than the one that pressed it does nothing.
    public func up(_ button: Footswitch, source: InputSource) {
        forgetStale()
        guard var gesture = gestures[button], gesture.source == source else { return }
        switch gesture.phase {
        case .pressed:
            guard hasDoubleTap(gesture.address) else { return finish(button, Self.tapEnd) }
            stopTimer(of: button)
            gesture.phase = .waiting
            gesture.timer = startTimer(button, after: gesture.timing.doubleTapWindow)
            gestures[button] = gesture
        case .held: finish(button, Self.holdEnd)
        case .secondPressed: finish(button, Self.doubleTapEnd)
        case .secondHeld: finish(button, Self.longDoubleTapEnd)
        case .waiting: break
        }
    }

    /// The window lost focus. A held gesture past its long press releases; one before its long press ends silently.
    /// A wait for a second tap ends as a single tap. An action that already runs, such as a Press at a Delay, finishes:
    /// focus loss is not a generation bump (spec 5.4), and the cancel policy only stops unintended actions (spec 6.2).
    /// The Press of a gesture that ends silently and still waits in the queue is removed: it has sent nothing yet.
    public func focusLost() {
        forgetStale()
        for button in Footswitch.allCases {
            switch gestures[button]?.phase {
            case .held: finish(button, Self.holdEnd)
            case .secondHeld: finish(button, Self.longDoubleTapEnd)
            case .waiting: finish(button, Self.tapEnd)
            case .pressed, .secondPressed:
                if let gesture = gestures[button] { engine.withdraw(gesture.address, SwitchAction.press) }
                finish(button, [])
            case nil: break
            }
        }
    }

    private func timerFired(_ button: Footswitch) {
        forgetStale()
        guard var gesture = gestures[button] else { return }
        gesture.timer = nil
        switch gesture.phase {
        case .pressed:
            gesture.phase = .held
            gestures[button] = gesture
            engine.enqueue(gesture.address, SwitchAction.longPress)
        case .secondPressed:
            gesture.phase = .secondHeld
            gestures[button] = gesture
            engine.enqueue(gesture.address, SwitchAction.longDoubleTap)
        case .waiting: finish(button, Self.tapEnd)
        case .held, .secondHeld: break
        }
    }

    /// Ends a gesture and sends its last actions. They stop at the first one that bumps the generation (a fault).
    private func finish(_ button: Footswitch, _ actions: [Int]) {
        stopTimer(of: button)
        guard let gesture = gestures.removeValue(forKey: button) else { return }
        for action in actions where engine.generation == gesture.generation {
            engine.enqueue(gesture.address, action)
        }
    }

    /// Forgets every gesture that started before the last generation bump, without sending anything.
    private func forgetStale() {
        for (button, gesture) in gestures where gesture.generation != engine.generation {
            finish(button, [])
        }
    }

    private func startTimer(_ button: Footswitch, after delay: Duration) -> Wakeup {
        scheduler.schedule(after: delay) { [weak self] in self?.timerFired(button) }
    }

    private func stopTimer(of button: Footswitch) {
        if let timer = gestures[button]?.timer { scheduler.cancel(timer) }
        gestures[button]?.timer = nil
    }

    /// U08: only presets with Double Tap, Double Tap Release, Long Double Tap or Long Double Tap Release messages wait.
    private func hasDoubleTap(_ address: PresetAddress) -> Bool {
        let messages = engine.backup.banks[address.bank].presets[address.preset].messages
        return messages.contains { SwitchAction.secondTap.contains($0.action) }
    }
}
