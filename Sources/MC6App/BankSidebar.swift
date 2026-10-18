import MC6Core
import SwiftUI

/// The banks that the bank keys step through (V01), with the shown bank selected. A click goes to page 1 of a bank.
struct BankSidebar: View {
    let backup: Backup
    let shownBank: Int
    let select: (Int) -> Void

    var body: some View {
        List(selection: Binding(get: { shownBank }, set: { if let bank = $0 { select(bank) } })) {
            ForEach(backup.sortedProductionBanks, id: \.self) { number in
                let bank = backup.banks[number]
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(verbatim: String(format: "%03d", number + 1))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        nameText(NamePart.parts(bank.name)).font(.body.weight(.semibold)).lineLimit(1)
                    }
                    if !bank.description.isEmpty {
                        Text(verbatim: bank.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(.vertical, 2)
                .tag(number)
            }
        }
        .listStyle(.sidebar)
        .frame(width: 230)
    }
}

/// Hands the `NSWindow` of a SwiftUI view to the app, once it is in a window.
struct WindowReader: NSViewRepresentable {
    let found: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window { found(window) }
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
