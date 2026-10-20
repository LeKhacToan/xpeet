import SwiftUI

/// What a face shows. Built by the View from ViewModel outputs; no logic of its own.
struct GaugeReading: Equatable {
    var displayText: String
    /// Nil when there is no live reading ("--").
    var value: Int?
    var fraction: Double
    var unit: SpeedUnit

    /// Fixed reading for picker thumbnails: 88, live, no status.
    static func sample(unit: SpeedUnit) -> GaugeReading {
        let value = 88
        return GaugeReading(
            displayText: String(value),
            value: value,
            fraction: unit.gaugeFraction(for: value),
            unit: unit
        )
    }
}

/// Lays out one face: its drawing, the number and the unit control.
/// Shared by the speed screen and the picker thumbnails, so both always look the same.
struct GaugeDisplay<UnitControl: View>: View {
    let face: GaugeFace
    let reading: GaugeReading
    /// False for thumbnails: no transitions at all.
    var animated = true
    var accessibilityLabel: String?
    @ViewBuilder let unitControl: UnitControl

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: Theme { face.theme }

    /// Nil with Reduce Motion on, so the number and the gauge change instantly.
    private var motion: Animation? {
        animated && !reduceMotion ? .smooth(duration: 0.6) : nil
    }

    var body: some View {
        GeometryReader { proxy in
            gauge(diameter: min(proxy.size.width, proxy.size.height))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func gauge(diameter: CGFloat) -> some View {
        switch face {
        case .minimalRing:
            MinimalRingFace(fraction: reading.fraction, theme: theme, animation: motion)
                .frame(width: diameter, height: diameter)
                .overlay {
                    speed(fontSize: diameter * 0.4)
                        .frame(width: diameter * 0.72)
                }
                .overlay(alignment: .bottom) { bottomPill(diameter: diameter) }
        case .analogSport, .retro:
            DialFace(fraction: reading.fraction, unit: reading.unit, theme: theme, animation: motion)
                .frame(width: diameter, height: diameter)
                .overlay {
                    // Inside the centre disc; 0.4 of the diameter keeps "199" within the disc's 0.5.
                    speed(fontSize: diameter * 0.2)
                        .frame(width: diameter * 0.4)
                }
                .overlay(alignment: .bottom) { bottomPill(diameter: diameter) }
        case .digitalHUD:
            VStack(spacing: diameter * 0.04) {
                speed(fontSize: diameter * 0.42)
                    .frame(width: diameter * 0.9)
                unitControl
                    .frame(maxWidth: diameter * 0.55)
                SegmentBar(fraction: reading.fraction, theme: theme, animation: motion)
                    .frame(width: diameter * 0.86, height: diameter * 0.07)
            }
            .frame(width: diameter, height: diameter)
        }
    }

    /// Lifts the pill into the gap between the arc's or dial's ends.
    private func bottomPill(diameter: CGFloat) -> some View {
        unitControl
            .frame(maxWidth: diameter * 0.55)
            .offset(y: -diameter * 0.05)
    }

    private func speed(fontSize: CGFloat) -> some View {
        Text(reading.displayText)
            .font(.system(size: fontSize, weight: .heavy, design: theme.design.font))
            .monospacedDigit()
            .foregroundStyle(Color(hex: reading.value == nil ? theme.placeholder : theme.number))
            .lineLimit(1)
            .minimumScaleFactor(0.2)
            .contentTransition(motion == nil ? .identity : .numericText(value: Double(reading.value ?? 0)))
            .animation(motion, value: reading.displayText)
            .speedAccessibility(accessibilityLabel)
    }
}

private extension View {
    /// The speed element's VoiceOver label; hidden entirely when there is none (thumbnails).
    @ViewBuilder
    func speedAccessibility(_ label: String?) -> some View {
        if let label {
            accessibilityLabel(label).accessibilityAddTraits(.updatesFrequently)
        } else {
            accessibilityHidden(true)
        }
    }
}

/// The unit label as a tinted capsule. Wrapped in a Button on the speed screen.
struct UnitPill: View {
    let text: String
    let theme: Theme
    /// Small, fixed-size variant for picker thumbnails.
    var compact = false

    var body: some View {
        Text(text)
            .font(compact ? .system(size: 11, weight: .semibold, design: theme.design.font)
                : .system(.title, design: theme.design.font, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(Color(hex: theme.accent))
            .padding(.horizontal, compact ? 8 : 20)
            .padding(.vertical, compact ? 2 : 6)
            .frame(minWidth: compact ? 0 : 88, minHeight: compact ? 0 : 44)
            .background(Color(hex: theme.accent).opacity(Theme.pillTintOpacity), in: Capsule())
            .contentShape(Capsule())
    }
}

#Preview("All faces") {
    ScrollView {
        ForEach(GaugeFace.allCases) { face in
            GaugeDisplay(face: face, reading: .sample(unit: .kmh), animated: false) {
                UnitPill(text: SpeedUnit.kmh.symbol, theme: face.theme)
            }
            .frame(height: 320)
            .padding()
            .background(face.theme.backgroundGradient)
        }
    }
}

#Preview("Unit pill") {
    VStack(spacing: 16) {
        ForEach(GaugeFace.allCases) { face in
            HStack {
                UnitPill(text: "km/h", theme: face.theme)
                UnitPill(text: "mph", theme: face.theme, compact: true)
            }
            .padding()
            .background(face.theme.backgroundGradient)
        }
    }
}
