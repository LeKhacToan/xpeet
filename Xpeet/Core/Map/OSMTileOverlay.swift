import MapKit

/// The OpenStreetMap layer, in place of Apple's map content (specs/osm-map R10, R11). It only marks the layer:
/// `TileRenderer` draws it and loads just the tiles it draws, with no prefetching.
final class OSMTileOverlay: MKTileOverlay {
    init() {
        super.init(urlTemplate: nil)
        canReplaceMapContent = true
        minimumZ = TileSource.zoomRange.lowerBound
        maximumZ = TileSource.zoomRange.upperBound
        tileSize = CGSize(width: 256, height: 256)
    }
}

/// Slippy-map zoom levels as MapKit camera distances (specs/osm-map R7). MapKit doesn't document its field of
/// view, so the ratio of camera distance to visible height is measured on the live map.
enum CameraMath {
    /// Camera distance over visible height for a ~30° field of view, until the live map has been measured.
    static let defaultDistancePerVisibleHeight = 1.866

    /// Ground metres per screen point at zoom `zoom` (256-point tiles). The world is 2^28 map points wide, so zoom
    /// z is a zoom scale of 2^(z - 20) screen points per map point.
    static func metersPerPoint(zoom: Int, latitude: Double) -> Double {
        MKMetersPerMapPointAtLatitude(latitude) * pow(2, Double(20 - zoom))
    }

    static func distance(zoom: Int, latitude: Double, viewHeight: Double, distancePerVisibleHeight: Double) -> Double {
        metersPerPoint(zoom: zoom, latitude: latitude) * viewHeight * distancePerVisibleHeight
    }

    /// Pinch-zoom stays within these levels (specs/osm-map R8).
    static let zoomLimits = 3...19

    /// Camera distances for `zoomLimits`: closest at the highest zoom.
    static func distanceRange(latitude: Double, viewHeight: Double, distancePerVisibleHeight: Double) -> ClosedRange<Double> {
        let closest = distance(zoom: zoomLimits.upperBound, latitude: latitude, viewHeight: viewHeight,
                               distancePerVisibleHeight: distancePerVisibleHeight)
        let farthest = distance(zoom: zoomLimits.lowerBound, latitude: latitude, viewHeight: viewHeight,
                                distancePerVisibleHeight: distancePerVisibleHeight)
        return closest...farthest
    }
}
