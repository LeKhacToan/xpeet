import SwiftUI

struct SpeedometerView: View {
    @State private var viewModel: SpeedometerViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .title) private var unitFontSize: CGFloat = 32

    /// Secondary grey on black: 8:1 contrast.
    private static let secondary = Color(white: 0.62)

    init(viewModel: SpeedometerViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? SpeedometerViewModel())
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                speed(fontSize: min(proxy.size.width, proxy.size.height) * 0.5)
                unitButton
                Spacer(minLength: 0)
                status
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task(id: scenePhase) {
            if scenePhase == .active {
                await viewModel.run()
            }
        }
    }

    private func speed(fontSize: CGFloat) -> some View {
        Text(viewModel.displayText)
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.2)
            .contentTransition(.numericText(value: Double(viewModel.displayedSpeed ?? 0)))
            .animation(.smooth(duration: 0.6), value: viewModel.displayText)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(viewModel.accessibilityLabel)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var unitButton: some View {
        Button(action: viewModel.toggleUnit) {
            Text(viewModel.unitText)
                .font(.system(size: unitFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(Self.secondary)
                .frame(minWidth: 88, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Unit")
        .accessibilityValue(viewModel.unitAccessibilityValue)
        .accessibilityHint("Double-tap to switch")
    }

    private var status: some View {
        VStack(spacing: 12) {
            if let statusText = viewModel.statusText {
                Text(statusText)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Self.secondary)
                    .multilineTextAlignment(.center)
            }
            if viewModel.canOpenSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.top, 12)
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

#Preview("Acquiring") {
    SpeedometerView(viewModel: .preview())
}

#Preview("Denied") {
    SpeedometerView(viewModel: .preview(authorization: .denied))
}
