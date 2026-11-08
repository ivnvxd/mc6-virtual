/// A decoded message of the v1 profile (spec section 7). Named `Command` to avoid `Foundation.Operation`.
public enum Command: Sendable, Equatable {
    /// Program Change or Control Change, ready to send.
    case midi([UInt8])
    /// `enter` runs the On Enter Bank messages of the new bank (`data[2]` bit 1, V21).
    case bankJump(BankJumpTarget, enter: Bool)
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
    /// V23: Set Message Scroll Counter cues a message of the frame preset (nil) or of a preset of the frame bank.
    /// A nil slot is Reset.
    case scrollCounter(preset: Int?, slot: Int?)
    /// V24: sets temporary colors of the frame preset (nil) or of a preset of the frame bank (Utility 8 and 9).
    case presetColors(preset: Int?, PresetColors)
    /// V24: sets a temporary name of the frame preset; nil restores the stored name.
    case rename(NameKind, String?)
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

/// The name that a Rename changes (SEMANTICS.md section 4). The app has no Shift names.
public enum NameKind: Sendable, Hashable {
    /// The name the band shows now, whatever the position.
    case current
    case short, toggle, long
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
        guard d[2] & 1 == 0 else { throw problem(pointer, "data/2", "A CC with the expression value is not supported.") }
        return .midi([0xB0 | UInt8(try channel(raw, pointer) - 1), UInt8(d[0]), UInt8(d[1])])
    case 13:
        // Bit 1 runs the On Enter Bank messages of the new bank (V21). Bit 2 runs the On Exit Bank messages, which the
        // importer skips, so it has no effect.
        guard d[2] & ~15 == 0 else { throw problem(pointer, "data/2", "Bank Jump option \(d[2]) is not supported.") }
        let enter = d[2] & 2 != 0
        switch d[1] {
        case 0: return .bankJump(.bank(d[0], page: (d[2] & 1) | ((d[2] >> 3) & 1) << 1), enter: enter)
        case 126: return .bankJump(.lastBankAndPage, enter: enter)
        case 127: return .bankJump(.lastBank, enter: enter)
        default: throw problem(pointer, "data/1", "Bank Jump mode \(d[1]) is not supported.")
        }
    case 14:
        switch d[0] {
        case 1: return .togglePage(.up)
        case 2: return .togglePage(.down)
        case 3...6: return .togglePage(.go(d[0] - 3))
        default: throw problem(pointer, "data/0", "Toggle Page operation \(d[0]) is not supported.")
        }
    case 15:
        guard d[3] & ~7 == 0 else { throw problem(pointer, "data/3", "Set Toggle names presets beyond the 24 of a bank.") }
        let mask = UInt32(d[0] & 127) | UInt32(d[1] & 127) << 7 | UInt32(d[2] & 127) << 14 | UInt32(d[3] & 7) << 21
        // The operation is `(c - 1) & 15`, and only operations 0 and 1 are supported. Compare `c` instead of computing
        // with it: an imported value can be any Int.
        switch raw.c {
        case 1: return .setToggle(.one, mask: mask)
        case 2: return .setToggle(.two, mask: mask)
        default: throw problem(pointer, "c", "Set Toggle operation \(raw.c) is not supported. Only Position 1 and Position 2 are.")
        }
    case 17:
        guard d[4] & ~63 == 0 else { throw problem(pointer, "data/4", "Select Expression value \(d[4]) is not supported.") }
        let mask = UInt32(d[0] >> 2) << 27 | UInt32(d[1] & 127) << 20 | UInt32(d[2] & 127) << 13
            | UInt32(d[3] & 127) << 6 | UInt32(d[4] & 63)
        return .selectExpression(input: d[0] & 3, mask: mask)
    case 22:
        return .togglePreset
    case 23:
        if d[1] != 0 { notes.append(ImportNote(pointer: "\(pointer)/data/1", text: "The Delay has an unused value \(d[1]). The app does not use this value.", kind: .unusedValue)) }
        return .delay(ms: d[0] * 10)
    case 24:
        return .clockTap
    case 27:
        let (target, action) = try decodeEngage(raw, bank: bank, pointer: pointer, notes: &notes)
        return .engage(bank: target.bank, preset: target.preset, action: action)
    case 36:
        switch d[0] {
        case 0:
            // `data[1]` is the preset, 127 the current one. `data[2]` is the message, 127 Reset.
            guard d[1] < Importer.presetCount || d[1] == 127 else {
                throw problem(pointer, "data/1", "The Utility names preset \(d[1] + 1), which does not exist.")
            }
            guard d[2] < Importer.slotCount || d[2] == 127 else {
                throw problem(pointer, "data/2", "The Utility names message \(d[2] + 1), which does not exist.")
            }
            return .scrollCounter(preset: d[1] == 127 ? nil : d[1], slot: d[2] == 127 ? nil : d[2])
        case 6:
            guard d[1] == 4 else { throw problem(pointer, "data/1", "Message scroll operation \(d[1]) is not supported.") }
            guard d[2] > 0 else { throw problem(pointer, "data/2", "A message scroll group size of 0 is not supported.") }
            return .scrollGroupSize(d[2])
        case 8, 9:
            // The editor binds `data[1]` to the background, `data[2]` to the text, `data[3]` to the strip and, for
            // Utility 9, `data[4]` to the preset.
            var preset: Int?
            if d[0] == 9 {
                guard d[4] < Importer.presetCount else {
                    throw problem(pointer, "data/4", "The Utility names preset \(d[4] + 1), which does not exist.")
                }
                preset = d[4]
            }
            for i in 1...3 where Importer.unnamedColors.contains(d[i]) {
                notes.append(ImportNote(
                    pointer: "\(pointer)/data/\(i)",
                    text: "Color \(d[i]) has no name in the Morningstar table. It shows as the dim version of color \(d[i] - 64).",
                    kind: .unnamedColor))
            }
            return .presetColors(preset: preset, PresetColors(strip: d[3], text: d[2], background: d[1]))
        default:
            throw problem(pointer, "data/0", "Utility type \(d[0]) is not supported.")
        }
    case 44:
        // `c - 1`: bit 0 restores, bits 1 to 3 name the kind. Compare `c` instead of computing with it: an imported
        // value can be any Int.
        let kind: NameKind
        switch raw.c {
        case 1, 2: kind = .current
        case 3, 4: kind = .short
        case 5, 6: kind = .toggle
        case 7, 8: throw problem(pointer, "c", "Renaming the Shift name is not supported.")
        case 9, 10: kind = .long
        default: throw problem(pointer, "c", "Rename type \(raw.c) is not supported.")
        }
        // An even `c` restores the stored name and has no text.
        if raw.c.isMultiple(of: 2) { return .rename(kind, nil) }
        let bytes = d.filter { (32...127).contains($0) }.map { UInt8($0) }
        return .rename(kind, String(decoding: bytes, as: UTF8.self))
    default:
        throw problem(pointer, "t", "\(TypeNames.name(raw.t, in: .switchMessage)) is not supported.")
    }
}

/// The target preset and action of an Engage Preset in `bank`, a switch or a bank message. The current-bank flag
/// (`data[1]` bit 6) resolves to `bank`. Inert bytes go to `notes` (U01).
private func decodeEngage(
    _ raw: RawMessage, bank: Int, pointer: String, notes: inout [ImportNote]
) throws(ImportProblem) -> (target: PresetAddress, action: Int) {
    let d = raw.data
    guard d[1] & 32 == 0, d[1] & 31 < 24 else {
        throw problem(pointer, "data/1", "Engage names preset \((d[1] & 63) + 1), which does not exist.")
    }
    guard SwitchAction.targets.contains(d[2]) else { throw problem(pointer, "data/2", "Engage action \(d[2]) is not supported.") }
    if d[3] != 0 { notes.append(ImportNote(pointer: "\(pointer)/data/3", text: "The Engage has an unused value \(d[3]). The app does not use this value.", kind: .unusedValue)) }
    if raw.c != 1 { notes.append(ImportNote(pointer: "\(pointer)/c", text: "The Engage has an unused channel value \(raw.c). The app does not use this value.", kind: .unusedValue)) }
    return (PresetAddress(bank: d[1] & 64 != 0 ? bank : d[0], preset: d[1] & 31), d[2])
}

/// V21: decodes a bank message with an event (`a != 0`) in `bank`. Only an Engage Preset On Enter Bank runs, each
/// time or once. The checks go type, event, position setting, then the Engage fields.
func decodeBankMessage(
    _ raw: RawMessage, slot: Int, bank: Int, pointer: String, notes: inout [ImportNote]
) throws(ImportProblem) -> BankMessage {
    guard raw.t == 15 else { throw problem(pointer, "t", "\(TypeNames.name(raw.t, in: .bankMessage)) as a bank message is not supported.") }
    let once: Bool
    switch raw.a {
    case 1: once = false
    case 3: once = true
    default: throw problem(pointer, "a", "The bank event \(TypeNames.bankEvent(raw.a)) is not supported.")
    }
    guard raw.tg == 2 else { throw problem(pointer, "tg", "Position setting \(raw.tg) is not supported for a bank message.") }
    let (target, action) = try decodeEngage(raw, bank: bank, pointer: pointer, notes: &notes)
    return BankMessage(slot: slot, once: once, target: target, action: action, pointer: pointer)
}

/// Decodes an expression message (`t != 0`). Only linear CC (`t=1`) is supported.
func decodeExpressionCommand(_ raw: RawMessage, pointer: String) throws(ImportProblem) -> Command {
    guard raw.t == 1 else { throw problem(pointer, "t", "\(TypeNames.name(raw.t, in: .expression)) is not supported.") }
    return .expression(channel: try channel(raw, pointer), number: raw.data[0], min: raw.data[1], max: raw.data[2])
}

/// A problem at `field` of the message at `pointer`. The importer skips the message with a note.
private func problem(_ pointer: String, _ field: String, _ reason: String) -> ImportProblem {
    ImportProblem(pointer: "\(pointer)/\(field)", reason: reason)
}

/// The MIDI channel `c` of a message, 1 to 16.
private func channel(_ raw: RawMessage, _ pointer: String) throws(ImportProblem) -> Int {
    guard (1...16).contains(raw.c) else { throw problem(pointer, "c", "MIDI channel \(raw.c) is outside 1 to 16.") }
    return raw.c
}
