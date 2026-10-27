import MapKit
import os

/// OpenStreetMap raster tiles in place of Apple's map content (specs/osm-map R10-R11). MapKit calls `loadTile` on
/// background queues, only for tiles it needs to draw; this class adds no prefetching.
final class OSMTileOverlay: MKTileOverlay {
    private let fetcher: TileFetcher
    #if DEBUG
    private static let log = Logger(subsystem: "app.plouton.xpeet", category: "tiles")
    #endif

    init(fetcher: TileFetcher) {
        self.fetcher = fetcher
        super.init(urlTemplate: nil)
        canReplaceMapContent = true
        minimumZ = TileSource.zoomRange.lowerBound
        maximumZ = TileSource.zoomRange.upperBound
        tileSize = CGSize(width: 256, height: 256)
    }

    override func loadTile(at path: MKTileOverlayPath) async throws -> Data {
        #if DEBUG
        // Which zoom MapKit asks for at which screen scale (plan risk: Retina screens may ask for z + 1).
        Self.log.debug("tile z\(path.z) x\(path.x) y\(path.y) scale \(path.contentScaleFactor)")
        #endif
        return try await fetcher.tile(TileKey(z: path.z, x: path.x, y: path.y))
    }
}

/// A black veil over the whole world, drawn just above the tiles, so a bright map doesn't glare at night
/// (specs/osm-map R15). The trail and marker are drawn above it.
final class DimOverlay: MKPolygon {
    static func world() -> DimOverlay {
        let world = MKMapRect.world
        let corners = [
            MKMapPoint(x: world.minX, y: world.minY), MKMapPoint(x: world.maxX, y: world.minY),
            MKMapPoint(x: world.maxX, y: world.maxY), MKMapPoint(x: world.minX, y: world.maxY),
        ]
        return DimOverlay(points: corners, count: corners.count)
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
}
