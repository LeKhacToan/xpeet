import SwiftUI

/// 270° arc gauge, open at the bottom. Decorative: the number already carries the speed for VoiceOver.
struct MinimalRingFace: View {
    /// 0...1, how much of the arc is filled.
    let fraction: Double
    let theme: Theme
    let animation: Animation?

    /// Share of the full circle the arc covers.
    private static let sweep = GaugeGeometry.sweepAngle / 360

    var body: some View {
        GeometryReader { proxy in
            let lineWidth = min(proxy.size.width, proxy.size.height) * 0.07
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            ZStack {
                arc(to: Self.sweep, lineWidth: lineWidth)
                    .stroke(theme.color(theme.track), style: style)
                arc(to: Self.sweep * fraction, lineWidth: lineWidth)
                    .stroke(theme.arcGradient, style: style)
                    .shadow(color: Color(hex: theme.accent).opacity(Theme.glowOpacity), radius: lineWidth * 0.8)
                    .animation(animation, value: fraction)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// Starts at the lower left (7:30) and runs clockwise. Rotating the shape, not the view, keeps the gradient fixed.
    private func arc(to end: Double, lineWidth: CGFloat) -> some Shape {
        Circle()
            .inset(by: lineWidth / 2)
            .trim(from: 0, to: end)
            .rotation(.degrees(135))
    }
}

#Preview("Minimal ring") {
    MinimalRingFace(fraction: 0.65, theme: .minimalRing, animation: nil)
        .padding(40)
        .background(Theme.minimalRing.backgroundGradient)
}
