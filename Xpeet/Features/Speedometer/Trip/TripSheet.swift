import SwiftUI

/// Trip details and the last trips (specs/trip-stats R14-R17, frames `trip-sheet`, `trip-sheet-empty`).
/// Same glass style as the face picker. Shows only what it is given: values stay live while it is open.
/// Earlier trips open their route and can be deleted (specs/osm-map R22-R25, frames `trip-sheet-delete`, `route-view`).
struct TripSheet: View {
    let display: TripDisplay
    let theme: Theme
    let onNewTrip: () -> Void
    var onDelete: (UUID) -> Void = { _ in }
    var onDeleteAll: () -> Void = {}
    var route: (UUID) -> Route? = { _ in nil }
    var isMapNoticePending = false
    var isMapOffline = false
    var onAcceptNotice: () -> Void = {}
    var tileFetcher: TileFetcher?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selected: (id: UUID, route: Route?)?
    @State private var detent: PresentationDetent = .medium
    @State private var confirmsDeleteAll = false

    private var accent: Color { Color(hex: theme.accent) }

    var body: some View {
        content
            // While a route shows, dragging the map must not drag the sheet (osm-map R23).
            .presentationDetents(selected == nil ? [.medium, .large] : [.large], selection: $detent)
            .interactiveDismissDisabled(selected != nil)
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
            .confirmationDialog("Delete all trips?", isPresented: $confirmsDeleteAll, titleVisibility: .visible) {
                Button("Delete All Trips", role: .destructive, action: onDeleteAll)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All trips and their routes will be deleted from this iPhone. This can't be undone.")
            }
    }

    @ViewBuilder
    private var content: some View {
        if let selected, let row = display.history.first(where: { $0.id == selected.id }), let tileFetcher {
            RouteView(
                row: row,
                route: selected.route,
                theme: theme,
                tileFetcher: tileFetcher,
                isMapNoticePending: isMapNoticePending,
                isMapOffline: isMapOffline,
                onAcceptNotice: onAcceptNotice,
                onBack: { self.selected = nil },
                onDone: { dismiss() }
            )
        } else {
            trips
        }
    }

    private var trips: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trip")
                        .font(.title3.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(display.started)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
            }
            .padding()

            // A List, so earlier trips can be swiped to delete (osm-map R24); rows keep the card look.
            List {
                Group {
                    currentTrip
                    if display.isEmpty {
                        Text("The trip starts when the car moves.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    newTripButton
                    history
                    deleteAllButton
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            .listStyle(.plain)
            .listRowSpacing(8)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: Current trip

    private var currentTrip: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Current distance")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(display.distanceValue)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text(display.distanceUnit)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(accent)
                }
                .monospacedDigit()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Distance")
                .accessibilityValue(display.distanceSpoken)
            }
            if display.isApproximate {
                Label {
                    Text("Approximate").fontWeight(.semibold) + Text(" · ") + Text("GPS was lost for part of this trip")
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 10) {
                metric("Moving time", display.movingTime, spoken: display.movingTimeSpoken)
                metric("Stopped time", display.stoppedTime, spoken: display.stoppedTimeSpoken)
                metric("Total time", display.totalTime, spoken: display.totalTimeSpoken)
                metric("Average speed", display.averageSpeed, spoken: display.averageSpeedSpoken)
            }
        }
        .padding(16)
        .background { GlassBackground(shape: card, tint: theme.color(theme.chipFill), colorScheme: theme.colorScheme) }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    private var card: RoundedRectangle { RoundedRectangle(cornerRadius: 16, style: .continuous) }

    private func metric(_ label: LocalizedStringKey, _ value: String, spoken: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(12)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(spoken)
    }

    private var newTripButton: some View {
        Button(action: onNewTrip) {
            Label("New trip", systemImage: "arrow.triangle.2.circlepath")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background { GlassBackground(shape: card, tint: theme.color(theme.chipFill), colorScheme: theme.colorScheme) }
                .contentShape(card)
        }
        .buttonStyle(.plain)
        .disabled(display.isEmpty)
        .opacity(display.isEmpty ? 0.4 : 1)
    }

    // MARK: History

    @ViewBuilder
    private var history: some View {
        Text("Earlier trips")
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
        if display.history.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "car.side")
                    .font(.title2)
                    .accessibilityHidden(true)
                Text("No earlier trips")
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(.black.opacity(0.18), in: card)
        } else {
            ForEach(display.history) { row in
                Button {
                    selected = (row.id, route(row.id))
                    detent = .large
                } label: {
                    historyRow(row)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Double-tap to show the route")
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        onDelete(row.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    /// Deletes every trip and route, after one confirmation (osm-map R25).
    private var deleteAllButton: some View {
        Button {
            confirmsDeleteAll = true
        } label: {
            Label("Delete all trips", systemImage: "trash")
                .font(.body.weight(.semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background { GlassBackground(shape: card, tint: theme.color(theme.chipFill), colorScheme: theme.colorScheme) }
                .contentShape(card)
        }
        .buttonStyle(.plain)
        .disabled(display.history.isEmpty && display.isEmpty)
        .opacity(display.history.isEmpty && display.isEmpty ? 0.4 : 1)
        .padding(.top, 8)
    }

    /// Values on one line beside the day when they fit; otherwise stacked under it, wrapping between words
    /// rather than truncating (R14, R17).
    private func historyRow(_ row: TripDisplay.Row) -> some View {
        HStack(spacing: 10) {
            rowValues(row)
            // Each row opens its route (osm-map R22).
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .font(.subheadline)
        .padding(14)
        .background { GlassBackground(shape: card, tint: theme.color(theme.chipFill), colorScheme: theme.colorScheme) }
        .contentShape(card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }

    private func rowValues(_ row: TripDisplay.Row) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                dayAndTag(row)
                Spacer(minLength: 8)
                Text(row.values)
                    .monospacedDigit()
                    .fixedSize()
            }
            VStack(alignment: .leading, spacing: 6) {
                dayAndTag(row)
                Text(row.values)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func dayAndTag(_ row: TripDisplay.Row) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(row.day)
                Text(row.startTime)
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
            if row.isApproximate {
                Label("Approximate", systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(.secondary.opacity(0.5)))
                    .fixedSize()
            }
        }
    }
}

#if DEBUG
private extension TripDisplay {
    /// A display built through the real formatter: `trips` finished trips, then a current one moving `minutes`.
    static func preview(minutes: Int, trips: Int, lost: Bool = false) -> TripDisplay {
        let now = Date()
        var tracker = TripTracker()
        for index in 0..<trips {
            let start = now.addingTimeInterval(TimeInterval(-86_400 * (index + 1)))
            for second in 0...(600 + index * 120) {
                tracker.update(at: start.addingTimeInterval(TimeInterval(second)), reading: .live(metersPerSecond: 11))
            }
            if lost, index == 0 {
                tracker.update(at: start.addingTimeInterval(700), reading: .acquiring)
                tracker.update(at: start.addingTimeInterval(800), reading: .live(metersPerSecond: 11))
            }
            tracker.newTrip()
        }
        let start = now.addingTimeInterval(TimeInterval(-minutes * 60))
        if minutes > 0 {
            for second in stride(from: 0, through: minutes * 60, by: 1) {
                let speed: Double = second % 300 < 40 ? 0 : 12
                tracker.update(at: start.addingTimeInterval(TimeInterval(second)), reading: .live(metersPerSecond: speed))
            }
        }
        let formatter = TripFormatter(locale: Locale(identifier: "en_GB"), calendar: .current)
        return formatter.display(of: tracker, unit: .kmh, now: now, showsLine: true)
    }
}

#Preview("Running, with history") {
    Color.black.sheet(isPresented: .constant(true)) {
        TripSheet(
            display: .preview(minutes: 24, trips: 4, lost: true),
            theme: GaugeFace.minimalRing.theme,
            onNewTrip: {},
            route: { _ in Route(segments: [(0..<60).map { RoutePoint(latitude: 45 + Double($0) * 0.0004, longitude: 120) }]) },
            tileFetcher: FakeTileFetcher()
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Empty") {
    Color.black.sheet(isPresented: .constant(true)) {
        TripSheet(display: .preview(minutes: 0, trips: 0), theme: GaugeFace.minimalRing.theme) {}
    }
    .preferredColorScheme(.dark)
}

#Preview("Retro, light") {
    Color.white.sheet(isPresented: .constant(true)) {
        TripSheet(display: .preview(minutes: 12, trips: 2), theme: GaugeFace.retro.theme) {}
    }
    .preferredColorScheme(.light)
}
#endif
