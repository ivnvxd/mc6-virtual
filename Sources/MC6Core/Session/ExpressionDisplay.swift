/// What an expression input does right now, for the pedal label (spec 6.3).
public enum ExpressionDisplay {
    /// The selected messages of `input` (0 to 3) in the shown bank, one line each, in slot order (U06: masks are global).
    /// Empty when no message of the input is selected.
    public static func selected(input: Int, _ state: RuntimeState, in backup: Backup) -> [String] {
        let mask = state.expressionMasks[input]
        return backup.banks[state.bank].expressions[input].messages.compactMap { message in
            guard mask & 1 << message.slot != 0, case .expression(let channel, let number, _, _) = message.command else { return nil }
            return "m\(message.slot): CC \(number), channel \(channel)"
        }
    }
}
