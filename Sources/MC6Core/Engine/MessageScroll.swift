/// The message scroll state of a preset with `toMsgScroll` (spec 7.11, U07).
public struct MessageScroll: Hashable, Sendable {
    /// Release messages per group, set by Utility `[6,4,n]`. Before any Utility, one message per group.
    public var groupSize = 1
    /// The group the next Release runs. U07: starts at 0, wraps, survives bank changes.
    public var group = 0
}

extension RuntimeState {
    /// U07: the slots of the next group of `releases` (the Release messages in slot order), and advances the pointer.
    /// Groups ignore the position gate; the last group may be short.
    mutating func nextScrollGroup(_ releases: [Message], of address: PresetAddress) -> Set<Int> {
        guard !releases.isEmpty else { return [] }
        var scroll = messageScroll[address, default: MessageScroll()]
        let count = (releases.count + scroll.groupSize - 1) / scroll.groupSize
        let group = scroll.group % count
        scroll.group = (group + 1) % count
        messageScroll[address] = scroll
        let start = group * scroll.groupSize
        return Set(releases[start..<min(start + scroll.groupSize, releases.count)].map(\.slot))
    }
}
