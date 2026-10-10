/// Spec 7.13: an expression message sends CC `number` on `channel` (1 to 16) with
/// `min + round((max - min) * value / 127)` for an input `value` of 0 to 127.
func expressionBytes(channel: Int, number: Int, min: Int, max: Int, value: Int) -> [UInt8] {
    let scaled = min + Int((Double((max - min) * value) / 127).rounded())
    return [0xB0 | UInt8(channel - 1), UInt8(number), UInt8(scaled)]
}
