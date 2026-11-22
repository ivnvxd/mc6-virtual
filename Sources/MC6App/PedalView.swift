import MC6Core
import SwiftUI

/// Expression pedal 1 as a small device next to the panel, in the material of the panel: 0 at the bottom and 127
/// at the top. Like the panel it has a natural size, and `ZoomedPanel` scales it.
struct PedalView: View {
    @Binding var value: Int
    /// The natural height: the height of the panel.
    let height: CGFloat
    /// The labels of the up key and the down key.
    let upKey: String
    let downKey: String
    /// What the pedal sends in the shown bank, one line for each message. Empty when it sends nothing.
    let targets: [String]
    var onHover: (Bool) -> Void = { _ in }

    static let width: CGFloat = 64

    var body: some View {
        VStack(spacing: 10) {
            Text(verbatim: "EXP 1").font(PanelFont.print(10)).tracking(1.2)
            track
            // The value as MIDI sends it, and the percentage that screen 3 shows.
            VStack(spacing: 0) {
                Text(verbatim: "\(value)").font(PanelFont.print(15)).monospacedDigit()
                Text(verbatim: "\(Int((Double(value) * 100 / 127).rounded()))%")
                    .font(PanelFont.print(10)).monospacedDigit().opacity(0.7)
            }
            HStack(spacing: 4) {
                KeyCap(key: upKey)
                KeyCap(key: downKey)
            }
        }
        .foregroundStyle(PanelView.silkscreen)
        .padding(.vertical, 16)
        .frame(width: Self.width, height: height)
        .deviceSurface()
        // A scroll anywhere over the pedal moves it (V17).
        .onHover(perform: onHover)
        .help(help)
    }

    private var help: String {
        targets.isEmpty
            ? "The pedal sends nothing in this bank: no expression message is active here."
            : "The pedal sends:\n" + targets.joined(separator: "\n")
    }

    /// A groove with the level and a thumb. The level is dim when the pedal sends nothing.
    private var track: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let level = height * CGFloat(value) / 127
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.black.opacity(0.55))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                RoundedRectangle(cornerRadius: 5)
                    .fill(PanelView.silkscreen.opacity(targets.isEmpty ? 0.2 : 0.55))
                    .frame(height: level)
                Capsule()
                    .fill(Color.white)
                    .frame(height: 4)
                    .padding(.horizontal, -3)
                    .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
                    .offset(y: -min(max(level - 2, 0), height - 4))
            }
            .contentShape(Rectangle().inset(by: -8))
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                value = min(127, max(0, Int(((1 - drag.location.y / height) * 127).rounded())))
            })
        }
        .frame(width: 26)
        .accessibilityElement()
        .accessibilityLabel("Expression 1")
        .accessibilityValue(String(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(127, value + 1)
            case .decrement: value = max(0, value - 1)
            @unknown default: break
            }
        }
    }
}
