import MapKit
import UIKit
import XCTest
@testable import Xpeet

/// What `TileRenderer.draw` puts in a tile's area (specs/osm-map R11, R33, R34), drawn into a small bitmap that is
/// flipped like MapKit's context: map points grow downwards.
final class TileRendererTests: XCTestCase {
    /// Serves one image for every tile and remembers what was asked for.
    actor StubFetcher: TileFetcher {
        let data: Data
        private(set) var requested: [TileKey] = []

        init(data: Data) {
            self.data = data
        }

        func tile(_ key: TileKey) async throws -> Data {
            requested.append(key)
            return data
        }

        func statusUpdates() -> AsyncStream<TileStatus> { AsyncStream { $0.finish() } }
        func clearCache() {}
    }

    /// Black on the top half, white below: shows which way up a tile is drawn.
    private static let blackOverWhite: Data = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 128))
        }
    }()

    /// Zoom 16; its parent at 15 has it as the top-left quarter.
    private let tile = TileKey(z: 16, x: 52_450, y: 29_796)
    private var parent: TileKey { TileKey(z: 15, x: tile.x / 2, y: tile.y / 2) }
    private var fetcher: StubFetcher!
    private var images: TileImages!
    private var renderer: TileRenderer!

    override func setUp() {
        fetcher = StubFetcher(data: Self.blackOverWhite)
        images = TileImages(fetcher: fetcher)
        renderer = TileRenderer(overlay: OSMTileOverlay(), images: images)
    }

    private func preload(_ key: TileKey) async {
        images.noteDrawn(zoom: key.z)
        images.request(key)
        let deadline = Date().addingTimeInterval(2)
        while images.image(key) == nil, Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(images.image(key))
    }

    /// Draws `key`'s area at its zoom into 8 × 8 pixels; rows run from north to south.
    private func draw(_ key: TileKey) throws -> [[SIMD3<Double>]] {
        let area = TileGrid.mapRect(for: key)
        let size = 8
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        let sRGB = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.translateBy(x: 0, y: Double(size))
            context.scaleBy(x: Double(size) / area.width, y: -Double(size) / area.height)
            context.translateBy(x: -area.minX, y: -area.minY)
            renderer.draw(area, zoomScale: pow(2, Double(key.z - 20)), in: context)
        }
        return (0..<size).map { row in
            (0..<size).map { column in
                let index = (row * size + column) * 4
                return SIMD3(Double(bytes[index]), Double(bytes[index + 1]), Double(bytes[index + 2]))
            }
        }
    }

    private func isDark(_ pixel: SIMD3<Double>) -> Bool { pixel.max() < 60 }
    private func isWhite(_ pixel: SIMD3<Double>) -> Bool { pixel.min() > 250 }

    // MARK: - specs/osm-map R34

    func testTileInMemoryDrawsNorthUp() async throws {
        await preload(tile)

        let pixels = try draw(tile)

        XCTAssertTrue(isDark(pixels[1][4]), "top half")
        XCTAssertTrue(isWhite(pixels[6][4]), "bottom half")
    }

    func testMissingTileShowsItsPartOfACoarserTile() async throws {
        await preload(parent)
        let below = TileKey(z: 16, x: tile.x, y: tile.y + 1)

        let topLeft = try draw(tile)
        let bottomLeft = try draw(below)

        XCTAssertTrue(topLeft.joined().allSatisfy(isDark), "the parent's black top half")
        XCTAssertTrue(bottomLeft.joined().allSatisfy(isWhite), "the parent's white bottom half")
    }

    func testMissingTileShowsFinerTilesInMemory() async throws {
        let child = TileGrid.children(of: tile)[0]
        await preload(child)

        let pixels = try draw(tile)

        XCTAssertTrue(isDark(pixels[0][0]), "the child's top in its quarter")
        XCTAssertTrue(isWhite(pixels[3][0]), "the child's bottom in its quarter")
        let land = TilePalette.land * 255
        XCTAssertEqual(pixels[6][6].x, land.x, accuracy: 2, "no tile here yet: land")
    }

    func testNothingInMemoryShowsLand() throws {
        let land = TilePalette.land * 255

        let pixels = try draw(tile)

        for pixel in pixels.joined() {
            XCTAssertEqual(pixel.x, land.x, accuracy: 2)
            XCTAssertEqual(pixel.y, land.y, accuracy: 2)
            XCTAssertEqual(pixel.z, land.z, accuracy: 2)
        }
    }

    // MARK: - R11

    func testDrawAsksOnlyForTheTilesItDraws() async throws {
        await preload(parent)
        _ = try draw(tile)

        let deadline = Date().addingTimeInterval(2)
        while images.isBusy, Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }

        let requested = await fetcher.requested
        XCTAssertEqual(requested, [parent, tile], "the stand-in came from memory; no neighbours, parents or children")
    }
}
