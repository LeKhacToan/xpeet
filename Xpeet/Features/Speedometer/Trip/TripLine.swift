import SwiftUI

/// The trip's distance and moving time as a quiet frosted capsule (specs/trip-stats R11-R12, frames
/// `portrait-trip-line`, `landscape-trip-line`). Read-only text; the speed screen wraps it in a button.
struct TripLine: View {
    /// "12.4 km · 18 min".
    let text: String
    let theme: Theme
    /// Over the map the capsule is opaque, so tiles never show behind the text (specs/osm-map R4).
    var isOpaque = false

    static let separator = " · "

    /// Distance and time, for the two-line layouts.
    private var parts: [String] { text.components(separatedBy: Self.separator) }

    var body: some View {
        // Widest layout that fits; the last one always fits because its lines shrink (specs/trip-stats R12).
        ViewThatFits(in: .horizontal) {
            capsule(glyphs: true) { Text(text).lineLimit(1) }
            capsule(glyphs: true) { stacked(shrinks: false) }
            capsule(glyphs: false) { stacked(shrinks: true) }
        }
        .font(Theme.captionFont(textStyle: .footnote, size: 13).monospacedDigit())
        .foregroundStyle(Color(hex: theme.secondaryText))
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    /// Distance over time, one line each, never wrapping inside a value.
    private func stacked(shrinks: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(parts, id: \.self) { part in
                Text(part)
                    .lineLimit(1)
                    .minimumScaleFactor(shrinks ? 0.5 : 1)
            }
        }
    }

    private func capsule(glyphs: Bool, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 8) {
            if glyphs {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            content()
            if glyphs {
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .opacity(0.6)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, glyphs ? 16 : 12)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .background {
            if isOpaque {
                MapCardBackground(shape: Capsule(), theme: theme)
            } else {
                GlassBackground(shape: Capsule(), tint: theme.color(theme.chipFill), colorScheme: theme.colorScheme)
            }
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

#Preview("Narrow: iPhone SE and 15 Pro landscape, large text") {
    VStack(spacing: 16) {
        ForEach([CGFloat(118), 153], id: \.self) { width in
            ForEach([DynamicTypeSize.large, .accessibility2], id: \.self) { size in
                TripLine(text: "142 km · 1 h 05 min", theme: GaugeFace.minimalRing.theme)
                    .frame(maxWidth: width)
                    .environment(\.dynamicTypeSize, size)
            }
        }
    }
    .padding()
    .background(GaugeFace.minimalRing.theme.backgroundGradient)
}
