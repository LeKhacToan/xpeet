import XCTest
@testable import Xpeet

final class MapFollowerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 10_000)

    private func follower(atKmh kmh: Double) -> MapFollower {
        var follower = MapFollower()
        follower.update(metersPerSecond: kmh / 3.6, course: -1, courseAccuracy: -1)
        return follower
    }

    // MARK: - specs/osm-map R7

    func testZoomLevelsByShownSpeed() {
        XCTAssertEqual(follower(atKmh: 0).zoom, 17)
        XCTAssertEqual(follower(atKmh: 20).zoom, 17)
        XCTAssertEqual(follower(atKmh: 40).zoom, 16)
        XCTAssertEqual(follower(atKmh: 70).zoom, 15)
        XCTAssertEqual(follower(atKmh: 100).zoom, 14)
    }

    func testZoomHysteresis() {
        var follower = MapFollower()
        func drive(_ kmh: Double) -> Int {
            follower.update(metersPerSecond: kmh / 3.6, course: -1, courseAccuracy: -1)
            return follower.zoom
        }

        XCTAssertEqual(drive(32), 17, "2 km/h past the boundary is not enough")
        XCTAssertEqual(drive(35), 16)
        XCTAssertEqual(drive(27), 16, "back under the boundary, but within the margin")
        XCTAssertEqual(drive(24.9), 17)
    }

    // MARK: - R6

    func testHeadingFollowsValidCourse() {
        var follower = MapFollower()
        XCTAssertEqual(follower.heading, 0, "north-up before any course")
        XCTAssertFalse(follower.hasHeading)

        follower.update(metersPerSecond: 50 / 3.6, course: 135, courseAccuracy: 10)

        XCTAssertEqual(follower.heading, 135)
        XCTAssertTrue(follower.hasHeading)
    }

    func testHeadingHeldWhenSlowOrInaccurate() {
        var follower = MapFollower()
        follower.update(metersPerSecond: 50 / 3.6, course: 90, courseAccuracy: 5)

        follower.update(metersPerSecond: 4 / 3.6, course: 180, courseAccuracy: 5)
        follower.update(metersPerSecond: 50 / 3.6, course: 200, courseAccuracy: MapFollower.headingMaxCourseAccuracy + 1)
        follower.update(metersPerSecond: 50 / 3.6, course: -1, courseAccuracy: 5)
        follower.update(metersPerSecond: 50 / 3.6, course: 220, courseAccuracy: -1)

        XCTAssertEqual(follower.heading, 90, "slow, inaccurate or invalid courses keep the last heading")
    }

    // MARK: - R8

    func testGesturePausesFollowing() {
        var follower = MapFollower()

        follower.userMoved(at: start)

        XCTAssertFalse(follower.isFollowing)
    }

    func testFollowResumesAfterTenSeconds() {
        var follower = MapFollower()
        follower.userMoved(at: start)
        follower.userMoved(at: start + 4)

        XCTAssertFalse(follower.tick(at: start + 4 + MapFollower.resumeAfter - 0.1), "each gesture restarts the wait")
        XCTAssertTrue(follower.tick(at: start + 4 + MapFollower.resumeAfter))
        XCTAssertTrue(follower.isFollowing)
        XCTAssertFalse(follower.tick(at: start + 60), "nothing to resume")
    }

    func testRecentreResumesAtOnce() {
        var follower = MapFollower()
        follower.userMoved(at: start)

        follower.recentre()

        XCTAssertTrue(follower.isFollowing)
    }
}
