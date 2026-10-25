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

    /// Nil with Reduce Motion on, so the number and the gauge change instantly. Short and linear so the gauge never
    /// trails the reading by more than 0.1 s, even at about 10 updates a second (specs/speed-accuracy R16).
    private var motion: Animation? {
        animated && !reduceMotion ? .linear(duration: 0.1) : nil
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
            MinimalRingFace(fraction: reading.fraction, unit: reading.unit, theme: theme, animation: motion)
                .frame(width: diameter, height: diameter)
                .overlay {
                    speed(fontSize: diameter * 0.4)
                        .frame(width: diameter * 0.72)
                }
                .overlay(alignment: .top) {
                    SpeedCaption(theme: theme, size: diameter * 0.045)
                        .padding(.top, diameter * 0.26)
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
                .overlay {
                    if face == .analogSport {
                        // Above the number, still inside the centre disc.
                        SpeedCaption(theme: theme, size: diameter * 0.032)
                            .offset(y: -diameter * 0.165)
                    }
                }
                .overlay(alignment: .bottom) { bottomPill(diameter: diameter) }
        case .digitalHUD:
            VStack(spacing: diameter * 0.035) {
                speed(fontSize: diameter * 0.36)
                    .frame(width: diameter * 0.8)
                    .background {
                        // Soft glow behind the readout.
                        Ellipse()
                            .fill(RadialGradient(
                                colors: [Color(hex: theme.accent).opacity(0.22), .clear],
                                center: .center, startRadius: 0, endRadius: diameter * 0.45
                            ))
                            .frame(width: diameter * 1.1, height: diameter * 0.6)
                    }
                unitControl
                    .frame(maxWidth: diameter * 0.5)
                // Inside the frame's circle (specs/ui-redesign R12).
                SegmentBar(fraction: reading.fraction, theme: theme, animation: motion)
                    .frame(width: diameter * 0.62, height: diameter * 0.05)
            }
            .frame(width: diameter, height: diameter)
            .background { HUDFrame(theme: theme).equatable() }
            .background { Scanlines(theme: theme).equatable().clipShape(Circle()) }
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
            .font(theme.font(role: .number, size: fontSize))
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

/// The unit as a frosted-glass pill with a swap glyph (specs/ui-redesign R15). Wrapped in a Button on the speed screen.
struct UnitPill: View {
    let text: String
    let theme: Theme
    /// Small, fixed-size variant for picker thumbnails: no glass, no glyph.
    var compact = false

    var body: some View {
        if compact {
            Text(text.uppercased())
                .font(.custom(Theme.captionTypeface, fixedSize: 10))
                .lineLimit(1)
                .foregroundStyle(Color(hex: theme.accent))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color(hex: theme.accent).opacity(Theme.pillTintOpacity), in: Capsule())
        } else {
            HStack(spacing: 8) {
                Text(text.uppercased())
                    .kerning(1.2)
                Image(systemName: "arrow.up.arrow.down")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            .font(Theme.captionFont(textStyle: .title3, size: 18))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(Color(hex: theme.accent))
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(minWidth: 96, minHeight: 44)
            .background {
                GlassBackground(
                    shape: Capsule(),
                    tint: Color(hex: theme.accent).opacity(Theme.pillTintOpacity),
                    colorScheme: theme.colorScheme
                )
            }
            .contentShape(Capsule())
        }
    }
}

/// "SPEED" with a trend glyph, above the number (specs/ui-redesign R10, R11). Sized by the gauge, decorative.
struct SpeedCaption: View {
    let theme: Theme
    let size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.35) {
            Image(systemName: "arrow.up.right")
                .font(.system(size: size * 0.85, weight: .bold))
                .foregroundStyle(Color(hex: theme.accent))
            Text("SPEED")
                .font(.custom(Theme.captionTypeface, fixedSize: size))
                .kerning(size * 0.12)
                .foregroundStyle(Color(hex: theme.secondaryText))
        }
        .lineLimit(1)
        .accessibilityHidden(true)
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
