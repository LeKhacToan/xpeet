import SwiftUI

/// One earlier trip's route inside the trip sheet (specs/osm-map R23, frame `route-view`): a north-up map fitted to
/// the route, then the trip's totals. Read-only: deleting happens in the list (R24).
struct RouteView: View {
    let row: TripDisplay.Row
    /// Nil or empty: "No route saved for this trip", and no tiles are requested.
    let route: Route?
    let theme: Theme
    let tileFetcher: TileFetcher
    let isMapNoticePending: Bool
    let isMapOffline: Bool
    let onAcceptNotice: () -> Void
    let onBack: () -> Void
    let onDone: () -> Void

    private var accent: Color { Color(hex: theme.accent) }
    private var card: RoundedRectangle { RoundedRectangle(cornerRadius: 16, style: .continuous) }

    var body: some View {
        VStack(spacing: 16) {
            header
            map
            totals
        }
        .padding([.horizontal, .bottom])
        .padding(.top, 8)
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Label("Trips", systemImage: "chevron.left")
                    .fontWeight(.semibold)
                    .foregroundStyle(accent)
            }
            Spacer()
            Text("\(row.day) \(row.startTime)")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Done", action: onDone)
                .fontWeight(.semibold)
        }
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var map: some View {
        if let route, !route.isEmpty {
            MapCanvas(
                scene: MapScene(trail: route.coordinates),
                style: .route,
                tileFetcher: tileFetcher,
                trailColor: UIColor(accent)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Route map")
            .overlay(alignment: .top) {
                if isMapNoticePending {
                    MapNotice(theme: theme, onAccept: onAcceptNotice).padding(8)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                MapCredit(isOffline: isMapOffline, theme: theme)
                    .padding(.trailing, 8)
                    .padding(.bottom, 26)
            }
            .clipShape(card)
            .frame(maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "map")
                    .font(.title2)
                    .accessibilityHidden(true)
                Text("No route saved for this trip")
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.18), in: card)
        }
    }

    /// Frame `route-view`: three values side by side, and the approximate note (trip-stats R14).
    private var totals: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                metric("Distance", row.distance)
                metric("Moving time", row.movingTime)
                metric("Average speed", row.averageSpeed)
            }
            if row.isApproximate {
                Label {
                    Text("Approximate").fontWeight(.semibold) + Text(" · ") + Text("GPS was lost for part of this trip")
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background { GlassBackground(shape: card, tint: theme.color(theme.chipFill), colorScheme: theme.colorScheme) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }

    private func metric(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

private extension Route {
    var coordinates: [[MapCoordinate]] {
        segments.map { segment in segment.map { MapCoordinate(latitude: $0.latitude, longitude: $0.longitude) } }
    }
}

#if DEBUG
#Preview("Route, approximate") {
    let row = TripDisplay.Row(
        id: UUID(), day: "Yesterday", startTime: "18:32", values: "14.2 km · 22 min · 38 km/h avg",
        distance: "14.2 km", movingTime: "22 min", averageSpeed: "38 km/h", isApproximate: true,
        accessibilityLabel: "Yesterday 18:32, 14.2 kilometres, 22 minutes moving, approximate"
    )
    let route = Route(segments: [
        (0..<40).map { RoutePoint(latitude: 45 + Double($0) * 0.0004, longitude: 120) },
        (50..<90).map { RoutePoint(latitude: 45.02, longitude: 120 + Double($0 - 50) * 0.0005) },
    ])
    return Color.black.sheet(isPresented: .constant(true)) {
        RouteView(row: row, route: route, theme: GaugeFace.minimalRing.theme, tileFetcher: FakeTileFetcher(),
                  isMapNoticePending: false, isMapOffline: false, onAcceptNotice: {}, onBack: {}, onDone: {})
            .presentationBackground(.ultraThinMaterial)
    }
    .preferredColorScheme(.dark)
}

#Preview("No route") {
    let row = TripDisplay.Row(
        id: UUID(), day: "Sat 24 Oct", startTime: "09:05", values: "31.0 km · 42 min · 44 km/h avg",
        distance: "31.0 km", movingTime: "42 min", averageSpeed: "44 km/h", isApproximate: false,
        accessibilityLabel: "Saturday 24 October 09:05, 31.0 kilometres, 42 minutes moving"
    )
    return Color.black.sheet(isPresented: .constant(true)) {
        RouteView(row: row, route: nil, theme: GaugeFace.retro.theme, tileFetcher: FakeTileFetcher(),
                  isMapNoticePending: true, isMapOffline: false, onAcceptNotice: {}, onBack: {}, onDone: {})
    }
}
#endif
