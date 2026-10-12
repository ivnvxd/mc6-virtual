import Foundation
import Testing
@testable import MC6Core

/// Acceptance criterion 1: a sweep over every production switch message, in the coverage sense.
/// The expected set is inventory/active-messages.json. The sweep sets only the position of the pressed preset,
/// so it cannot show that no chain of presses puts a hidden helper at Position 2. `pedalsUStaysAtPosition1`
/// checks that fact for PEDALS U, whose Position 2 messages are the only ones the sweep does not run.
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

    /// Only a Toggle Preset in U itself or a Set Toggle to Position 2 in bank 2 with bit 20 can move U.
    @Test("Fixture fact: no production message puts PEDALS U at Position 2")
    func pedalsUStaysAtPosition1() throws {
        let backup = try Fixture.backup()
        let u = PresetAddress(bank: 2, preset: 20)
        for b in backup.productionBanks {
            for (p, preset) in backup.banks[b].presets.enumerated() {
                for message in preset.messages {
                    switch message.command {
                    case .togglePreset: #expect(PresetAddress(bank: b, preset: p) != u, "\(message.pointer)")
                    case .setToggle(.two, let mask): #expect(b != u.bank || mask & 1 << u.preset == 0, "\(message.pointer)")
                    default: break
                    }
                }
            }
        }
    }
}
