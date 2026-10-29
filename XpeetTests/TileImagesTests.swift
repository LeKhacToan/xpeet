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

        func releaseAll() {
            waiting.forEach { $0.resume() }
            waiting.removeAll()
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

    /// Lets every held answer through until nothing is queued or loading. Recolouring on the Simulator's CPU is slow,
    /// so a long queue takes a few seconds.
    private func drain(_ fetcher: GatedFetcher, _ images: TileImages) async {
        await waitUntilAsync(timeout: 10) {
            await fetcher.releaseAll()
            return !images.isBusy
        }
    }

    /// Six loads running at zoom 16, so later requests wait in the queue.
    private func fillSlots(_ fetcher: GatedFetcher, _ images: TileImages) async {
        images.noteDrawn(zoom: 16)
        for x in 0..<TileImages.concurrentLoads { images.request(key(x)) }
        await waitUntilAsync { await fetcher.requested.count == TileImages.concurrentLoads }
    }

    // MARK: - specs/osm-map R34

    func testLoadedTileStaysInMemory() async {
        let fetcher = FakeTileFetcher()
        let images = TileImages(fetcher: fetcher)
        var events = images.events.makeAsyncIterator()
        images.noteDrawn(zoom: 16)

        images.request(key(1))
        let event = await events.next()
        images.request(key(1))
        await waitUntilAsync { !images.isBusy }

        XCTAssertEqual(event, .loaded(key(1)))
        XCTAssertNotNil(images.image(key(1)))
        let requested = await fetcher.requested
        XCTAssertEqual(requested, [key(1)], "already in memory")
    }

    func testDuplicateRequestsShareOneLoad() async {
        let fetcher = GatedFetcher()
        let images = TileImages(fetcher: fetcher)
        images.noteDrawn(zoom: 16)

        images.request(key(1))
        images.request(key(1))
        await drain(fetcher, images)

        let count = await fetcher.requested.count
        XCTAssertEqual(count, 1)
    }

    func testNewestQueuedRequestStartsFirst() async {
        let fetcher = GatedFetcher()
        let images = TileImages(fetcher: fetcher)
        await fillSlots(fetcher, images)

        images.request(key(100))
        images.request(key(101))
        await fetcher.releaseOne()
        await waitUntilAsync { await fetcher.requested.count == TileImages.concurrentLoads + 1 }

        let started = await fetcher.requested.last
        XCTAssertEqual(started, key(101), "the map wants what it drew last")
        await drain(fetcher, images)
    }

    func testQueuedTilesTwoLevelsFromTheDrawnZoomAreDropped() async {
        let fetcher = GatedFetcher()
        let images = TileImages(fetcher: fetcher)
        await fillSlots(fetcher, images)

        images.request(key(50))
        images.request(key(51, z: 15))
        // Zoomed out to 14 where nothing is missing: no request, but the map no longer draws 16.
        images.noteDrawn(zoom: 14)
        await drain(fetcher, images)

        let requested = await fetcher.requested
        XCTAssertFalse(requested.contains(key(50)), "two levels away")
        XCTAssertTrue(requested.contains(key(51, z: 15)), "one level away")
    }

    func testQueueKeepsOnlyTheNewestTiles() async {
        let fetcher = GatedFetcher()
        let images = TileImages(fetcher: fetcher)
        await fillSlots(fetcher, images)

        for x in 100...(100 + TileImages.queueLimit) { images.request(key(x)) }
        await drain(fetcher, images)

        let requested = await fetcher.requested
        XCTAssertEqual(requested.count, TileImages.concurrentLoads + TileImages.queueLimit)
        XCTAssertFalse(requested.contains(key(100)), "the oldest waiting tile")
    }

    func testStopDropsQueuedTiles() async {
        let fetcher = GatedFetcher()
        let images = TileImages(fetcher: fetcher)
        await fillSlots(fetcher, images)
        images.request(key(100))
        images.request(key(101))

        images.stop()
        images.request(key(102))
        await drain(fetcher, images)

        let count = await fetcher.requested.count
        XCTAssertEqual(count, TileImages.concurrentLoads, "nothing new once the map is gone (R11)")
    }

    func testFailedTileWaitsLongerEachTime() async {
        let fetcher = FakeTileFetcher(isFailing: true)
        let clock = Clock()
        let images = TileImages(fetcher: fetcher, now: { clock.now })
        var events = images.events.makeAsyncIterator()
        images.noteDrawn(zoom: 16)

        images.request(key(1))
        let first = await events.next()
        images.request(key(1))
        await waitUntilAsync { !images.isBusy }
        var count = await fetcher.requested.count
        XCTAssertEqual(count, 1, "held back")

        clock.now += TileImages.retryDelay
        images.request(key(1))
        let second = await events.next()
        count = await fetcher.requested.count

        XCTAssertEqual(first, .failed(key(1), retryIn: TileImages.retryDelay))
        XCTAssertEqual(second, .failed(key(1), retryIn: TileImages.retryDelay * 2))
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
        let sRGB = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))

        let image = try XCTUnwrap(TileImages.recoloured(osmLand))
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
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
