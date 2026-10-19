import MC6Core
import SwiftUI

extension Color {
    init(_ rgb: RGB) {
        self.init(.sRGB, red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }
}

/// Fonts of the panel. Avenir Next is close to the geometric sans of the hardware screens and print,
/// and its condensed cut fits long preset names on a small screen.
enum PanelFont {
    static func name(_ size: CGFloat) -> Font { .custom("AvenirNextCondensed-Heavy", size: size) }
    static func center(_ size: CGFloat) -> Font { .custom("AvenirNextCondensed-DemiBold", size: size) }
    static func print(_ size: CGFloat) -> Font { .custom("AvenirNext-Medium", size: size) }
}

/// A name of text and SF Symbols as one `Text`, so it scales and wraps as a unit.
func nameText(_ parts: [NamePart]) -> Text {
    parts.reduce(Text(verbatim: "")) { text, part in
        switch part {
        case .text(let string): text + Text(verbatim: string)
        case .icon(let symbol): text + Text(Image(systemName: symbol))
        }
    }
}

/// One color screen of the panel: the upper switch's band, the white center band and the lower switch's band.
/// The LED strips sit on the outer edges, toward their switches.
struct ScreenView: View {
    let screen: Screen
    /// 0.3 to 1: the backup's or the custom screen brightness.
    let brightness: Double
    /// The held switches. Their bands light up (V13).
    var held: Set<Footswitch> = []

    static let size: CGFloat = 156
    private static let strip: CGFloat = 5
    private static let band: CGFloat = 46

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color(screen.top.strip)).frame(height: Self.strip)
            band(screen.top)
            Spacer(minLength: 0)
            center
            Spacer(minLength: 0)
            band(screen.bottom)
            Rectangle().fill(Color(screen.bottom.strip)).frame(height: Self.strip)
        }
        .frame(width: Self.size, height: Self.size)
        .background(Color.black)
        // A backlit screen stays readable when dimmed, so 30% brightness darkens by less than 70%.
        .overlay(Color.black.opacity((1 - brightness) * 0.65).allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        // One glow for the whole glass, not one for each text inside it.
        .compositingGroup()
        .shadow(color: Color(screen.top.strip).opacity(0.35 * brightness), radius: 8, y: -2)
        .shadow(color: Color(screen.bottom.strip).opacity(0.35 * brightness), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
    }

    private func band(_ band: Band) -> some View {
        nameText(band.parts)
            .font(PanelFont.name(26))
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            .foregroundStyle(Color(band.text))
            // Room for the letter and the "2" mark in the corners.
            .padding(.leading, band.letter == nil ? 6 : 18)
            .padding(.trailing, band.position == .two ? 18 : 6)
            .frame(maxWidth: .infinity, minHeight: Self.band, maxHeight: Self.band)
            .background(Color(band.background))
            .overlay {
                if held.contains(band.button) {
                    Rectangle().fill(Color.white.opacity(0.22))
                        .overlay(Rectangle().strokeBorder(Color.white.opacity(0.9), lineWidth: 2))
                }
            }
            .overlay(alignment: .topLeading) {
                if let letter = band.letter { mark(letter, band) }
            }
            .overlay(alignment: .topTrailing) {
                // Color is never the only sign of Position 2 (spec 11).
                if band.position == .two { mark("2", band) }
            }
            .accessibilityLabel(Text(verbatim: "\(band.button.letter): ") + nameText(band.parts)
                + Text(band.position == .two ? ", position 2" : ""))
    }

    private func mark(_ text: String, _ band: Band) -> some View {
        Text(verbatim: text)
            .font(PanelFont.center(10))
            .foregroundStyle(Color(band.background))
            .padding(.horizontal, 3)
            .background(RoundedRectangle(cornerRadius: 2).fill(Color(band.text)))
            .padding(3)
    }

    private var center: some View {
        VStack(spacing: 0) {
            ForEach(Array(screen.center.enumerated()), id: \.offset) { _, line in
                nameText(line)
                    .font(PanelFont.center(screen.center.count == 1 ? 21 : 14))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Color.black)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Color.white)
    }
}
