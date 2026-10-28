import Foundation

/// Gauge or map (specs/osm-map R1). Stored under `screenMode`.
enum ScreenMode: String {
    case gauge
    case map
}

/// A position in degrees. Plain values, so nothing outside `Core/Map` needs MapKit.
struct MapCoordinate: Equatable {
    var latitude: Double
    var longitude: Double
}

/// Everything the live map draws, already decided by `SpeedometerViewModel` (specs/osm-map R5-R8, R18).
/// `MapCanvas` only applies it.
struct MapScene: Equatable {
    struct Marker: Equatable {
        var coordinate: MapCoordinate
        /// Degrees from true north; nil draws a dot instead of an arrow (R5).
        var heading: Double?
        /// While Acquiring after a fix (R5).
        var isDimmed: Bool
    }

    struct Camera: Equatable {
        var center: MapCoordinate
        /// Slippy-map zoom level (R7).
        var zoom: Int
        /// Degrees from true north, up on screen (R6).
        var heading: Double
    }

    var marker: Marker?
    /// Nil while the map is moved by hand (R8).
    var camera: Camera?
    /// The current trip's segments, the last one ending at a live marker (R18).
    var trail: [[MapCoordinate]] = []

    var isFollowing: Bool { camera != nil }
}

/// Map styling over the light tiles (specs/osm-map R4, R5, R18, R33).
enum MapStyle {
    /// The marker's opacity while Acquiring (R5).
    static let dimmedMarkerOpacity = 0.5
    /// Trail and route line width, pt (R18).
    static let trailWidth = 5.0
    /// The dark edge on each side of the trail, so a light accent still shows on the light map (R18).
    static let trailEdge: UInt32 = 0x0D121C
    static let trailEdgeWidth = 1.5

    /// The opaque map-card fill (R4): the theme background with the chip tint, or without the tint for a face where
    /// the tint would take the speed below 7:1 or other text below 4.5:1.
    static func cardColor(for theme: Theme) -> UInt32 {
        let tinted = Theme.blend(theme.chipFill.hex, over: theme.backgroundCenter, opacity: theme.chipFill.opacity)
        let readable = Theme.contrastRatio(theme.number, tinted) >= 7
            && Theme.contrastRatio(theme.placeholder, tinted) >= 7
            && [theme.secondaryText, theme.chipText, theme.accent].allSatisfy { Theme.contrastRatio($0, tinted) >= 4.5 }
        return readable ? tinted : theme.backgroundCenter
    }
}
