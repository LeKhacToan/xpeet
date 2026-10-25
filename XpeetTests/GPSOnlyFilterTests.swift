import XCTest
@testable import Xpeet

final class GPSOnlyFilterTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    // MARK: - specs/speed-accuracy R5

    func testMatchesHandComputedStep() {
        var filter = GPSOnlyFilter(speed: 10, variance: 0.25, at: start)

        XCTAssertTrue(filter.update(speed: 12, variance: 0.25, at: start + 1))

        // Predict 1 s with jerk noise 4: P = [[5.5833, 6], [6, 8]]. Gain = [0.957143, 1.028571], innovation 2.
        XCTAssertEqual(filter.speed, 11.914286, accuracy: 1e-5)
        XCTAssertEqual(filter.acceleration, 2.057143, accuracy: 1e-5)
        XCTAssertEqual(filter.variance, 0.239286, accuracy: 1e-5)
    }

    func testLessAccurateFixMovesEstimateLess() {
        var precise = GPSOnlyFilter(speed: 20, variance: 0.25, at: start)
        var vague = precise
        _ = precise.update(speed: 20, variance: 0.25, at: start + 1)
        _ = vague.update(speed: 20, variance: 0.25, at: start + 1)

        _ = precise.update(speed: 24, variance: 0.25, at: start + 2)
        _ = vague.update(speed: 24, variance: 9, at: start + 2)

        XCTAssertGreaterThan(precise.speed, vague.speed)
        XCTAssertGreaterThan(vague.speed, 20)
    }

    func testImpossibleJumpIsRejected() {
        var filter = GPSOnlyFilter(speed: 20, variance: 0.25, at: start)
        let before = filter

        // 13 m/s in 1 s is 1.3 g: more than the 12 m/s² bound.
        XCTAssertFalse(filter.update(speed: 33, variance: 0.25, at: start + 1))
        XCTAssertEqual(filter, before)
    }

    func testBoundGrowsWithTimeSinceLastAcceptedFix() {
        var filter = GPSOnlyFilter(speed: 20, variance: 0.25, at: start)
        XCTAssertFalse(filter.update(speed: 35, variance: 0.25, at: start + 1))

        // Rejections don't move the reference time, so a wrong start heals itself.
        XCTAssertTrue(filter.update(speed: 35, variance: 0.25, at: start + 2))
    }

    func testSameTimestampUpdatesWithoutPredict() {
        var filter = GPSOnlyFilter(speed: 10, variance: 0.25, at: start)

        XCTAssertTrue(filter.update(speed: 12, variance: 0.25, at: start))

        // Equal variances, no predict: the average, and half the variance.
        XCTAssertEqual(filter.speed, 11, accuracy: 1e-9)
        XCTAssertEqual(filter.variance, 0.125, accuracy: 1e-9)
        XCTAssertEqual(filter.timestamp, start)
    }

    func testSpeedIsNeverNegative() {
        var filter = GPSOnlyFilter(speed: 1, variance: 0.25, at: start)
        _ = filter.update(speed: 0, variance: 0.25, at: start + 1)
        _ = filter.update(speed: 0, variance: 0.25, at: start + 2)

        XCTAssertGreaterThanOrEqual(filter.speed, 0)
    }

    func testStopZeroesSpeedAndAcceleration() {
        var filter = GPSOnlyFilter(speed: 10, variance: 0.25, at: start)
        _ = filter.update(speed: 8, variance: 0.25, at: start + 1)

        filter.stop(at: start + 2)

        XCTAssertEqual(filter.speed, 0)
        XCTAssertEqual(filter.acceleration, 0)
        XCTAssertEqual(filter.variance, GPSOnlyFilter.stoppedVariance)
    }
}
