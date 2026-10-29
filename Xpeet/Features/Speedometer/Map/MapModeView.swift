import SwiftUI

// The pieces of map mode (specs/osm-map R2-R4, R8, R9, R13, R14; frames `map-portrait`, `map-landscape-weak-signal`,
// `map-notice`, `map-offline-not-following`). `SpeedometerView+Map.swift` lays them out.

/// An opaque card in the theme's colours: the map never shows through behind text (R4).
struct MapCardBackground<S: InsettableShape>: View {
    let shape: S
    let theme: Theme

    var body: some View {
        shape
            .fill(Color(hex: MapStyle.cardColor(for: theme)))
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            }
    }
}

/// The speed on the map: the largest text on screen, in the face's number font (R3).
struct SpeedCard<Unit: View>: View {
    static var portraitFontSize: CGFloat { 76 }
    static var landscapeFontSize: CGFloat { 60 }

    let text: String
    let hasReading: Bool
    let theme: Theme
    let isLandscape: Bool
    let accessibilityLabel: String
    @ViewBuilder let unit: Unit

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let layout = isLandscape
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            Text(text)
                .font(theme.font(role: .number, size: isLandscape ? Self.landscapeFontSize : Self.portraitFontSize))
                .foregroundStyle(Color(hex: hasReading ? theme.number : theme.placeholder))
                .lineLimit(1)
                .fixedSize()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : .snappy, value: text)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityAddTraits(.updatesFrequently)
            if !isLandscape { Spacer(minLength: 8) }
            unit
        }
        .padding(.horizontal, isLandscape ? 16 : 22)
        .padding(.vertical, isLandscape ? 14 : 10)
        .background { MapCardBackground(shape: RoundedRectangle(cornerRadius: 16, style: .continuous), theme: theme) }
    }
}

/// Shown over the first map until "OK" (R2).
struct MapNotice: View {
    let theme: Theme
    let onAccept: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color(hex: theme.accent))
                .accessibilityHidden(true)
            Text("Map tiles come from OpenStreetMap. Their servers can see the area you are viewing.")
                .font(Theme.captionFont(textStyle: .footnote, size: 14))
                .foregroundStyle(Color(hex: theme.chipText))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("OK", action: onAccept)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(hex: theme.accent))
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .background { MapCardBackground(shape: RoundedRectangle(cornerRadius: 16, style: .continuous), theme: theme) }
        .accessibilityElement(children: .contain)
    }
}

/// "© OpenStreetMap contributors", always visible on a map, and "Map offline" while tiles fail (R13, R14).
struct MapCredit: View {
    static let copyright = "https://www.openstreetmap.org/copyright"

    let isOffline: Bool
    let theme: Theme

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if let url = URL(string: Self.copyright) { openURL(url) }
            } label: {
                Text("© OpenStreetMap contributors")
            }
            .buttonStyle(.plain)
            .accessibilityRemoveTraits(.isButton)
            .accessibilityAddTraits(.isLink)
            if isOffline {
                Text(verbatim: "|").accessibilityHidden(true)
                Label("Map offline", systemImage: "wifi.slash")
            }
        }
        .font(Theme.captionFont(textStyle: .caption2, size: 11))
        .foregroundStyle(Color(hex: theme.chipText))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: theme.backgroundCenter), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

/// Appears while the map is moved by hand (R8).
struct RecentreButton: View {
    let theme: Theme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "location.north.line.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(hex: theme.accent))
                .frame(width: 44, height: 44)
                .background { MapCardBackground(shape: Circle(), theme: theme) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Re-centre map")
    }
}

/// Before a position, or with location off: no map and no tiles (R9). The status chip says why.
struct MapPlaceholder: View {
    let theme: Theme
    let isLocationOff: Bool

    var body: some View {
        Image(systemName: isLocationOff ? "location.slash" : "location.magnifyingglass")
            .font(.system(size: 44, weight: .light))
            .foregroundStyle(Color(hex: theme.placeholder))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}

#Preview("Speed card") {
    let theme = GaugeFace.minimalRing.theme
    return VStack(spacing: 20) {
        SpeedCard(text: "72", hasReading: true, theme: theme, isLandscape: false, accessibilityLabel: "72 km/h") {
            UnitPill(text: "km/h", theme: theme)
        }
        SpeedCard(text: "--", hasReading: false, theme: theme, isLandscape: true, accessibilityLabel: "No GPS signal") {
            UnitPill(text: "km/h", theme: theme)
        }
        MapNotice(theme: theme) {}
        HStack {
            RecentreButton(theme: theme) {}
            MapCredit(isOffline: true, theme: theme)
        }
    }
    .padding()
    .background(Color(white: 0.55))
}

#Preview("Placeholder, retro") {
    MapPlaceholder(theme: GaugeFace.retro.theme, isLocationOff: true)
        .background(GaugeFace.retro.theme.backgroundGradient)
}
