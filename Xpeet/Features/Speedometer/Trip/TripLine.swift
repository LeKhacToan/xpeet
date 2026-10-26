import SwiftUI

/// The trip's distance and moving time as a quiet frosted capsule (specs/trip-stats R11-R12, frames
/// `portrait-trip-line`, `landscape-trip-line`). Read-only text; the speed screen wraps it in a button.
struct TripLine: View {
    /// "12.4 km · 18 min".
    let text: String
    let theme: Theme

    static let separator = " · "

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .imageScale(.small)
                .accessibilityHidden(true)
            // One line where it fits; distance over time in a narrow landscape space.
            ViewThatFits(in: .horizontal) {
                Text(text)
                Text(text.replacingOccurrences(of: Self.separator, with: "\n"))
                    .multilineTextAlignment(.leading)
            }
            .lineLimit(2)
            Image(systemName: "chevron.right")
                .imageScale(.small)
                .opacity(0.6)
                .accessibilityHidden(true)
        }
        .font(Theme.captionFont(textStyle: .footnote, size: 13).monospacedDigit())
        .foregroundStyle(Color(hex: theme.secondaryText))
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .background {
            GlassBackground(shape: Capsule(), tint: theme.color(theme.chipFill), colorScheme: theme.colorScheme)
        }
        .contentShape(Capsule())
    }
}

#Preview("All faces") {
    VStack(spacing: 16) {
        ForEach(GaugeFace.allCases) { face in
            TripLine(text: "12.4 km · 18 min", theme: face.theme)
                .padding()
                .frame(maxWidth: .infinity)
                .background(face.theme.backgroundGradient)
        }
    }
}

#Preview("Narrow, two lines") {
    TripLine(text: "142 km · 1 h 05 min", theme: GaugeFace.minimalRing.theme)
        .frame(width: 120)
        .padding()
        .background(GaugeFace.minimalRing.theme.backgroundGradient)
}
