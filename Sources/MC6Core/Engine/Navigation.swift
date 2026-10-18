/// A shown bank and page index (0 = page 1).
public struct Place: Hashable, Sendable {
    public let bank: Int
    public let page: Int

    public init(bank: Int, page: Int) {
        self.bank = bank
        self.page = page
    }
}

/// A bank or page step of the keys or the bank sidebar (V01 to V03).
public enum NavigationStep: Sendable, Equatable {
    case bankDown, bankUp, pageDown, pageUp
    /// A bank of the sidebar, at page 1.
    case select(Int)
}

extension Backup {
    /// V01: the banks that the bank keys and the sidebar step through, by number.
    public var sortedProductionBanks: [Int] { productionBanks.sorted() }
}

extension Bank {
    /// The pages that normal paging shows. U05: `pageLimit` 0 means 4, the MC6 Pro page count.
    public var pageCount: Int { pageLimit == 0 ? 4 : pageLimit }
}

extension RuntimeState {
    /// The shown bank and page.
    public var place: Place { Place(bank: bank, page: page) }

    /// Spec 6.1: the stored preset under a physical button of the shown page, `page * 6 + button`.
    public func address(of button: Footswitch) -> PresetAddress {
        PresetAddress(bank: bank, preset: page * Footswitch.allCases.count + button.rawValue)
    }

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

    /// V01: bank steps wrap within the production banks. V02: a bank change goes to page 1 through `jump`,
    /// so it records `lastPlace`. V03: page steps are Toggle Page up and down. A bank outside the production banks
    /// does nothing, because the importer did not check it.
    mutating func navigate(_ step: NavigationStep, backup: Backup) {
        let banks = backup.sortedProductionBanks
        switch step {
        case .bankDown, .bankUp:
            guard let index = banks.firstIndex(of: bank) else { return }
            let next = banks[(index + (step == .bankUp ? 1 : banks.count - 1)) % banks.count]
            jump(.bank(next, page: 0), banks: backup.banks)
        case .pageDown: turnPage(.down, banks: backup.banks)
        case .pageUp: turnPage(.up, banks: backup.banks)
        case .select(let target):
            guard banks.contains(target) else { return }
            jump(.bank(target, page: 0), banks: backup.banks)
        }
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
