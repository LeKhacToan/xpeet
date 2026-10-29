import XCTest
@testable import Xpeet

final class RouteStoreTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "RouteStoreTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private let route = Route(segments: [
        [RoutePoint(latitude: 45, longitude: 120), RoutePoint(latitude: 45.001, longitude: 120)],
        [RoutePoint(latitude: 45.01, longitude: 120.002)],
    ])

    // MARK: - specs/osm-map R20

    func testRoundTrip() {
        let store = RouteStore(folder: folder)
        let id = UUID()

        XCTAssertTrue(store.save(route, id: id))

        XCTAssertEqual(store.load(id: id), route)
        XCTAssertNil(store.load(id: UUID()), "no file, no route")
    }

    func testWritesRequestCompleteProtection() {
        var requested: Data.WritingOptions = []
        let store = RouteStore(folder: folder) { data, url, options in
            requested = options
            try data.write(to: url, options: options)
        }

        store.save(route, id: UUID())

        XCTAssertTrue(requested.contains(.completeFileProtection))
        XCTAssertTrue(requested.contains(.atomic))
    }

    func testFolderExcludedFromBackup() throws {
        RouteStore(folder: folder).save(route, id: UUID())

        let values = try folder.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testCorruptFileIsNoRoute() throws {
        let store = RouteStore(folder: folder)
        let id = UUID()
        store.save(route, id: id)
        let file = folder.appending(path: "\(id.uuidString).json")
        try Data("not json".utf8).write(to: file)

        XCTAssertNil(store.load(id: id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "an unreadable file is deleted")
    }

    func testFailedWriteReportsFalse() {
        struct Locked: Error {}
        let store = RouteStore(folder: folder) { _, _, _ in throw Locked() }

        XCTAssertFalse(store.save(route, id: UUID()))
    }

    // MARK: - R19, R25

    func testPruneKeepsOnlyKnownTrips() {
        let store = RouteStore(folder: folder)
        let kept = UUID()
        let dropped = UUID()
        store.save(route, id: kept)
        store.save(route, id: dropped)

        store.prune(keeping: [kept])

        XCTAssertNotNil(store.load(id: kept))
        XCTAssertNil(store.load(id: dropped))
    }

    func testRemoveAll() {
        let store = RouteStore(folder: folder)
        let id = UUID()
        store.save(route, id: id)

        store.removeAll()

        XCTAssertNil(store.load(id: id))
        XCTAssertTrue(store.save(route, id: id), "the folder comes back on the next save")
    }
}
