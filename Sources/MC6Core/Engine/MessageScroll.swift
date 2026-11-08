/// The message scroll state of a preset with `toMsgScroll` (spec 7.11, U07).
public struct MessageScroll: Hashable, Sendable {
    /// Release messages per group, set by Utility `[6,4,n]`. Before any Utility, one message per group.
    public var groupSize = 1
    /// The ordinal of the Release message that the next Release runs first. U07: starts at 0, wraps, survives bank
    /// changes. V23: Set Message Scroll Counter can point it into the middle of a group.
    public var next = 0
}

extension RuntimeState {
    /// U07: the slots of the next group of `releases` (the Release messages in slot order), and advances the pointer.
    /// Groups ignore the position gate; a group ends early at the last message.
    mutating func nextScrollGroup(_ releases: [Message], of address: PresetAddress) -> Set<Int> {
        guard !releases.isEmpty else { return [] }
        var scroll = messageScroll[address, default: MessageScroll()]
        let start = scroll.next % releases.count
        let end = min(start + scroll.groupSize, releases.count)
        scroll.next = end == releases.count ? 0 : end
        messageScroll[address] = scroll
        return Set(releases[start..<end].map(\.slot))
    }

    /// V23: the next Release of `address` starts at the first of `releases` in `slot` or after it. Without one, and
    /// for Reset (nil), it starts at the first.
    mutating func cueScroll(_ address: PresetAddress, slot: Int?, releases: [Message]) {
        let next = slot.flatMap { slot in releases.firstIndex { $0.slot >= slot } } ?? 0
        messageScroll[address, default: MessageScroll()].next = next
    }
}
