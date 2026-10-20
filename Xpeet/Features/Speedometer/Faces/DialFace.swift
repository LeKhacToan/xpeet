import SwiftUI

/// Round dial with ticks, scale labels and a needle. Used by Analog sport and Retro. Decorative for VoiceOver.
struct DialFace: View {
    /// Share of the dial diameter taken by the centre disc that holds the number.
    static let discDiameter = 0.5
    /// Needle span, as fractions of the diameter from the centre.
    private static let needleInner = 0.25
    private static let needleOuter = 0.46

    let fraction: Double
    let unit: SpeedUnit
    let theme: Theme
    let animation: Animation?

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            ZStack {
                DialScale(unit: unit, theme: theme)
                    .equatable()
                Needle()
                    .fill(Color(hex: theme.accent))
                    .frame(width: diameter * 0.035, height: diameter * (Self.needleOuter - Self.needleInner))
                    .shadow(color: Color(hex: theme.accent).opacity(theme.colorScheme == .dark ? Theme.glowOpacity : 0), radius: 6)
                    // The needle points up and runs between the centre disc and the rim; rotating about the dial centre.
                    .offset(y: -diameter * (Self.needleOuter + Self.needleInner) / 2)
                    .rotationEffect(.degrees(GaugeGeometry.needleAngle(fraction: fraction)))
                    .animation(animation, value: fraction)
                // The number sits on this disc, so neither the needle nor the scale labels ever cross it.
                Circle()
                    .fill(Color(hex: theme.backgroundCenter))
                    .overlay { Circle().strokeBorder(theme.color(theme.track), lineWidth: diameter * 0.006) }
                    .frame(width: diameter * Self.discDiameter)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The static part of the dial. Equatable so it redraws only when the unit or theme changes, not per sample.
private struct DialScale: View, Equatable {
    let unit: SpeedUnit
    let theme: Theme

    var body: some View {
        Canvas { context, size in
            let diameter = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = diameter / 2 - diameter * 0.02
            let maximum = unit.gaugeMaximum

            var rim = Path()
            rim.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(GaugeGeometry.startAngle - 90),
                endAngle: .degrees(GaugeGeometry.startAngle + GaugeGeometry.sweepAngle - 90),
                clockwise: false
            )
            context.stroke(rim, with: .color(theme.color(theme.track)), lineWidth: diameter * 0.006)

            for tick in GaugeGeometry.ticks(for: unit) {
                let angle = Angle.degrees(GaugeGeometry.angle(for: tick.value, maximum: maximum))
                let length = diameter * (tick.isMajor ? 0.07 : 0.04)
                var line = Path()
                line.move(to: point(center, radius, angle))
                line.addLine(to: point(center, radius - length, angle))
                let color = tick.isMajor ? Color(hex: theme.scaleLabel) : theme.color(theme.track)
                context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: diameter * (tick.isMajor ? 0.012 : 0.007), lineCap: .round))

                if let label = tick.label {
                    let text = Text(label)
                        .font(.system(size: diameter * 0.06, weight: .semibold, design: theme.design.font))
                        .monospacedDigit()
                        .foregroundColor(Color(hex: theme.scaleLabel))
                    context.draw(context.resolve(text), at: point(center, radius - diameter * 0.14, angle))
                }
            }
        }
    }

    /// Point on the dial for an angle measured clockwise from 12 o'clock.
    private func point(_ center: CGPoint, _ radius: CGFloat, _ angle: Angle) -> CGPoint {
        CGPoint(x: center.x + radius * sin(angle.radians), y: center.y - radius * cos(angle.radians))
    }
}

/// A tapered needle pointing up, filling its frame.
private struct Needle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.width / 2))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - rect.width / 2), control: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview("Analog sport") {
    DialFace(fraction: 0.44, unit: .kmh, theme: .analogSport, animation: nil)
        .padding(32)
        .background(Theme.analogSport.backgroundGradient)
}

#Preview("Retro, mph") {
    DialFace(fraction: 0.68, unit: .mph, theme: .retro, animation: nil)
        .padding(32)
        .background(Theme.retro.backgroundGradient)
}
