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
    /// True from the first change of a drag to its end. A drag presses once, so a drag that outlives a focus loss
    /// does not press again. `GestureState` goes back to false when the drag ends and also when SwiftUI cancels it,
    /// which calls no `onEnded`. Plain storage, like `progress`.
    private let dragging = GestureState(initialValue: false)

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.07), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress.wrappedValue)
                    .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                knob.scaleEffect(isHeld ? 0.93 : 1)
            }
            .frame(width: 76, height: 76)
            .contentShape(Circle())
            // Minimum distance 0: the down counts at once and the up counts wherever the pointer is.
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
            VStack(spacing: 4) {
                Text(verbatim: button.letter).font(PanelFont.print(15))
                Text(verbatim: key)
                    .font(PanelFont.print(9))
                    .frame(minWidth: 14, minHeight: 14)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(PanelView.silkscreen.opacity(key.isEmpty ? 0 : 0.5)))
            }
            .foregroundStyle(PanelView.silkscreen)
            .padding(.bottom, 4)
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
    }

    /// Brushed steel with a knurled cap.
    private var knob: some View {
        ZStack {
            Circle().fill(RadialGradient(
                colors: [Color(white: 0.92), Color(white: 0.62), Color(white: 0.42)],
                center: UnitPoint(x: 0.4, y: 0.35), startRadius: 2, endRadius: 34))
            Circle()
                .fill(RadialGradient(
                    colors: [Color(white: isHeld ? 0.62 : 0.8), Color(white: 0.55)],
                    center: UnitPoint(x: 0.45, y: 0.4), startRadius: 1, endRadius: 20))
                .padding(13)
            Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1)
        }
        .frame(width: 62, height: 62)
        .shadow(color: .black.opacity(0.5), radius: isHeld ? 1 : 3, y: isHeld ? 1 : 2)
    }
}
