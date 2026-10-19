import SwiftUI

struct SpeedometerView: View {
    @State private var viewModel: SpeedometerViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: SpeedometerViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? SpeedometerViewModel())
    }

    var body: some View {
        GeometryReader { proxy in
            gauge(diameter: min(proxy.size.width, proxy.size.height))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .safeAreaInset(edge: .bottom, spacing: 0) { status }
        .background(Palette.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task(id: scenePhase) {
            if scenePhase == .active {
                await viewModel.run()
            }
        }
    }

    /// Nil with Reduce Motion on, so the number and the arc change instantly.
    private var motion: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.6)
    }

    private func gauge(diameter: CGFloat) -> some View {
        SpeedGauge(fraction: viewModel.gaugeFraction, animation: motion)
            .frame(width: diameter, height: diameter)
            .overlay {
                speed(fontSize: diameter * 0.4)
                    .frame(width: diameter * 0.72)
            }
            .overlay(alignment: .bottom) {
                // Lifts the pill into the gap between the arc's ends.
                unitButton.offset(y: -diameter * 0.05)
            }
    }

    private func speed(fontSize: CGFloat) -> some View {
        Text(viewModel.displayText)
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(viewModel.displayedSpeed == nil ? Palette.placeholder : .white)
            .lineLimit(1)
            .minimumScaleFactor(0.2)
            .contentTransition(reduceMotion ? .identity : .numericText(value: Double(viewModel.displayedSpeed ?? 0)))
            .animation(motion, value: viewModel.displayText)
            .accessibilityLabel(viewModel.accessibilityLabel)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var unitButton: some View {
        Button(action: viewModel.toggleUnit) {
            Text(viewModel.unitText)
                .font(.system(.title, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.brand)
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .frame(minWidth: 88, minHeight: 44)
                .background(Palette.brand.opacity(0.16), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .sensoryFeedback(.selection, trigger: viewModel.unit)
        .accessibilityLabel("Unit")
        .accessibilityValue(viewModel.unitAccessibilityValue)
        .accessibilityHint("Double-tap to switch")
    }

    private var status: some View {
        VStack(spacing: 12) {
            if let statusText = viewModel.statusText {
                Label {
                    Text(statusText)
                } icon: {
                    if let symbol = viewModel.statusSymbol {
                        Image(systemName: symbol)
                            .foregroundStyle(Palette.brand)
                            .accessibilityHidden(true)
                    }
                }
                .font(.callout.weight(.medium))
                .foregroundStyle(Palette.chipText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Palette.chipFill, in: Capsule())
            }
            if viewModel.canOpenSettings {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Text("Open Settings")
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.backgroundEdge)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.brand)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }
}

/// 270° arc gauge, open at the bottom. Decorative: the number already carries the speed for VoiceOver.
private struct SpeedGauge: View {
    /// 0...1, how much of the arc is filled.
    let fraction: Double
    let animation: Animation?

    /// Share of the full circle the arc covers.
    private static let sweep = 0.75

    var body: some View {
        GeometryReader { proxy in
            let lineWidth = min(proxy.size.width, proxy.size.height) * 0.07
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            ZStack {
                arc(to: Self.sweep, lineWidth: lineWidth)
                    .stroke(Palette.track, style: style)
                arc(to: Self.sweep * fraction, lineWidth: lineWidth)
                    .stroke(Palette.arc, style: style)
                    .shadow(color: Palette.brand.opacity(0.45), radius: lineWidth * 0.8)
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

private enum Palette {
    /// Pastel green `#9FE3B5`. Read from the asset directly: the environment tint is system blue in previews and renderers.
    static let brand = Color("AccentColor")
    static let backgroundCenter = Color(hex: 0x16231B)
    static let backgroundEdge = Color(hex: 0x0A0F0C)
    static let background = EllipticalGradient(
        colors: [backgroundCenter, backgroundEdge],
        center: .center,
        startRadiusFraction: 0,
        endRadiusFraction: 0.75
    )
    /// 7.7:1 on the background centre.
    static let placeholder = Color(white: 0.7)
    static let track = Color.white.opacity(0.1)
    /// Fixed brand gradient. It never depends on speed.
    static let arc = LinearGradient(
        colors: [Color(hex: 0x6CCB97), Palette.brand],
        startPoint: .bottomLeading,
        endPoint: .topTrailing
    )
    static let chipFill = Color.white.opacity(0.08)
    /// 6.9:1 on the chip fill.
    static let chipText = Color(white: 0.75)
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private extension SpeedometerViewModel {
    /// Preview ViewModel whose fixes never go stale.
    static func preview(authorization: LocationAuthorization = .authorized, kmh: Double? = nil) -> SpeedometerViewModel {
        let samples = kmh.map { [SpeedSample(metersPerSecond: $0 / 3.6, accuracy: 0.5, isStationary: false, timestamp: .now)] } ?? []
        return SpeedometerViewModel(
            provider: FakeSpeedProvider(authorization: authorization, samples: samples),
            defaults: UserDefaults(suiteName: "SpeedometerPreview") ?? .standard,
            locale: Locale(identifier: "fr_FR"),
            now: { .distantPast },
            setIdleTimerDisabled: { _ in }
        )
    }
}

#Preview("Live") {
    SpeedometerView(viewModel: .preview(kmh: 87))
}

#Preview("Live, landscape", traits: .landscapeLeft) {
    SpeedometerView(viewModel: .preview(kmh: 199))
}

#Preview("Above max") {
    SpeedometerView(viewModel: .preview(kmh: 250))
}

#Preview("Acquiring") {
    SpeedometerView(viewModel: .preview())
}

#Preview("Denied") {
    SpeedometerView(viewModel: .preview(authorization: .denied))
}

#Preview("Gauge") {
    SpeedGauge(fraction: 0.65, animation: nil)
        .padding(40)
        .background(Palette.background)
}
