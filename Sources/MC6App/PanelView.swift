import MC6Core
import SwiftUI

/// The MC6 Pro face: D E F on top, the three screens, A B C below, on a dark anodized panel.
/// Built from plain values with shapes, text and images only, so `ImageRenderer` can draw it for snapshots.
struct PanelView: View {
    let screens: [Screen]
    let brightness: Double
    let held: Set<Footswitch>
    let longPress: Duration
    var onDown: (Footswitch) -> Void = { _ in }
    var onUp: (Footswitch) -> Void = { _ in }

    static let column: CGFloat = 200
    static let surface = Color(red: 0x2A / 255, green: 0x2C / 255, blue: 0x2F / 255)
    static let silkscreen = Color(red: 0xB9 / 255, green: 0xBC / 255, blue: 0xC0 / 255)

    var body: some View {
        VStack(spacing: 22) {
            row([.d, .e, .f])
            HStack(spacing: 0) {
                ForEach(screens.indices, id: \.self) { index in
                    ScreenView(screen: screens[index], brightness: brightness).frame(width: Self.column)
                }
            }
            row([.a, .b, .c])
                .overlay {
                    HStack(spacing: 0) {
                        Color.clear.frame(width: Self.column / 2)
                        printLine("BANK DOWN", key: KeyCommand.navigate(.bankDown).label)
                        printLine("BANK UP", key: KeyCommand.navigate(.bankUp).label)
                        Color.clear.frame(width: Self.column / 2)
                    }
                }
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Self.surface)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4))
    }

    private func row(_ buttons: [Footswitch]) -> some View {
        HStack(spacing: 0) {
            ForEach(buttons, id: \.self) { button in
                FootswitchView(
                    button: button, isHeld: held.contains(button), longPress: longPress,
                    onDown: { onDown(button) }, onUp: { onUp(button) })
                    .frame(width: Self.column)
            }
        }
    }

    /// "— BANK DOWN —" as printed between the lower switches, with its key.
    private func printLine(_ text: String, key: String) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(Self.silkscreen.opacity(0.5)).frame(height: 1)
            VStack(spacing: 2) {
                Text(verbatim: text).font(PanelFont.print(9)).tracking(1.2).fixedSize()
                Text(verbatim: key).font(PanelFont.print(9)).opacity(0.7)
            }
            Rectangle().fill(Self.silkscreen.opacity(0.5)).frame(height: 1)
        }
        .foregroundStyle(Self.silkscreen)
        .frame(width: Self.column - 104)
        .frame(width: Self.column)
    }
}
