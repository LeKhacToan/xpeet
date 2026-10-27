import XCTest
@testable import Xpeet

final class RouteRecorderTests: XCTestCase {
    /// Metres per degree of latitude on the sphere `SpeedEstimator.distance` uses.
    private let metresPerDegree = 6_371_000.0 * .pi / 180
    /// An arbitrary synthetic origin, not a real place of interest.
    private let originLatitude = 45.0
    private let originLongitude = 120.0

    /// Adds a point `metres` north of the origin.
    @discardableResult
    private func add(_ recorder: inout RouteRecorder, north metres: Double, accuracy: Double = 5) -> Bool {
        recorder.add(latitude: originLatitude + metres / metresPerDegree, longitude: originLongitude, horizontalAccuracy: accuracy)
    }

    // MARK: - specs/osm-map R16

    func testSkipsInaccurateFixes() {
        var recorder = RouteRecorder()

        XCTAssertFalse(add(&recorder, north: 0, accuracy: -1), "invalid accuracy")
        XCTAssertFalse(add(&recorder, north: 0, accuracy: RouteRecorder.maxAccuracy + 1))
        XCTAssertTrue(add(&recorder, north: 0, accuracy: RouteRecorder.maxAccuracy))
        XCTAssertEqual(recorder.route.segments.count, 1)
    }

    func testKeepsPointsTenMetresApart() {
        var recorder = RouteRecorder()

        for metres in [0.0, 4, 8, 12, 16, 24] {
            add(&recorder, north: metres)
        }

        // Spacing is measured from the last kept point: 0, then 12, then 24.
        XCTAssertEqual(recorder.route.segments.first?.count, 3)
    }

    func testFirstPointOfSegmentAlwaysKept() {
        var recorder = RouteRecorder()
        add(&recorder, north: 0)

        recorder.breakSegment()

        XCTAssertTrue(add(&recorder, north: 3), "3 m from the last point, but it opens a new segment")
        XCTAssertEqual(recorder.route.segments.map(\.count), [1, 1])
    }

    func testStoresOnlyRoundedCoordinates() throws {
        var recorder = RouteRecorder()
        recorder.add(latitude: 45.123456789, longitude: 120.987654321, horizontalAccuracy: 5)

        let json = try XCTUnwrap(String(data: JSONEncoder().encode(recorder.route), encoding: .utf8))

        XCTAssertEqual(json, #"{"segments":[[[45.12346,120.98765]]]}"#)
    }

    // MARK: - R17

    func testBreakStartsNewSegment() {
        var recorder = RouteRecorder()
        add(&recorder, north: 0)
        add(&recorder, north: 20)

        recorder.breakSegment()
        add(&recorder, north: 200)
        add(&recorder, north: 220)

        XCTAssertEqual(recorder.route.segments.map(\.count), [2, 2])
        XCTAssertEqual(recorder.route.length, 40, accuracy: 2, "the 180 m gap is not part of the route")
    }

    func testLoadedRouteContinuesInNewSegment() {
        var first = RouteRecorder()
        add(&first, north: 0)
        add(&first, north: 20)

        var resumed = RouteRecorder(route: first.route)
        add(&resumed, north: 40)

        XCTAssertEqual(resumed.route.segments.map(\.count), [2, 1])
    }

    // MARK: - R21

    func testHourAtFiftyIsUnder200KB() throws {
        var recorder = RouteRecorder()
        let metresPerSecond = 50 / 3.6

        for second in 0..<3_600 {
            add(&recorder, north: Double(second) * metresPerSecond)
        }

        let size = try JSONEncoder().encode(recorder.route).count
        XCTAssertEqual(recorder.route.segments.first?.count, 3_600, "every fix is more than 10 m apart")
        XCTAssertLessThan(size, 200_000)
    }
}
