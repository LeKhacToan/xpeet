import SwiftUI

/// 270° arc gauge, open at the bottom. Decorative: the number already carries the speed for VoiceOver.
struct MinimalRingFace: View {
    /// 0...1, how much of the arc is filled.
    let fraction: Double
    let unit: SpeedUnit
    let theme: Theme
    let animation: Animation?

    /// Share of the full circle the arc covers.
    private static let sweep = GaugeGeometry.sweepAngle / 360
    /// Band outside the ring kept for the faint scale ticks, as a share of the diameter (specs/ui-redesign R10).
    private static let tickBand = 0.045

    var body: some View {
        GeometryReader { proxy in
            let fullDiameter = min(proxy.size.width, proxy.size.height)
            let diameter = fullDiameter * (1 - 2 * Self.tickBand)
            let lineWidth = fullDiameter * 0.06
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let tipAngle = Angle.degrees(135 + GaugeGeometry.sweepAngle * min(max(fraction, 0), 1))
            let tipRadius = (diameter - lineWidth) / 2
            ZStack {
                RingTicks(unit: unit, theme: theme)
                    .equatable()
                    .frame(width: fullDiameter, height: fullDiameter)
                ring(diameter: diameter, lineWidth: lineWidth, style: style)
                    .frame(width: diameter, height: diameter)
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

    private func ring(diameter: CGFloat, lineWidth: CGFloat, style: StrokeStyle) -> some View {
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
        }
    }

    /// Starts at the lower left (7:30) and runs clockwise. Rotating the shape, not the view, keeps the gradient fixed.
    private func arc(to end: Double, lineWidth: CGFloat) -> some Shape {
        Circle()
            .inset(by: lineWidth / 2)
            .trim(from: 0, to: end)
            .rotation(.degrees(135))
    }
}

/// Faint marks at every other major scale value (0, 40, 80, …), just outside the ring. Static: redrawn on unit change only.
private struct RingTicks: View, Equatable {
    let unit: SpeedUnit
    let theme: Theme

    var body: some View {
        Canvas { context, size in
            let diameter = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = diameter / 2
            let inner = outer - diameter * 0.03
            let majors = GaugeGeometry.ticks(for: unit).filter(\.isMajor)
            var path = Path()
            for (index, tick) in majors.enumerated() where index.isMultiple(of: 2) {
                let angle = Angle.degrees(GaugeGeometry.angle(for: tick.value, maximum: unit.gaugeMaximum))
                path.move(to: CGPoint(x: center.x + outer * sin(angle.radians), y: center.y - outer * cos(angle.radians)))
                path.addLine(to: CGPoint(x: center.x + inner * sin(angle.radians), y: center.y - inner * cos(angle.radians)))
            }
            let style = StrokeStyle(lineWidth: 1.5, lineCap: .round)
            context.stroke(path, with: .color(Color(hex: theme.scaleLabel).opacity(0.35)), style: style)
        }
        .allowsHitTesting(false)
    }
}

#Preview("Minimal ring") {
    MinimalRingFace(fraction: 0.65, unit: .kmh, theme: .minimalRing, animation: nil)
        .padding(40)
        .background(Theme.minimalRing.backgroundGradient)
}
