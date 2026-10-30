import XCTest
@testable import Xpeet

final class TripStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private let start = Date(timeIntervalSince1970: 10_000)

    override func setUpWithError() throws {
        suiteName = "TripStoreTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func tracker(trips: Int) -> TripTracker {
        var tracker = TripTracker()
        for index in 0..<trips {
            let offset = TimeInterval(index * 100)
            for second in 0...20 {
                tracker.update(at: start + offset + TimeInterval(second), reading: .live(metersPerSecond: 12))
            }
            tracker.newTrip()
        }
        for second in 0...5 {
            tracker.update(at: start + 5_000 + TimeInterval(second), reading: .live(metersPerSecond: 8))
        }
        return tracker
    }

    // MARK: - specs/trip-stats R9

    func testRoundTrip() {
        let store = TripStore(defaults: defaults)
        let saved = tracker(trips: 3)

        store.save(saved)
        let loaded = store.load()

        XCTAssertEqual(loaded.current, saved.current)
        XCTAssertEqual(loaded.history, saved.history)
    }

    func testStoresTotalsOnly() throws {
        TripStore(defaults: defaults).save(tracker(trips: 1))

        let data = try XCTUnwrap(defaults.data(forKey: TripStore.currentKey))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        // "id" joined in specs/osm-map R19: it names the trip's route file, and is not a position.
        let allowed: Set = ["id", "startedAt", "lastUpdateAt", "lastMovementAt", "distance", "movingTime", "stoppedTime", "lostTime"]
        XCTAssertTrue(Set(object.keys).isSubset(of: allowed), "unexpected keys: \(object.keys)")

        let history = try XCTUnwrap(defaults.data(forKey: TripStore.historyKey))
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: history) as? [[String: Any]])
        XCTAssertTrue(rows.allSatisfy { Set($0.keys).isSubset(of: allowed) })
    }

    // MARK: - R10

    func testEmptyStoreGivesEmptyTrip() {
        let loaded = TripStore(defaults: defaults).load()

        XCTAssertTrue(loaded.current.isEmpty)
        XCTAssertEqual(loaded.history, [])
    }

    func testCorruptDataGivesEmptyTrip() {
        defaults.set(Data("not json".utf8), forKey: TripStore.currentKey)
        defaults.set(Data("[{\"distance\":".utf8), forKey: TripStore.historyKey)

        let loaded = TripStore(defaults: defaults).load()

        XCTAssertEqual(loaded, TripTracker())
    }

    // MARK: - specs/osm-map R19

    func testLegacyTripWithoutIdLoads() throws {
        let legacy = Data("""
        {"startedAt": 10000, "lastUpdateAt": 10600, "lastMovementAt": 10600, "distance": 5000,
         "movingTime": 540, "stoppedTime": 60, "lostTime": 0}
        """.utf8)
        defaults.set(legacy, forKey: TripStore.currentKey)
        defaults.set(Data("[\(String(decoding: legacy, as: UTF8.self))]".utf8), forKey: TripStore.historyKey)

        let loaded = TripStore(defaults: defaults).load()

        XCTAssertEqual(loaded.current.distance, 5_000)
        XCTAssertNotNil(loaded.current.id)
        XCTAssertEqual(loaded.history.count, 1)
        XCTAssertNotNil(loaded.history.first?.id)
    }

    // MARK: - specs/break-reminder R13, R14

    private var stretch: DrivingStretch {
        DrivingStretch(startedAt: start, drivingTime: 3_600, lastMovementAt: start + 3_700)
    }

    func testStretchRoundTrip() {
        TripStore(defaults: defaults).save(stretch)
        XCTAssertEqual(TripStore(defaults: defaults).loadStretch(), stretch)
    }

    func testMissingStretchGivesEmptyStretch() {
        XCTAssertEqual(TripStore(defaults: defaults).loadStretch(), DrivingStretch())
    }

    func testStretchStoresTimesOnly() throws {
        TripStore(defaults: defaults).save(stretch)
        let data = try XCTUnwrap(defaults.data(forKey: TripStore.stretchKey))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["startedAt", "drivingTime", "lastMovementAt"])
    }

    func testClearedStretchIsSavedEmpty() throws {
        TripStore(defaults: defaults).save(stretch)
        TripStore(defaults: defaults).save(DrivingStretch())
        let data = try XCTUnwrap(defaults.data(forKey: TripStore.stretchKey))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["drivingTime"])
        XCTAssertEqual(object["drivingTime"] as? Double, 0)
    }

    func testCorruptStretchKeepsTheTrip() {
        let store = TripStore(defaults: defaults)
        let saved = tracker(trips: 2)
        store.save(saved)
        defaults.set(Data("not json".utf8), forKey: TripStore.stretchKey)

        XCTAssertEqual(store.loadStretch(), DrivingStretch())
        XCTAssertEqual(store.load().current, saved.current)
        XCTAssertEqual(store.load().history, saved.history)
    }

    func testCorruptTripKeepsTheStretch() {
        let store = TripStore(defaults: defaults)
        store.save(stretch)
        defaults.set(Data("not json".utf8), forKey: TripStore.currentKey)

        XCTAssertEqual(store.load(), TripTracker())
        XCTAssertEqual(store.loadStretch(), stretch)
    }
}
