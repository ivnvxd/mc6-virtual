/// A decoded message of the v1 profile (spec section 7). Named `Command` to avoid `Foundation.Operation`.
public enum Command: Sendable, Equatable {
    /// Program Change or Control Change, ready to send.
    case midi([UInt8])
    case bankJump(BankJumpTarget)
    case togglePage(PageChange)
    /// Set Toggle: put the presets in `mask` (bit 0 = A) of the frame bank at `position`.
    case setToggle(Position, mask: UInt32)
    /// Select Expression: `mask` bit 0 is expression message 0 of `input`.
    case selectExpression(input: Int, mask: UInt32)
    case togglePreset
    case delay(ms: Int)
    case clockTap
    /// Engage Preset, with the current-bank flag already resolved to the message's bank.
    case engage(bank: Int, preset: Int, action: Int)
    case scrollGroupSize(Int)
    /// Rename the current name of the frame preset.
    case rename(String)
    /// Expression message: CC `number` on `channel`, scaled from `min` to `max`.
    case expression(channel: Int, number: Int, min: Int, max: Int)
}

public enum BankJumpTarget: Sendable, Equatable {
    /// Bank ID and page index (0 = page 1).
    case bank(Int, page: Int)
    /// Last used bank and page (`d1=126`).
    case lastBankAndPage
    /// Last used bank, page 1 (`d1=127`).
    case lastBank
}

public enum PageChange: Sendable, Equatable {
    case up, down
    /// Page index (0 = page 1).
    case go(Int)
}

public enum Position: Sendable, Equatable {
    case one, two
}

/// Decodes a switch message (`t != 0`) that lives in `bank`. Inert bytes go to `notes`.
func decodeSwitchCommand(
    _ raw: RawMessage, bank: Int, pointer: String, notes: inout [ImportNote]
) throws(ImportProblem) -> Command {
    let d = raw.data

    switch raw.t {
    case 1:
        return .midi([0xC0 | UInt8(try channel(raw, pointer) - 1), UInt8(d[0])])
    case 2:
        guard d[2] & 1 == 0 else { throw problem(pointer, "data/2", "CC with the expression value is not supported") }
        return .midi([0xB0 | UInt8(try channel(raw, pointer) - 1), UInt8(d[0]), UInt8(d[1])])
    case 13:
        // Bits 1 and 2 run the bank's Enter and Exit messages. They have no effect, because bank messages are a load error.
        guard d[2] & ~15 == 0 else { throw problem(pointer, "data/2", "Bank Jump d2=\(d[2]) has bits above bit 3") }
        switch d[1] {
        case 0: return .bankJump(.bank(d[0], page: (d[2] & 1) | ((d[2] >> 3) & 1) << 1))
        case 126: return .bankJump(.lastBankAndPage)
        case 127: return .bankJump(.lastBank)
        default: throw problem(pointer, "data/1", "Bank Jump mode \(d[1]) is not supported")
        }
    case 14:
        switch d[0] {
        case 1: return .togglePage(.up)
        case 2: return .togglePage(.down)
        case 3...6: return .togglePage(.go(d[0] - 3))
        default: throw problem(pointer, "data/0", "Toggle Page operation \(d[0]) is not supported")
        }
    case 15:
        guard d[3] & ~7 == 0 else { throw problem(pointer, "data/3", "Set Toggle d3=\(d[3]) has bits above the 24 presets") }
        let mask = UInt32(d[0] & 127) | UInt32(d[1] & 127) << 7 | UInt32(d[2] & 127) << 14 | UInt32(d[3] & 7) << 21
        // The operation is `(c - 1) & 15`, and only operations 0 and 1 are supported. Compare `c` instead of computing
        // with it: an imported value can be any Int.
        switch raw.c {
        case 1: return .setToggle(.one, mask: mask)
        case 2: return .setToggle(.two, mask: mask)
        default: throw problem(pointer, "c", "Set Toggle c=\(raw.c) is not supported (only 1 and 2: Position 1 and Position 2)")
        }
    case 17:
        guard d[4] & ~63 == 0 else { throw problem(pointer, "data/4", "Select Expression d4=\(d[4]) has bit 6 set") }
        let mask = UInt32(d[0] >> 2) << 27 | UInt32(d[1] & 127) << 20 | UInt32(d[2] & 127) << 13
            | UInt32(d[3] & 127) << 6 | UInt32(d[4] & 63)
        return .selectExpression(input: d[0] & 3, mask: mask)
    case 22:
        return .togglePreset
    case 23:
        if d[1] != 0 { notes.append(ImportNote(pointer: "\(pointer)/data/1", text: "Delay d1=\(d[1]) is inert")) }
        return .delay(ms: d[0] * 10)
    case 24:
        return .clockTap
    case 27:
        guard d[1] & 32 == 0, d[1] & 31 < 24 else {
            throw problem(pointer, "data/1", "Engage target preset \(d[1] & 63) does not exist")
        }
        guard SwitchAction.all.contains(d[2]) else { throw problem(pointer, "data/2", "Engage action \(d[2]) is not supported") }
        if d[3] != 0 { notes.append(ImportNote(pointer: "\(pointer)/data/3", text: "Engage d3=\(d[3]) is inert (U01)")) }
        if raw.c != 1 { notes.append(ImportNote(pointer: "\(pointer)/c", text: "Engage c=\(raw.c) is inert (U01)")) }
        return .engage(bank: d[1] & 64 != 0 ? bank : d[0], preset: d[1] & 31, action: d[2])
    case 36:
        guard d[0] == 6 else { throw problem(pointer, "data/0", "Utility subtype \(d[0]) is not supported") }
        guard d[1] == 4 else { throw problem(pointer, "data/1", "Message scroll operation \(d[1]) is not supported") }
        guard d[2] > 0 else { throw problem(pointer, "data/2", "Message scroll group size must be positive") }
        return .scrollGroupSize(d[2])
    case 44:
        guard raw.c == 1 else { throw problem(pointer, "c", "Rename type \(raw.c) is not supported") }
        let bytes = d.filter { (32...127).contains($0) }.map { UInt8($0) }
        return .rename(String(decoding: bytes, as: UTF8.self))
    default:
        throw problem(pointer, "t", "Message type \(raw.t) is not supported")
    }
}

/// Decodes an expression message (`t != 0`). Only linear CC (`t=1`) is supported.
func decodeExpressionCommand(_ raw: RawMessage, pointer: String) throws(ImportProblem) -> Command {
    guard raw.t == 1 else { throw problem(pointer, "t", "Expression type \(raw.t) is not supported") }
    return .expression(channel: try channel(raw, pointer), number: raw.data[0], min: raw.data[1], max: raw.data[2])
}

/// A load error at `field` of the message at `pointer`.
private func problem(_ pointer: String, _ field: String, _ reason: String) -> ImportProblem {
    ImportProblem(pointer: "\(pointer)/\(field)", reason: reason)
}

/// The MIDI channel `c` of a message, 1 to 16.
private func channel(_ raw: RawMessage, _ pointer: String) throws(ImportProblem) -> Int {
    guard (1...16).contains(raw.c) else { throw problem(pointer, "c", "MIDI channel \(raw.c) is outside 1 to 16") }
    return raw.c
}
