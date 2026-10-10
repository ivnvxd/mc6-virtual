/// A physical footswitch on the shown page. Spec 6.1: D E F on top, A B C below.
public enum Footswitch: Int, CaseIterable, Sendable {
    case a, b, c, d, e, f
}

/// The input that pressed a footswitch. Only the source that started a gesture ends it.
public enum InputSource: Sendable {
    case mouse, keyboard
}

/// Turns footswitch downs and ups into switch actions (spec 6.2, U08) and sends them to the engine.
///
/// The preset address is captured at the first down and kept until the gesture ends.
/// A generation bump of the engine forgets every gesture: a button held across it fires nothing more.
@MainActor
public final class GestureRecognizer {
    /// U08: how long a preset with double-tap messages waits for a second tap.
    public static let doubleTapWindow = Duration.milliseconds(300)

    /// U08: the editor's long-press time, `100 + 50 * longPressTime` ms.
    public let longPress: Duration

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
    }

    private let backup: Backup
    private let engine: Engine
    private let scheduler: any Scheduler
    private var gestures: [Footswitch: Gesture] = [:]

    public init(backup: Backup, engine: Engine, scheduler: any Scheduler) {
        self.backup = backup
        self.engine = engine
        self.scheduler = scheduler
        longPress = .milliseconds(100 + 50 * backup.longPressTime)
    }

    /// A footswitch went down. A down on a footswitch that is already down does nothing (key repeat, second source).
    public func down(_ button: Footswitch, source: InputSource) {
        forgetStale()
        if var gesture = gestures[button] {
            guard gesture.phase == .waiting else { return }
            stopTimer(of: button)
            gesture.phase = .secondPressed
            gesture.source = source
            gesture.timer = startTimer(button, after: longPress)
            gestures[button] = gesture
            return
        }
        // Another button ends a wait for a second tap as a single tap.
        for other in Footswitch.allCases where gestures[other]?.phase == .waiting {
            finish(other, [2, 9])
        }
        let address = PresetAddress(bank: engine.state.bank, preset: engine.state.page * 6 + button.rawValue)
        gestures[button] = Gesture(
            address: address, source: source, generation: engine.generation, phase: .pressed,
            timer: startTimer(button, after: longPress))
        engine.enqueue(address, 1)
    }

    /// A footswitch went up. An up from another source than the one that pressed it does nothing.
    public func up(_ button: Footswitch, source: InputSource) {
        forgetStale()
        guard var gesture = gestures[button], gesture.source == source else { return }
        switch gesture.phase {
        case .pressed:
            guard hasDoubleTap(gesture.address) else { return finish(button, [2, 9]) }
            stopTimer(of: button)
            gesture.phase = .waiting
            gesture.timer = startTimer(button, after: Self.doubleTapWindow)
            gestures[button] = gesture
        case .held: finish(button, [4, 9])
        case .secondPressed: finish(button, [5, 6, 9])
        case .secondHeld: finish(button, [8, 9])
        case .waiting: break
        }
    }

    /// The window lost focus. A held gesture past its long press releases; one before its long press ends silently.
    /// A wait for a second tap ends as a single tap.
    public func focusLost() {
        forgetStale()
        for button in Footswitch.allCases {
            switch gestures[button]?.phase {
            case .held: finish(button, [4, 9])
            case .secondHeld: finish(button, [8, 9])
            case .waiting: finish(button, [2, 9])
            case .pressed, .secondPressed: finish(button, [])
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
            engine.enqueue(gesture.address, 3)
        case .secondPressed:
            gesture.phase = .secondHeld
            gestures[button] = gesture
            engine.enqueue(gesture.address, 7)
        case .waiting: finish(button, [2, 9])
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
        backup.banks[address.bank].presets[address.preset].messages.contains { (5...8).contains($0.action) }
    }
}
