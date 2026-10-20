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
            let diameter = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let tipAngle = Angle.degrees(135 + GaugeGeometry.sweepAngle * min(max(fraction, 0), 1))
            let tipRadius = (diameter - lineWidth) / 2
            ZStack {
                // Bezel just outside the track, and a soft inner glow inside it.
                Circle()
                    .strokeBorder(theme.color(theme.track).opacity(0.6), lineWidth: lineWidth * 0.12)
                Circle()
                    .inset(by: lineWidth * 1.1)
                    .fill(RadialGradient(
                        colors: [.clear, Color(hex: theme.accent).opacity(0.14)],
                        center: .center, startRadius: diameter * 0.2, endRadius: diameter * 0.5
                    ))
                arc(to: Self.sweep, lineWidth: lineWidth)
                    .stroke(theme.color(theme.track), style: style)
                arc(to: Self.sweep * fraction, lineWidth: lineWidth)
                    .stroke(theme.arcGradient, style: style)
                    .shadow(color: Color(hex: theme.accent).opacity(Theme.glowOpacity), radius: lineWidth * 0.8)
                    .animation(animation, value: fraction)
                // Bright tip at the leading end of the progress arc.
                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: lineWidth * 0.45)
                    .shadow(color: .white.opacity(0.8), radius: lineWidth * 0.4)
                    .position(x: center.x + tipRadius * cos(tipAngle.radians), y: center.y + tipRadius * sin(tipAngle.radians))
                    .opacity(fraction > 0 ? 1 : 0)
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
