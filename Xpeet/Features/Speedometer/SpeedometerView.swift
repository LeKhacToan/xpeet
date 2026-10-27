import SwiftUI

struct SpeedometerView: View {
    static let faceButtonLabel = String(localized: "Gauge style")
    static let faceButtonHint = String(localized: "Double-tap to choose a gauge face")

    // Internal, not private: SpeedometerView+Map.swift lays out map mode with the same pieces (specs/osm-map).
    @State var viewModel: SpeedometerViewModel
    @State private var showsFacePicker = false
    @State var showsTrip = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    init(viewModel: SpeedometerViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? SpeedometerViewModel())
    }

    var theme: Theme { viewModel.face.theme }

    var body: some View {
        GeometryReader { root in
            if viewModel.screenMode == .map {
                mapMode(isLandscape: root.size.width > root.size.height)
            } else if root.size.height >= root.size.width {
                portrait
            } else {
                landscape
            }
        }
        .background(theme.backgroundGradient.ignoresSafeArea())
        .preferredColorScheme(theme.colorScheme)
        .sheet(isPresented: $showsFacePicker) {
            FacePickerSheet(selected: viewModel.face, unit: viewModel.unit) { face in
                withoutAnimation { viewModel.select(face) }
            }
        }
        .sheet(isPresented: $showsTrip) {
            TripSheet(display: viewModel.trip, theme: theme) { viewModel.startNewTrip() }
        }
        .task(id: scenePhase) {
            if scenePhase == .active {
                await viewModel.run()
            }
        }
    }

    /// The top row is always reserved, so the gauge never changes size when the chip comes or goes (specs/ui-redesign R7).
    private var portrait: some View {
        VStack(spacing: 0) {
            ZStack {
                if let chip = statusChip {
                    // Clear of the face button on either side, so the chip stays centred.
                    chip.padding(.horizontal, Self.topRowButtonSpace)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Self.topRowHeight)
            .overlay(alignment: .trailing) { faceButton }
            .overlay(alignment: .leading) { modeButton }
            gauge(tripBeside: false)
            // Under the gauge; the gauge gives up height, never width (specs/trip-stats R12).
            tripButton
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.canOpenSettings {
                openSettings
            }
        }
    }

    /// Landscape keeps the status at the bottom edge (specs/ui-redesign R7).
    private var landscape: some View {
        gauge(tripBeside: true)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if viewModel.statusText != nil || viewModel.canOpenSettings {
                    VStack(spacing: 0) {
                        statusChip
                            .padding(.horizontal)
                            .padding(.top, 12)
                            .padding(.bottom, viewModel.canOpenSettings ? 0 : 16)
                        if viewModel.canOpenSettings { openSettings }
                    }
                }
            }
            .overlay(alignment: .topTrailing) { faceButton }
            .overlay(alignment: .topLeading) { modeButton }
    }

    /// Fits a three-line chip at the default text size (the mic chip wraps to three lines on 375–393 pt phones).
    static let topRowHeight: CGFloat = 76
    /// Width kept free beside the chip for the face and mode buttons and their padding.
    static let topRowButtonSpace: CGFloat = 64

    /// `tripBeside`: landscape puts the trip line right of the gauge; portrait puts it underneath instead.
    private func gauge(tripBeside: Bool) -> some View {
        GeometryReader { proxy in
            GaugeDisplay(face: viewModel.face, reading: reading, accessibilityLabel: viewModel.accessibilityLabel) {
                unitButton
            }
            .overlay { mascot(in: proxy.size) }
            .overlay {
                if tripBeside { landscapeTrip(in: proxy.size) }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
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

    /// Landscape only: right of the gauge, mirroring the mascot (specs/trip-stats R12).
    @ViewBuilder
    private func landscapeTrip(in container: CGSize) -> some View {
        if let frame = TripLinePlacement.frame(in: container) {
            tripButton
                .frame(maxWidth: frame.width)
                .position(x: frame.midX, y: frame.midY)
        }
    }

    /// The trip line; tapping it opens the trip sheet. Hidden while location is off (specs/trip-stats R11, R13).
    @ViewBuilder
    var tripButton: some View {
        if let line = viewModel.trip.line {
            Button {
                showsTrip = true
            } label: {
                TripLine(text: line, theme: theme)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Trip")
            .accessibilityValue(viewModel.trip.lineAccessibilityValue)
            .accessibilityHint("Double-tap for trip details")
            .accessibilityAddTraits(.isButton)
        }
    }

    /// Unit and face switches are instant; only new samples animate.
    func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    var unitButton: some View {
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
                .background { GlassBackground(shape: Circle(), tint: theme.color(theme.chipFill), colorScheme: theme.colorScheme) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.trailing)
        .padding(.top, 4)
        .accessibilityLabel(Self.faceButtonLabel)
        .accessibilityHint(Self.faceButtonHint)
    }

    /// Frosted-glass status chip: accent dot, icon and wrapping text (specs/ui-redesign R7).
    var statusChip: StatusChip? {
        viewModel.statusText.map { StatusChip(text: $0, symbol: viewModel.statusSymbol, theme: theme) }
    }

    /// Denied only: a full-width button and a one-line hint (specs/ui-redesign R17).
    var openSettings: some View {
        VStack(spacing: 8) {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Label("Open Settings", systemImage: "gearshape.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(hex: theme.buttonLabel))
                    .frame(maxWidth: 360, minHeight: 50)
                    .background(Color(hex: theme.accent), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            Text("Enable Location in Settings to see your speed")
                .font(Theme.captionFont(textStyle: .footnote, size: 13))
                .foregroundStyle(Color(hex: theme.secondaryText))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }
}

struct StatusChip: View {
    let text: String
    let symbol: String?
    let theme: Theme

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: theme.accent))
                .frame(width: 6, height: 6)
                .shadow(color: Color(hex: theme.accent).opacity(0.8), radius: 3)
                .accessibilityHidden(true)
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(Color(hex: theme.accent))
                    .accessibilityHidden(true)
            }
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Theme.captionFont(textStyle: .subheadline, size: 14))
        .foregroundStyle(Color(hex: theme.chipText))
        .multilineTextAlignment(.leading)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background {
            GlassBackground(
                shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
                tint: theme.color(theme.chipFill),
                colorScheme: theme.colorScheme
            )
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
private extension SpeedometerViewModel {
    /// Preview ViewModel whose fixes never go stale.
    static func preview(
        face: GaugeFace = .minimalRing,
        authorization: LocationAuthorization = .authorized,
        mic: MicAuthorization = .authorized,
        kmh: Double? = nil,
        accuracy: Double = 0.5,
        tripMinutes: Int = 18,
        mapMode: Bool = false
    ) -> SpeedometerViewModel {
        let defaults = UserDefaults(suiteName: "SpeedometerPreview-\(face.rawValue)") ?? .standard
        // A running trip, so the trip line shows real numbers (specs/trip-stats).
        var tracker = TripTracker()
        let tripStart = Date.now.addingTimeInterval(TimeInterval(-tripMinutes * 60))
        for second in stride(from: 0, through: tripMinutes * 60, by: 1) where tripMinutes > 0 {
            tracker.update(at: tripStart.addingTimeInterval(TimeInterval(second)), reading: .live(metersPerSecond: 11.5))
        }
        TripStore(defaults: defaults).save(tracker)
        defaults.set(mapMode ? ScreenMode.map.rawValue : ScreenMode.gauge.rawValue, forKey: SpeedometerViewModel.screenModeDefaultsKey)
        // A synthetic position, so map mode has a marker (specs/osm-map).
        let samples = kmh.map {
            [SpeedSample(metersPerSecond: $0 / 3.6, accuracy: accuracy, isStationary: false, timestamp: .now,
                         latitude: 45, longitude: 120, horizontalAccuracy: 5, course: 30, courseAccuracy: 5)]
        } ?? []
        let viewModel = SpeedometerViewModel(
            provider: FakeSpeedProvider(authorization: authorization, samples: samples),
            motionProvider: FakeMotionProvider(),
            defaults: defaults,
            locale: Locale(identifier: "fr_FR"),
            now: { .distantPast },
            setIdleTimerDisabled: { _ in },
            engineSound: EngineSoundViewModel(detector: FakeSoundTriggerDetector(authorization: mic), player: FakeSoundPlayer()),
            routeStore: RouteStore(folder: FileManager.default.temporaryDirectory.appending(path: "PreviewRoutes")),
            tileFetcher: FakeTileFetcher()
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

#Preview("Weak signal") {
    SpeedometerView(viewModel: .preview(face: .analogSport, kmh: 64, accuracy: 9))
}

#Preview("Mic off, HUD") {
    SpeedometerView(viewModel: .preview(face: .digitalHUD, mic: .denied, kmh: 0))
}

#Preview("Searching, retro") {
    SpeedometerView(viewModel: .preview(face: .retro))
}

#Preview("New trip, landscape", traits: .landscapeLeft) {
    SpeedometerView(viewModel: .preview(face: .retro, kmh: 0, tripMinutes: 0))
}

#Preview("Map mode") {
    SpeedometerView(viewModel: .preview(kmh: 72, mapMode: true))
}

#Preview("Map mode, landscape", traits: .landscapeLeft) {
    SpeedometerView(viewModel: .preview(face: .analogSport, kmh: 64, accuracy: 9, mapMode: true))
}

#Preview("Map mode, searching, retro") {
    SpeedometerView(viewModel: .preview(face: .retro, mapMode: true))
}

#Preview("Denied, landscape", traits: .landscapeLeft) {
    SpeedometerView(viewModel: .preview(face: .analogSport, authorization: .denied))
}
#endif
