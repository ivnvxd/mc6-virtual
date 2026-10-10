/// A shown bank and page index (0 = page 1).
public struct Place: Hashable, Sendable {
    public let bank: Int
    public let page: Int

    public init(bank: Int, page: Int) {
        self.bank = bank
        self.page = page
    }
}

extension Bank {
    /// The pages that normal paging shows. U05: `pageLimit` 0 means 4, the MC6 Pro page count.
    public var pageCount: Int { (1...4).contains(pageLimit) ? pageLimit : 4 }
}

extension RuntimeState {
    /// The shown bank and page.
    public var place: Place { Place(bank: bank, page: page) }

    /// Bank Jump (U04). Only a jump to a different bank records `lastPlace`, so BACK flips between two places.
    /// Without a `lastPlace`, BACK does nothing.
    mutating func jump(_ target: BankJumpTarget, banks: [Bank]) {
        let destination: Place
        switch target {
        case .bank(let bank, let page): destination = Place(bank: bank, page: page)
        case .lastBankAndPage:
            guard let lastPlace else { return }
            destination = lastPlace
        case .lastBank:
            guard let lastPlace else { return }
            destination = Place(bank: lastPlace.bank, page: 0)
        }
        if destination.bank != bank {
            lastPlace = place
            bank = destination.bank
        }
        // U05: hidden pages never show, so a page past the limit becomes the last visible page.
        page = min(destination.page, banks[bank].pageCount - 1)
    }

    /// Toggle Page on the shown bank (U05). PageUp and PageDown wrap within the bank's page count.
    mutating func turnPage(_ change: PageChange, banks: [Bank]) {
        let count = banks[bank].pageCount
        switch change {
        case .up: page = (page + 1) % count
        case .down: page = (page + count - 1) % count
        case .go(let target): page = min(target, count - 1)
        }
    }
}
