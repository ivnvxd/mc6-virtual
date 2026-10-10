import Foundation
import Testing
@testable import MC6Core

/// Acceptance criterion 1: a sweep over every production switch message.
/// The expected set is inventory/active-messages.json; the only messages that never run are the
/// Position 2 messages of the hidden helper PEDALS U (plan, Context: fixture facts).
@MainActor @Suite struct SweepTests {
    /// PEDALS U (bank 2, stored preset 20) m1 to m4: nothing ever puts U at Position 2.
    static let unreachable: Set<String> = Set((1...4).map { "/data/bankArray/2/presetArray/20/msgArray/\($0)" })

    /// Switch message pointers of the production banks, from the spec inventory.
    static func expected(_ production: Set<Int>) throws -> Set<String> {
        let json = try JSONSerialization.jsonObject(with: Fixture.inventory("active-messages.json")) as! [String: Any]
        let rows = json["rows"] as! [[String: Any]]
        return Set(rows.filter { $0["namespace"] as? String == "switch" && production.contains($0["bankId"] as! Int) }
            .map { $0["sourcePointer"] as! String })
    }

    @Test("Every pressable production preset runs each action it uses from Position 1 and Position 2 without a fault")
    func sweep() throws {
        let backup = try Fixture.backup()
        var ran: Set<String> = []
        for b in backup.productionBanks.sorted() {
            let bank = backup.banks[b]
            // Only the pages that paging shows (U05); hidden helpers run through Engage.
            for p in 0..<bank.pageCount * 6 where !bank.presets[p].messages.isEmpty {
                let preset = bank.presets[p]
                let address = PresetAddress(bank: b, preset: p)
                for action in Set(preset.messages.map(\.action)).sorted() {
                    for position in [Position.one, .two] {
                        let h = EngineHarness(backup)
                        h.engine.onExecute = { ran.insert($0.pointer) }
                        h.engine.state.bank = b
                        h.engine.state.page = p / 6
                        h.engine.state[position: address] = position
                        // A message scroll preset runs one group per Release; repeat so that every group runs.
                        let runs = preset.toMsgScroll ? preset.messages.filter { $0.action == action }.count : 1
                        for _ in 0..<runs { h.engine.enqueue(address, action) }
                        h.scheduler.advance(by: .seconds(10))
                        #expect(h.faults.isEmpty, "\(address) action \(action) from \(position)")
                    }
                }
            }
        }
        let expected = try Self.expected(backup.productionBanks)
        #expect(expected.count == 1027)  // 1300 production minus 273 expression messages
        #expect(ran.isSubset(of: expected))
        #expect(expected.subtracting(ran) == Self.unreachable)
    }
}
