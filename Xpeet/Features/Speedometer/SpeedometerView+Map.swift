import SwiftUI

/// Map mode (specs/osm-map R1-R3, R8, R9, R13, R14; frames `map-portrait`, `map-landscape-weak-signal`).
/// The map fills the screen; the speed card, trip line and status chip sit on top. No gauge, mascot or face button.
extension SpeedometerView {
    /// Switches between gauge and map: top leading in both modes, mirroring the face button (R1).
    var modeButton: some View {
        let showsMap = viewModel.screenMode == .gauge
        return Button {
            withoutAnimation { viewModel.toggleScreenMode() }
        } label: {
            Image(systemName: showsMap ? "map" : "speedometer")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(hex: theme.accent))
                .frame(width: 44, height: 44)
                .background { modeButtonBackground }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.leading)
        .padding(.top, 4)
        .accessibilityLabel(showsMap ? "Show map" : "Show gauge")
    }

    @ViewBuilder
    private var modeButtonBackground: some View {
        if viewModel.screenMode == .map {
            MapCardBackground(shape: Circle(), theme: theme)
        } else {
            GlassBackground(shape: Circle(), tint: theme.color(theme.chipFill), colorScheme: theme.colorScheme)
        }
    }

    func mapMode(isLandscape: Bool) -> some View {
        ZStack {
            mapLayer.ignoresSafeArea()
            if isLandscape { landscapeMapOverlays } else { portraitMapOverlays }
        }
    }

    // MARK: Layers

    @ViewBuilder
    private var mapLayer: some View {
        if viewModel.showsMapPlaceholder {
            MapPlaceholder(theme: theme, isLocationOff: viewModel.isLocationOff)
        } else {
            MapCanvas(
                scene: viewModel.mapScene,
                style: .live,
                tileFetcher: viewModel.tileFetcher,
                trailColor: UIColor(Color(hex: theme.accent)),
                reduceMotion: reduceMotion,
                onUserGesture: { viewModel.mapWasMovedByHand() }
            )
            // One element: the map is not read tile by tile (R26).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Map")
            .accessibilityValue(viewModel.mapScene.isFollowing ? "Following your position" : "Not following")
        }
    }

    /// Frame `map-portrait`: chip in the top row, speed card and trip line at the bottom, the credit above Apple's
    /// "Legal" link.
    private var portraitMapOverlays: some View {
        VStack(spacing: 8) {
            ZStack {
                if let chip = statusChip {
                    chip.padding(.horizontal, Self.topRowButtonSpace)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Self.topRowHeight)
            .overlay(alignment: .leading) { modeButton }
            notice
                .padding(.horizontal)
            Spacer(minLength: 0)
            recentre
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal)
            speedCard(isLandscape: false)
                .padding(.horizontal)
            tripButton
                .padding(.horizontal)
            credit
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal)
                .padding(.bottom, Self.attributionClearance)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.canOpenSettings { openSettings }
        }
    }

    /// Frame `map-landscape-weak-signal`: speed card and trip line on the leading side, chip on the bottom edge.
    private var landscapeMapOverlays: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                speedCard(isLandscape: true)
                tripButton
            }
            .frame(maxWidth: 240)
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .topLeading) { modeButton }
        .overlay(alignment: .top) { notice.frame(maxWidth: 440).padding(.top, 4) }
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 8) {
                recentre
                credit
            }
            .padding(.trailing)
            .padding(.bottom, Self.attributionClearance)
        }
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
    }

    // MARK: Pieces

    /// Room left at the bottom for Apple's logo and "Legal" link, which no overlay may cover (R3).
    private static var attributionClearance: CGFloat { 26 }

    private func speedCard(isLandscape: Bool) -> some View {
        SpeedCard(
            text: viewModel.displayText,
            hasReading: viewModel.displayedSpeed != nil,
            theme: theme,
            isLandscape: isLandscape,
            accessibilityLabel: viewModel.accessibilityLabel
        ) {
            unitButton
        }
    }

    @ViewBuilder
    private var notice: some View {
        if viewModel.isMapNoticePending, !viewModel.showsMapPlaceholder {
            MapNotice(theme: theme) { viewModel.acceptMapNotice() }
        }
    }

    @ViewBuilder
    private var recentre: some View {
        if !viewModel.showsMapPlaceholder, !viewModel.mapScene.isFollowing {
            RecentreButton(theme: theme) { viewModel.recentreMap() }
        }
    }

    @ViewBuilder
    private var credit: some View {
        if !viewModel.showsMapPlaceholder {
            MapCredit(isOffline: viewModel.isMapOffline, theme: theme)
        }
    }
}
