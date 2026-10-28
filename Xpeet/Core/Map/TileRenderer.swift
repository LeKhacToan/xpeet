import MapKit

/// Draws `OSMTileOverlay` from `TileImages` in place of `MKTileOverlayRenderer` (specs/osm-map R33, R34): recoloured,
/// straight from memory, and never as a hole. While a tile loads, its area shows the land colour, then the nearest
/// coarser tile in memory enlarged, then any finer tiles in memory: zooming shows a soft map, not dark squares.
/// MapKit calls `draw` on background queues.
final class TileRenderer: MKOverlayRenderer, @unchecked Sendable {
    private static let land = CGColor(
        srgbRed: TilePalette.land.x, green: TilePalette.land.y, blue: TilePalette.land.z, alpha: 1
    )

    private let images: TileImages

    init(overlay: OSMTileOverlay, fetcher: TileFetcher) {
        images = TileImages(fetcher: fetcher)
        super.init(overlay: overlay)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let zoom = TileGrid.zoom(forScale: zoomScale)
        context.interpolationQuality = .high
        for key in TileGrid.keys(covering: mapRect, zoom: zoom) {
            let area = TileGrid.mapRect(for: key)
            if let image = images.image(key) {
                draw(image, in: area, zoomScale: zoomScale, context)
                continue
            }
            context.setFillColor(Self.land)
            context.fill(rect(for: area))
            if let standIn = coarserStandIn(for: key) {
                draw(standIn, in: area, zoomScale: zoomScale, context)
            }
            for child in TileGrid.children(of: key) {
                if let image = images.image(child) { draw(image, in: TileGrid.mapRect(for: child), zoomScale: zoomScale, context) }
            }
            images.request(key, drawnZoom: zoom) { [weak self] in
                DispatchQueue.main.async { self?.setNeedsDisplay(area) }
            }
        }
    }

    /// Map points grow downwards and images draw upwards, so each tile is flipped into place. Tiles overlap by half a
    /// screen point, so no seam shows between them.
    private func draw(_ image: CGImage, in area: MKMapRect, zoomScale: MKZoomScale, _ context: CGContext) {
        let overlap = 0.5 / zoomScale
        let target = rect(for: area).insetBy(dx: -overlap, dy: -overlap)
        context.saveGState()
        context.translateBy(x: target.minX, y: target.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: target.size))
        context.restoreGState()
    }

    /// The nearest coarser tile in memory, cut down to `key`'s part of it.
    private func coarserStandIn(for key: TileKey) -> CGImage? {
        for ancestor in TileGrid.ancestors(of: key) {
            guard let image = images.image(ancestor.key) else { continue }
            let part = ancestor.part
            return image.cropping(to: CGRect(
                x: part.minX * Double(image.width), y: part.minY * Double(image.height),
                width: part.width * Double(image.width), height: part.height * Double(image.height)
            ).integral)
        }
        return nil
    }
}

/// Slippy-map tiles in MapKit's map points (specs/osm-map R34). The world is 2^28 map points wide, so a tile at zoom z
/// spans 2^(28 - z) of them.
enum TileGrid {
    /// How many levels up a stand-in tile may come from: at most 32 times enlarged.
    static let fallbackLevels = 5

    /// The tile zoom for MapKit's drawing scale: 2^(z - 20) asks for zoom z. MapKit draws at twice the screen's points
    /// per map point (0.25 with the camera at z17 on the 3× simulator), so tiles come one level above the camera's
    /// zoom (`CameraMath`), sharp and at half size.
    static func zoom(forScale zoomScale: Double) -> Int {
        let zoom = Int((20 + log2(zoomScale)).rounded())
        return min(max(zoom, TileSource.zoomRange.lowerBound), TileSource.zoomRange.upperBound)
    }

    static func mapRect(for key: TileKey) -> MKMapRect {
        let span = MKMapSize.world.width / pow(2, Double(key.z))
        return MKMapRect(x: Double(key.x) * span, y: Double(key.y) * span, width: span, height: span)
    }

    /// The tiles at `zoom` that `rect` touches, within the world.
    static func keys(covering rect: MKMapRect, zoom: Int) -> [TileKey] {
        let count = 1 << zoom
        let span = MKMapSize.world.width / Double(count)
        func indices(_ low: Double, _ high: Double) -> ClosedRange<Int> {
            let first = min(max(Int((low / span).rounded(.down)), 0), count - 1)
            let last = min(max(Int((high / span).rounded(.up)) - 1, first), count - 1)
            return first...last
        }
        let columns = indices(rect.minX, rect.maxX)
        return indices(rect.minY, rect.maxY).flatMap { y in columns.map { x in TileKey(z: zoom, x: x, y: y) } }
    }

    /// The tiles up to `fallbackLevels` levels up that contain `key`, nearest first, each with the part `key` covers
    /// as fractions of its width and height.
    static func ancestors(of key: TileKey) -> [(key: TileKey, part: CGRect)] {
        (1...fallbackLevels).filter { key.z - $0 >= TileSource.zoomRange.lowerBound }.map { levels in
            let parts = 1 << levels
            let ancestor = TileKey(z: key.z - levels, x: key.x >> levels, y: key.y >> levels)
            let size = 1 / Double(parts)
            let part = CGRect(x: Double(key.x - ancestor.x * parts) * size, y: Double(key.y - ancestor.y * parts) * size,
                              width: size, height: size)
            return (ancestor, part)
        }
    }

    /// The four tiles one level down, or none at the highest zoom.
    static func children(of key: TileKey) -> [TileKey] {
        guard key.z < TileSource.zoomRange.upperBound else { return [] }
        return [(0, 0), (1, 0), (0, 1), (1, 1)].map { TileKey(z: key.z + 1, x: key.x * 2 + $0, y: key.y * 2 + $1) }
    }
}
