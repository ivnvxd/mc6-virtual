import MC6Core
import SwiftUI

/// One metal footswitch with its printed letter, its key and a ring that fills to the long-press time.
struct FootswitchView: View {
    let button: Footswitch
    /// The label of its key; empty when no key presses it.
    let key: String
    let isHeld: Bool
    let longPress: Duration
    let onDown: () -> Void
    let onUp: () -> Void

    /// The hold ring, 0 to 1. Plain `State` storage: with Command Line Tools the `@State` macro has no plugin.
    private let progress = State(initialValue: 0.0)

    var body: some View {
        // The switch sits in the middle of its column, over the middle of its screen. Its letter and its key
        // sit at its lower right, below the print line.
        ZStack {
            Circle().fill(Color.black.opacity(0.22)).padding(3)
            Circle().stroke(Color.white.opacity(0.07), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress.wrappedValue)
                .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            knob
        }
        .frame(width: 76, height: 76)
        .contentShape(Circle())
        .modifier(Press(onDown: onDown, onUp: onUp))
        .overlay(alignment: .bottomTrailing) {
            HStack(alignment: .center, spacing: 4) {
                Text(verbatim: button.letter).font(PanelFont.print(15))
                KeyCap(key: key)
            }
            .foregroundStyle(PanelView.silkscreen)
            .fixedSize()
            // The leading edge goes 3 points left of the trailing edge of the switch, under its curve.
            .alignmentGuide(.trailing) { $0[.leading] + 3 }
            .alignmentGuide(.bottom) { $0[.bottom] - 4 }
        }
        .onChange(of: isHeld) { _, held in
            if held {
                progress.wrappedValue = 0
                withAnimation(.linear(duration: longPress / .seconds(1))) { progress.wrappedValue = 1 }
            } else {
                var snap = Transaction()
                snap.disablesAnimations = true
                withTransaction(snap) { progress.wrappedValue = 0 }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: key.isEmpty ? "Footswitch \(button.letter)" : "Footswitch \(button.letter), key \(key)"))
        .accessibilityAddTraits(.isButton)
        // VoiceOver presses the switch as a short tap.
        .accessibilityAction {
            onDown()
            onUp()
        }
    }

    /// A stomp switch from above, lit from the top left: a hex nut with chamfered corners, the dark gap of the
    /// bushing and a domed chrome cap. A held cap sits lower and darker.
    private var knob: some View {
        ZStack {
            nut
            Circle()
                .fill(RadialGradient(colors: Self.grays([0.02, 0.02, 0.16]), center: .center, startRadius: 0, endRadius: 22))
                .frame(width: 44, height: 44)
            cap
                .frame(width: 38, height: 38)
                .scaleEffect(isHeld ? 0.94 : 1)
                .shadow(color: .black.opacity(0.75), radius: isHeld ? 0.5 : 2.5, x: isHeld ? 0 : 1, y: isHeld ? 0.5 : 2)
        }
    }

    private static func grays(_ values: [Double]) -> [Color] { values.map { Color(white: $0) } }

    /// The six sides of the nut, each in its own tone, clockwise from the right corner. Only their chamfers show,
    /// as the corners outside the top face.
    private static let sides: [Double] = [0.34, 0.40, 0.58, 0.96, 0.84, 0.60]

    private var nut: some View {
        ZStack {
            Hexagon()
                .fill(AngularGradient(
                    stops: Self.sides.enumerated().flatMap { index, tone in
                        [
                            Gradient.Stop(color: Color(white: tone), location: Double(index) / 6),
                            Gradient.Stop(color: Color(white: tone), location: Double(index + 1) / 6),
                        ]
                    },
                    center: .center))
                .overlay(Hexagon().stroke(Color.black.opacity(0.7), lineWidth: 0.75))
                .frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.7), radius: 3, x: 1.5, y: 3)
            // The turned top face, with a dark edge toward the bushing.
            Circle()
                .fill(AngularGradient(
                    colors: Self.grays([0.62, 0.86, 0.56, 0.82, 0.6, 0.9, 0.58, 0.8, 0.62]), center: .center, angle: .degrees(25)))
                .overlay(Circle().strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.75), Color.white.opacity(0.1), Color.black.opacity(0.35)],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1))
                .frame(width: 54, height: 54)
        }
    }

    /// A chrome dome: bright toward the light and dark away from it, with no separate light spot.
    private var cap: some View {
        ZStack {
            Circle().fill(RadialGradient(
                colors: Self.grays([0.99, 0.86, 0.58, 0.26]), center: UnitPoint(x: 0.36, y: 0.3), startRadius: 0, endRadius: 27))
            Circle().strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.6), Color.black.opacity(0.2), Color.black.opacity(0.7)],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1)
            if isHeld { Circle().fill(Color.black.opacity(0.32)) }
        }
    }
}

/// A regular hexagon with a flat side at the top, inside the circle of its frame.
private struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for corner in 0..<6 {
            let angle = CGFloat(corner) * .pi / 3
            let point = CGPoint(x: rect.midX + radius * cos(angle), y: rect.midY + radius * sin(angle))
            if corner == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// A press with the mouse, for a switch and for its band on the screen. The down counts at once, and the up
/// counts wherever the pointer is.
struct Press: ViewModifier {
    let onDown: () -> Void
    let onUp: () -> Void

    /// True from the first change of a drag to its end. A drag presses once, so a drag that outlives a focus loss
    /// does not press again. `GestureState` goes back to false when the drag ends and also when SwiftUI cancels it,
    /// which calls no `onEnded`. Plain storage, because the `@GestureState` macro is not available.
    private let dragging = GestureState(initialValue: false)

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating(dragging) { _, down, _ in
                        guard !down else { return }
                        down = true
                        onDown()
                    }
                    .onEnded { _ in onUp() })
            // A canceled drag lets go of the button too. After `onEnded` this second up does nothing.
            .onChange(of: dragging.wrappedValue) { _, down in
                if !down { onUp() }
            }
    }
}

/// A key of the Mac keyboard as a filled keycap, so it does not read as a print letter of the panel.
/// An empty key keeps its place, so the layout does not move.
struct KeyCap: View {
    let key: String

    var body: some View {
        Text(verbatim: key.isEmpty ? " " : key)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(PanelView.surface)
            .frame(minWidth: 9)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(PanelView.silkscreen.opacity(0.85)))
            .opacity(key.isEmpty ? 0 : 1)
            .accessibilityHidden(true)
    }
}
