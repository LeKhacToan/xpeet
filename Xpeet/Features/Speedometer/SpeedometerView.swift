import SwiftUI

struct SpeedometerView: View {
    static let faceButtonLabel = String(localized: "Gauge style")
    static let faceButtonHint = String(localized: "Double-tap to choose a gauge face")

    @State private var viewModel: SpeedometerViewModel
    @State private var showsFacePicker = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    init(viewModel: SpeedometerViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? SpeedometerViewModel())
    }

    private var theme: Theme { viewModel.face.theme }

    var body: some View {
        GeometryReader { proxy in
            GaugeDisplay(face: viewModel.face, reading: reading, accessibilityLabel: viewModel.accessibilityLabel) {
                unitButton
            }
            .overlay { mascot(in: proxy.size) }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.statusText != nil || viewModel.canOpenSettings {
                status
            }
        }
        .overlay(alignment: .topTrailing) { faceButton }
        .background(theme.backgroundGradient.ignoresSafeArea())
        .preferredColorScheme(theme.colorScheme)
        .sheet(isPresented: $showsFacePicker) {
            FacePickerSheet(selected: viewModel.face, unit: viewModel.unit) { face in
                withoutAnimation { viewModel.select(face) }
            }
        }
        .task(id: scenePhase) {
            if scenePhase == .active {
                await viewModel.run()
            }
        }
    }

    private var reading: GaugeReading {
        GaugeReading(
            displayText: viewModel.displayText,
            value: viewModel.displayedSpeed,
            fraction: viewModel.gaugeFraction,
            unit: viewModel.unit
        )
    }

    /// The mascot sits in the space the gauge leaves over; it never shrinks the gauge (speed-mascot R12).
    @ViewBuilder
    private func mascot(in container: CGSize) -> some View {
        if let frame = MascotPlacement.frame(in: container) {
            MascotView(mood: viewModel.mood, theme: theme)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
        }
    }

    /// Unit and face switches are instant; only new samples animate.
    private func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    private var unitButton: some View {
        Button {
            withoutAnimation { viewModel.toggleUnit() }
        } label: {
            UnitPill(text: viewModel.unitText, theme: theme)
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .sensoryFeedback(.selection, trigger: viewModel.unit)
        .accessibilityLabel("Unit")
        .accessibilityValue(viewModel.unitAccessibilityValue)
        .accessibilityHint("Double-tap to switch")
    }

    private var faceButton: some View {
        Button {
            showsFacePicker = true
        } label: {
            Image(systemName: "paintpalette")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(hex: theme.accent))
                .frame(width: 44, height: 44)
                .background(theme.color(theme.chipFill), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.trailing)
        .padding(.top, 4)
        .accessibilityLabel(Self.faceButtonLabel)
        .accessibilityHint(Self.faceButtonHint)
    }

    private var status: some View {
        VStack(spacing: 12) {
            if let statusText = viewModel.statusText {
                Label {
                    Text(statusText)
                } icon: {
                    if let symbol = viewModel.statusSymbol {
                        Image(systemName: symbol)
                            .foregroundStyle(Color(hex: theme.accent))
                            .accessibilityHidden(true)
                    }
                }
                .font(.callout.weight(.medium))
                .foregroundStyle(Color(hex: theme.chipText))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(theme.color(theme.chipFill), in: Capsule())
            }
            if viewModel.canOpenSettings {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Text("Open Settings")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(hex: theme.buttonLabel))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: theme.accent))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }
}

private extension SpeedometerViewModel {
    /// Preview ViewModel whose fixes never go stale.
    static func preview(
        face: GaugeFace = .minimalRing,
        authorization: LocationAuthorization = .authorized,
        mic: MicAuthorization = .authorized,
        kmh: Double? = nil
    ) -> SpeedometerViewModel {
        let samples = kmh.map { [SpeedSample(metersPerSecond: $0 / 3.6, accuracy: 0.5, isStationary: false, timestamp: .now)] } ?? []
        let viewModel = SpeedometerViewModel(
            provider: FakeSpeedProvider(authorization: authorization, samples: samples),
            defaults: UserDefaults(suiteName: "SpeedometerPreview-\(face.rawValue)") ?? .standard,
            locale: Locale(identifier: "fr_FR"),
            now: { .distantPast },
            setIdleTimerDisabled: { _ in },
            engineSound: EngineSoundViewModel(detector: FakeSoundTriggerDetector(authorization: mic), player: FakeSoundPlayer())
        )
        viewModel.select(face)
        return viewModel
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

#Preview("Analog sport") {
    SpeedometerView(viewModel: .preview(face: .analogSport, kmh: 87))
}

#Preview("Analog sport, landscape", traits: .landscapeLeft) {
    SpeedometerView(viewModel: .preview(face: .analogSport, kmh: 199))
}

#Preview("Digital HUD") {
    SpeedometerView(viewModel: .preview(face: .digitalHUD, kmh: 87))
}

#Preview("Digital HUD, landscape", traits: .landscapeLeft) {
    SpeedometerView(viewModel: .preview(face: .digitalHUD, kmh: 199))
}

#Preview("Retro") {
    SpeedometerView(viewModel: .preview(face: .retro, kmh: 87))
}

#Preview("Retro, landscape", traits: .landscapeLeft) {
    SpeedometerView(viewModel: .preview(face: .retro, kmh: 199))
}

#Preview("Retro, denied") {
    SpeedometerView(viewModel: .preview(face: .retro, authorization: .denied))
}

#Preview("Mascot worried") {
    SpeedometerView(viewModel: .preview(kmh: 130))
}

#Preview("Mascot worried, landscape", traits: .landscapeLeft) {
    SpeedometerView(viewModel: .preview(face: .digitalHUD, kmh: 130))
}

#Preview("Mic off") {
    SpeedometerView(viewModel: .preview(mic: .denied, kmh: 42))
}
