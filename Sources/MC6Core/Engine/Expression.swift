/// Spec 7.13: an expression message sends CC `number` on `channel` (1 to 16) with
/// `min + round((max - min) * value / 127)` for an input `value` of 0 to 127.
func expressionBytes(channel: Int, number: Int, min: Int, max: Int, value: Int) -> [UInt8] {
    let scaled = min + Int((Double((max - min) * value) / 127).rounded())
    return [0xB0 | UInt8(channel - 1), UInt8(number), UInt8(scaled)]
}

extension RuntimeState {
    /// The selected messages of expression input `input` (0 to 3) in the shown bank, in slot order.
    /// U06: the masks are global, so a bank change keeps the selection.
    func selectedExpressions(input: Int, in backup: Backup) -> [Message] {
        let mask = expressionMasks[input]
        return backup.banks[bank].expressions[input].messages.filter { mask & 1 << $0.slot != 0 }
    }
}
