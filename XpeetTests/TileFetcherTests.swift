import XCTest
@testable import Xpeet

final class TileFetcherTests: XCTestCase {
    /// A scripted tile server: answers requests from a queue and remembers them.
    actor StubServer {
        enum Reply {
            case status(Int, headers: [String: String] = [:], body: Data = Data("tile".utf8))
            case offline
        }

        private(set) var requests: [URLRequest] = []
        private var replies: [Reply] = []
        private var delay: Duration = .zero

        func queue(_ reply: Reply) { replies.append(reply) }
        func setDelay(_ delay: Duration) { self.delay = delay }

        func handle(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            requests.append(request)
            if delay > .zero { try await Task.sleep(for: delay) }
            let reply = replies.isEmpty ? .status(200) : replies.removeFirst()
            switch reply {
            case .offline:
                throw URLError(.notConnectedToInternet)
            case let .status(code, headers, body):
                let url = try XCTUnwrap(request.url)
                let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers))
                return (body, response)
            }
        }
    }

    final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_000_000)
    }

    private let key = TileKey(z: 16, x: 52_183, y: 30_804)
    private var folder: URL!
    private var server: StubServer!
    private var clock: Clock!
    private var fetcher: URLSessionTileFetcher!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "TileFetcherTests-\(UUID().uuidString)")
        server = StubServer()
        clock = Clock()
        let server = server!
        let clock = clock!
        fetcher = URLSessionTileFetcher(
            source: TileSource(defaults: UserDefaults(suiteName: "TileFetcherTests-\(UUID().uuidString)") ?? .standard),
            cache: TileCache(folder: folder),
            transport: { try await server.handle($0) },
            version: "9.9",
            now: { clock.now }
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - specs/osm-map R11

    func testRequestsCarryUserAgentAndNoNoCache() async throws {
        _ = try await fetcher.tile(key)

        let requests = await server.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://tile.openstreetmap.org/16/52183/30804.png")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Xpeet/9.9 (+https://github.com/LeKhacToan/xpeet)")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cache-Control"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Pragma"))
    }

    // MARK: - R12

    func testFreshTileServedWithoutRequest() async throws {
        await server.queue(.status(200, headers: ["Cache-Control": "max-age=3600"]))
        _ = try await fetcher.tile(key)

        clock.now += 3_000
        let data = try await fetcher.tile(key)

        XCTAssertEqual(data, Data("tile".utf8))
        let count = await server.requests.count
        XCTAssertEqual(count, 1)
    }

    func testStaleTileRevalidatesConditionally() async throws {
        await server.queue(.status(200, headers: [
            "Cache-Control": "max-age=60", "ETag": "\"abc\"", "Last-Modified": "Mon, 26 Oct 2026 08:00:00 GMT",
        ]))
        await server.queue(.status(304, headers: ["Cache-Control": "max-age=60"], body: Data()))
        _ = try await fetcher.tile(key)

        clock.now += 120
        let revalidated = try await fetcher.tile(key)
        clock.now += 30
        _ = try await fetcher.tile(key)

        let requests = await server.requests
        XCTAssertEqual(requests.count, 2, "the 304 renewed the expiry")
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "If-None-Match"), "\"abc\"")
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "If-Modified-Since"), "Mon, 26 Oct 2026 08:00:00 GMT")
        XCTAssertEqual(revalidated, Data("tile".utf8), "a 304 serves the cached tile")
    }

    func testNoHeadersFreshForSevenDays() async throws {
        _ = try await fetcher.tile(key)

        clock.now += URLSessionTileFetcher.defaultFreshness - 1
        _ = try await fetcher.tile(key)
        var count = await server.requests.count
        XCTAssertEqual(count, 1)

        clock.now += 2
        _ = try await fetcher.tile(key)
        count = await server.requests.count
        XCTAssertEqual(count, 2)
    }

    func testOfflineServesStaleCopy() async throws {
        await server.queue(.status(200, headers: ["Cache-Control": "max-age=60"]))
        await server.queue(.offline)
        _ = try await fetcher.tile(key)

        clock.now += 600
        let data = try await fetcher.tile(key)

        XCTAssertEqual(data, Data("tile".utf8))
    }

    func testRefusedWithoutCopyThrows() async {
        await server.queue(.status(503))

        do {
            _ = try await fetcher.tile(key)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? TileError, .http(503))
        }
    }

    func testDuplicateRequestsShareOneDownload() async throws {
        await server.setDelay(.milliseconds(100))

        async let first = fetcher.tile(key)
        async let second = fetcher.tile(key)
        _ = try await (first, second)

        let count = await server.requests.count
        XCTAssertEqual(count, 1)
    }

    func testCacheEvictsOverLimit() async throws {
        let cache = TileCache(folder: folder, capacity: 1_000)
        let entry = TileCache.Entry(expires: .distantFuture)
        for x in 0..<5 {
            await cache.store(Data(repeating: 0, count: 400), entry: entry, for: TileKey(z: 1, x: x, y: 0))
        }
        _ = await cache.cached(TileKey(z: 1, x: 4, y: 0))

        await cache.trim()

        var kept = 0
        for x in 0..<5 where await cache.cached(TileKey(z: 1, x: x, y: 0)) != nil { kept += 1 }
        XCTAssertLessThanOrEqual(kept, 2, "under 90% of 1,000 bytes")
        let newest = await cache.cached(TileKey(z: 1, x: 4, y: 0))
        XCTAssertNotNil(newest, "the most recently used tile stays")
    }

    // MARK: - R13

    func testStatusOfflineThenOk() async throws {
        await server.queue(.offline)
        await server.queue(.status(200))
        var statuses = await fetcher.statusUpdates().makeAsyncIterator()

        _ = try? await fetcher.tile(key)
        let offline = await statuses.next()
        _ = try await fetcher.tile(TileKey(z: 16, x: 1, y: 1))
        let ok = await statuses.next()

        XCTAssertEqual(offline, .offline)
        XCTAssertEqual(ok, .ok)
    }
}
