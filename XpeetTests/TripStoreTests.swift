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
        let allowed: Set = ["startedAt", "lastUpdateAt", "lastMovementAt", "distance", "movingTime", "stoppedTime", "lostTime"]
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
}
