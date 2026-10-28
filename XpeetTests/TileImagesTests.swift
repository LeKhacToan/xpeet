import UIKit
import XCTest
@testable import Xpeet

final class TileImagesTests: XCTestCase {
    /// A tile server whose answers wait until the test lets them through, one at a time.
    actor GatedFetcher: TileFetcher {
        private(set) var requested: [TileKey] = []
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func tile(_ key: TileKey) async throws -> Data {
            requested.append(key)
            await withCheckedContinuation { waiting.append($0) }
            return FakeTileFetcher.tileData
        }

        func releaseOne() {
            if !waiting.isEmpty { waiting.removeFirst().resume() }
        }

        func statusUpdates() -> AsyncStream<TileStatus> { AsyncStream { $0.finish() } }
        func clearCache() {}
    }

    final class Clock: @unchecked Sendable {
        var now: TimeInterval = 100
    }

    private func key(_ x: Int, z: Int = 16) -> TileKey {
        TileKey(z: z, x: x, y: 7)
    }

    private func waitUntilAsync(timeout: TimeInterval = 2, _ condition: () async -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while await !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Lets every held answer through until nothing is queued or loading.
    private func drain(_ fetcher: GatedFetcher, _ images: TileImages) async {
        await waitUntilAsync {
            await fetcher.releaseOne()
            return !images.isBusy
        }
    }

    // MARK: - specs/osm-map R34

    func testLoadedTileStaysInMemory() async {
        let fetcher = FakeTileFetcher()
        let images = TileImages(fetcher: fetcher)
        let loaded = expectation(description: "loaded")

        images.request(key(1), drawnZoom: 16) { loaded.fulfill() }
        await fulfillment(of: [loaded], timeout: 2)
        images.request(key(1), drawnZoom: 16) { XCTFail("already in memory") }

        XCTAssertNotNil(images.image(key(1)))
        let requested = await fetcher.requested
        XCTAssertEqual(requested, [key(1)])
    }

    func testDuplicateRequestsShareOneLoad() async {
        let fetcher = GatedFetcher()
        let images = TileImages(fetcher: fetcher)

        images.request(key(1), drawnZoom: 16) {}
        images.request(key(1), drawnZoom: 16) {}
        await drain(fetcher, images)

        let count = await fetcher.requested.count
        XCTAssertEqual(count, 1)
    }

    func testNewestQueuedRequestStartsFirst() async {
        let fetcher = GatedFetcher()
        let images = TileImages(fetcher: fetcher)
        for x in 0..<TileImages.concurrentLoads { images.request(key(x), drawnZoom: 16) {} }
        await waitUntilAsync { await fetcher.requested.count == TileImages.concurrentLoads }

        images.request(key(100), drawnZoom: 16) {}
        images.request(key(101), drawnZoom: 16) {}
        await fetcher.releaseOne()
        await waitUntilAsync { await fetcher.requested.count == TileImages.concurrentLoads + 1 }

        let started = await fetcher.requested.last
        XCTAssertEqual(started, key(101), "the map wants what it drew last")
        await drain(fetcher, images)
    }

    func testQueuedTileFarFromTheDrawnZoomIsDropped() async {
        let fetcher = GatedFetcher()
        let images = TileImages(fetcher: fetcher)
        for x in 0..<TileImages.concurrentLoads { images.request(key(x), drawnZoom: 16) {} }
        await waitUntilAsync { await fetcher.requested.count == TileImages.concurrentLoads }

        images.request(key(50), drawnZoom: 16) {}
        // Zoomed out while z16 tiles were still queued.
        images.request(key(60, z: 13), drawnZoom: 13) {}
        await drain(fetcher, images)

        let requested = await fetcher.requested
        XCTAssertFalse(requested.contains(key(50)), "three levels from what the map draws")
        XCTAssertTrue(requested.contains(key(60, z: 13)))
    }

    func testFailedTileWaitsBeforeAskingAgain() async {
        let fetcher = FakeTileFetcher(isFailing: true)
        let clock = Clock()
        let images = TileImages(fetcher: fetcher, now: { clock.now })

        images.request(key(1), drawnZoom: 16) { XCTFail("nothing loaded") }
        await waitUntilAsync { !images.isBusy }
        images.request(key(1), drawnZoom: 16) {}
        await waitUntilAsync { !images.isBusy }
        var count = await fetcher.requested.count
        XCTAssertEqual(count, 1)

        clock.now += TileImages.retryDelay
        images.request(key(1), drawnZoom: 16) {}
        await waitUntilAsync { !images.isBusy }
        count = await fetcher.requested.count
        XCTAssertEqual(count, 2)
        XCTAssertNil(images.image(key(1)))
    }

    // MARK: - R33

    func testRecolouredTileUsesTheLightPalette() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let osmLand = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format).pngData { context in
            UIColor(red: 0xF2 / 255.0, green: 0xEF / 255.0, blue: 0xE9 / 255.0, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }

        let image = try XCTUnwrap(TileImages.recoloured(osmLand))
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }

        let expected = TilePalette.land * 255
        XCTAssertEqual(Double(bytes[0]), expected.x, accuracy: 3)
        XCTAssertEqual(Double(bytes[1]), expected.y, accuracy: 3)
        XCTAssertEqual(Double(bytes[2]), expected.z, accuracy: 3)
        XCTAssertNil(TileImages.recoloured(Data("not an image".utf8)))
    }
}
