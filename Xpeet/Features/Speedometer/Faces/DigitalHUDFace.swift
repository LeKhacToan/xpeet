import SwiftUI

/// Horizontal bar of segments for the Digital HUD face. Decorative for VoiceOver.
struct SegmentBar: View {
    let fraction: Double
    let theme: Theme
    let animation: Animation?

    var body: some View {
        let lit = GaugeGeometry.litSegments(fraction: fraction)
        HStack(spacing: 3) {
            ForEach(0..<GaugeGeometry.segmentCount, id: \.self) { index in
                let isLit = index < lit
                Capsule()
                    .fill(isLit ? Color(hex: theme.accent) : theme.color(theme.track))
                    .shadow(color: Color(hex: theme.accent).opacity(isLit ? 0.8 : 0), radius: 4)
            }
        }
        .animation(animation, value: lit)
        .accessibilityHidden(true)
    }
}

#Preview("Segment bar") {
    SegmentBar(fraction: 0.55, theme: .digitalHUD, animation: nil)
        .frame(height: 20)
        .padding(32)
        .background(Theme.digitalHUD.backgroundGradient)
}
