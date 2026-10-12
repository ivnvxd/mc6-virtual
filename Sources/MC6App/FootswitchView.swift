import MC6Core
import SwiftUI

extension Footswitch {
    var letter: String { ["A", "B", "C", "D", "E", "F"][rawValue] }
    /// The key that presses it, by physical position.
    var key: String { ["A", "S", "D", "Q", "W", "E"][rawValue] }
}

/// One footswitch: its letter and key, the backup name, the position, and a ring that fills to the long-press time.
struct FootswitchView: View {
    let display: ButtonDisplay
    let isHeld: Bool
    let longPress: Duration
    let onDown: () -> Void
    let onUp: () -> Void

    /// The hold ring, 0 to 1. Plain `State` storage: with Command Line Tools the `@State` macro has no plugin.
    private let progress = State(initialValue: 0.0)
    /// True from the first change of a drag to its end. A drag presses once, so a drag that outlives a focus loss
    /// does not press again.
    private let dragging = State(initialValue: false)

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress.wrappedValue)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle()
                    .fill(isHeld ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.15))
                    .padding(10)
                Text(verbatim: display.button.letter).font(.title.bold())
            }
            .frame(width: 88, height: 88)
            .contentShape(Circle())
            // Minimum distance 0: the down counts at once and the up counts wherever the pointer is.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !dragging.wrappedValue else { return }
                        dragging.wrappedValue = true
                        onDown()
                    }
                    .onEnded { _ in
                        dragging.wrappedValue = false
                        onUp()
                    })

            Text(verbatim: display.name)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 40)
            HStack(spacing: 6) {
                Text(verbatim: "Key \(display.button.key)").foregroundStyle(.secondary)
                Text(verbatim: display.position == .two ? "Position 2" : "Position 1")
                    .padding(.horizontal, 6)
                    .background(
                        Capsule().fill(display.position == .two ? Color.orange.opacity(0.35) : Color.clear))
            }
            .font(.caption)
        }
        .frame(width: 170)
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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
