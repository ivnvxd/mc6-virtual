import SwiftUI

/// The panel at a zoom. `scaleEffect` alone draws larger but keeps the layout size, so this layout asks the panel
/// for its natural size and takes that size times the zoom. It needs one layout pass, so `ImageRenderer` draws it
/// the same way as the window does.
struct ZoomedPanel<Content: View>: View {
    /// 0.7 to 1.5.
    let zoom: Double
    @ViewBuilder let content: Content

    var body: some View {
        ScaledLayout(scale: zoom) {
            content.scaleEffect(zoom)
        }
    }
}

private struct ScaledLayout: Layout {
    let scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let natural = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: natural.width * scale, height: natural.height * scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let panel = subviews.first else { return }
        // The panel keeps its natural size. Its scale effect grows it around the center to fill the bounds.
        panel.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
            proposal: ProposedViewSize(panel.sizeThatFits(.unspecified)))
    }
}
