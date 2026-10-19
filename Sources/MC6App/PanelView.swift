import MC6Core
import SwiftUI

/// The mode color of the activity light (V13).
enum ActivityMode {
    case dryRun, live, error

    var color: Color {
        switch self {
        case .dryRun: Color(white: 0.75)
        case .live: Color(red: 0.2, green: 0.9, blue: 0.35)
        case .error: Color(red: 1, green: 0.25, blue: 0.2)
        }
    }
}

/// The MC6 Pro face: D E F on top, the three screens, A B C below, on a dark anodized panel.
/// Built from plain values with shapes, text and images only, so `ImageRenderer` can draw it for snapshots.
struct PanelView: View {
    let screens: [Screen]
    let brightness: Double
    let held: Set<Footswitch>
    let longPress: Duration
    var mode: ActivityMode = .dryRun
    /// True for 120 ms after each output (V13).
    var flash = false
    /// The shown page (0 is page 1) and the page count of the shown bank, for the page dots.
    var page = 0
    var pageCount = 1
    /// The keys shown on the switches and the print lines.
    var keys: KeyBindings = .defaults
    /// The bank and page print lines step banks and pages (V14). Nil draws them as print only.
    var onNavigate: ((NavigationStep) -> Void)?
    var onDown: (Footswitch) -> Void = { _ in }
    var onUp: (Footswitch) -> Void = { _ in }

    static let column: CGFloat = 200
    static let surface = Color(red: 0x2A / 255, green: 0x2C / 255, blue: 0x2F / 255)
    static let silkscreen = Color(red: 0xB9 / 255, green: 0xBC / 255, blue: 0xC0 / 255)

    var body: some View {
        VStack(spacing: 22) {
            row([.d, .e, .f])
                .overlay { printLines(("PAGE DOWN", .pageDown), ("PAGE UP", .pageUp)) }
            HStack(spacing: 0) {
                ForEach(screens.indices, id: \.self) { index in
                    ScreenView(screen: screens[index], brightness: brightness, held: held).frame(width: Self.column)
                }
            }
            row([.a, .b, .c])
                .overlay { printLines(("BANK DOWN", .bankDown), ("BANK UP", .bankUp)) }
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .overlay(alignment: .top) { pageDots.padding(.top, 10) }
        .overlay(alignment: .topTrailing) { activityLight.padding(10) }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Self.surface)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4))
    }

    /// A small light in the corner: dim in the mode color, bright for a moment on each output.
    private var activityLight: some View {
        HStack(spacing: 4) {
            Text(verbatim: "MIDI").font(PanelFont.print(8)).tracking(1).foregroundStyle(Self.silkscreen.opacity(0.7))
            Circle()
                .fill(mode.color.opacity(flash ? 1 : 0.3))
                .frame(width: 8, height: 8)
                .shadow(color: mode.color.opacity(flash ? 0.9 : 0), radius: 4)
        }
        .accessibilityHidden(true)
    }

    private func row(_ buttons: [Footswitch]) -> some View {
        HStack(spacing: 0) {
            ForEach(buttons, id: \.self) { button in
                FootswitchView(
                    button: button, key: KeyCommand.footswitch(button).label(in: keys), isHeld: held.contains(button),
                    longPress: longPress,
                    onDown: { onDown(button) }, onUp: { onUp(button) })
                    .frame(width: Self.column)
            }
        }
    }

    /// The two print lines between the switches of a row: the hardware's two-switch combos.
    private func printLines(_ left: (String, NavigationStep), _ right: (String, NavigationStep)) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.column / 2)
            PrintLine(text: left.0, key: KeyCommand.navigate(left.1).label(in: keys), action: onNavigate.map { go in { go(left.1) } })
            PrintLine(text: right.0, key: KeyCommand.navigate(right.1).label(in: keys), action: onNavigate.map { go in { go(right.1) } })
            Color.clear.frame(width: Self.column / 2)
        }
    }

    /// One dot per page of the shown bank, the shown page bright.
    private var pageDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<pageCount, id: \.self) { index in
                Circle()
                    .fill(Self.silkscreen.opacity(index == page ? 0.95 : 0.25))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "Page \(page + 1) of \(pageCount)"))
    }
}

/// "— BANK DOWN —" as printed between two switches, with its key. With an action it is a click target that
/// lights up under the pointer. It uses a gesture, not a `Button`, so `ImageRenderer` draws it for snapshots.
private struct PrintLine: View {
    let text: String
    let key: String
    let action: (() -> Void)?

    private let hovering = State(initialValue: false)

    var body: some View {
        let lit = action != nil && hovering.wrappedValue
        HStack(spacing: 5) {
            Rectangle().fill(PanelView.silkscreen.opacity(0.5)).frame(height: 1)
            VStack(spacing: 2) {
                Text(verbatim: text).font(PanelFont.print(9)).tracking(1.2).fixedSize()
                Text(verbatim: key).font(PanelFont.print(9)).opacity(0.7)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(lit ? 0.12 : 0)))
            Rectangle().fill(PanelView.silkscreen.opacity(0.5)).frame(height: 1)
        }
        .foregroundStyle(lit ? Color.white : PanelView.silkscreen)
        .frame(width: PanelView.column - 104)
        .contentShape(Rectangle())
        .onHover { hovering.wrappedValue = $0 }
        .onTapGesture { action?() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text.capitalized))
        .accessibilityAddTraits(action == nil ? [] : .isButton)
        .accessibilityAction { action?() }
        .frame(width: PanelView.column)
    }
}
