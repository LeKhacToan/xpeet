import XCTest
@testable import Xpeet

final class SpeedEstimatorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func fix(
        _ metersPerSecond: Double,
        accuracy: Double = 0.5,
        stationary: Bool = false,
        at seconds: TimeInterval,
        latitude: Double = 0,
        horizontalAccuracy: Double = -1
    ) -> SpeedSample {
        SpeedSample(
            metersPerSecond: metersPerSecond,
            accuracy: accuracy,
            isStationary: stationary,
            timestamp: start + seconds,
            latitude: latitude,
            longitude: 0,
            horizontalAccuracy: horizontalAccuracy
        )
    }

    // MARK: - R4

    func testFirstFixInitialisesExactly() throws {
        var estimator = SpeedEstimator()

        XCTAssertEqual(estimator.fix(fix(15, at: 0), arrival: start), .accepted)

        let estimate = try XCTUnwrap(estimator.gpsOnly)
        XCTAssertEqual(estimate.metersPerSecond, 15)
        XCTAssertEqual(estimate.sigma, 0.5, accuracy: 1e-9)
    }

    func testSameInputsSameOutputs() {
        var first = SpeedEstimator()
        var second = SpeedEstimator()
        for (index, speed) in [10.0, 12, 11, 15, 14].enumerated() {
            let seconds = TimeInterval(index)
            first.fix(fix(speed, at: seconds), arrival: start + seconds)
            second.fix(fix(speed, at: seconds), arrival: start + seconds)
        }

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.gpsOnly, second.gpsOnly)
    }

    func testKeepsGPSOnlyEstimateWithoutFusion() {
        var estimator = SpeedEstimator()
        estimator.fix(fix(15, at: 0), arrival: start)

        XCTAssertNotNil(estimator.gpsOnly)
        XCTAssertNil(estimator.fused, "fusion arrives in PR 2")
    }

    // MARK: - R13

    func testNegativeSpeedIgnoredByDefault() {
        var estimator = SpeedEstimator()
        estimator.fix(fix(15, at: 0, horizontalAccuracy: 5), arrival: start)

        let outcome = estimator.fix(fix(-1, at: 3, latitude: 0.001, horizontalAccuracy: 5), arrival: start + 3)

        XCTAssertEqual(outcome, .ignored)
        XCTAssertEqual(estimator.gpsOnly?.metersPerSecond, 15)
    }

    func testNegativeAccuracyIgnored() {
        var estimator = SpeedEstimator()
        estimator.fix(fix(15, at: 0), arrival: start)

        XCTAssertEqual(estimator.fix(fix(25, accuracy: -1, at: 1), arrival: start + 1), .ignored)
    }

    func testPositionSpeedUsedWhenEnabledAndAccurate() throws {
        var estimator = SpeedEstimator(configuration: .init(usesPositionSpeed: true))
        estimator.fix(fix(37, at: 0, horizontalAccuracy: 5), arrival: start)

        // 0.001° of latitude is 111.2 m; over 3 s that is 37.06 m/s.
        let outcome = estimator.fix(fix(-1, at: 3, latitude: 0.001, horizontalAccuracy: 5), arrival: start + 3)

        XCTAssertEqual(outcome, .accepted)
        XCTAssertEqual(try XCTUnwrap(estimator.gpsOnly).metersPerSecond, 37.06, accuracy: 0.1)
    }

    func testPositionSpeedSkippedWhenInaccurate() {
        var estimator = SpeedEstimator(configuration: .init(usesPositionSpeed: true))
        estimator.fix(fix(37, at: 0, horizontalAccuracy: 15), arrival: start)

        let outcome = estimator.fix(fix(-1, at: 3, latitude: 0.001, horizontalAccuracy: 5), arrival: start + 3)

        XCTAssertEqual(outcome, .ignored)
    }

    func testPositionSpeedSkippedOutsideInterval() {
        var estimator = SpeedEstimator(configuration: .init(usesPositionSpeed: true))
        estimator.fix(fix(37, at: 0, horizontalAccuracy: 5), arrival: start)

        let tooSoon = estimator.fix(fix(-1, at: 1, latitude: 0.0004, horizontalAccuracy: 5), arrival: start + 1)

        XCTAssertEqual(tooSoon, .ignored, "1 s apart: position noise would swamp the speed")
    }

    // MARK: - R5, via the estimator

    func testImpossibleJumpIsRejected() {
        var estimator = SpeedEstimator()
        estimator.fix(fix(20, at: 0), arrival: start)

        XCTAssertEqual(estimator.fix(fix(40, at: 1), arrival: start + 1), .rejected)
        XCTAssertEqual(estimator.gpsOnly?.metersPerSecond, 20)
    }

    // MARK: - R7 (speedometer), stationary

    func testStationaryFixGivesExactlyZero() {
        var estimator = SpeedEstimator()
        estimator.fix(fix(8, at: 0), arrival: start)

        estimator.fix(fix(0.6, stationary: true, at: 1), arrival: start + 1)

        XCTAssertEqual(estimator.gpsOnly?.metersPerSecond, 0)
        XCTAssertTrue(estimator.isStopped)
    }

    // MARK: - R14

    func testShowsGPSOnlyWhenFusionDisabled() {
        var estimator = SpeedEstimator()
        estimator.fix(fix(15, at: 0), arrival: start)

        XCTAssertEqual(estimator.shown?.source, .gpsOnly)
        XCTAssertEqual(estimator.shown?.estimate, estimator.gpsOnly)
    }

    // MARK: - R17

    func testGapStartsAfterOnePointFiveSeconds() {
        var estimator = SpeedEstimator()
        estimator.fix(fix(15, at: 0), arrival: start)

        estimator.tick(now: start + 1.5)
        XCTAssertFalse(estimator.inGap)

        estimator.tick(now: start + 1.6)
        XCTAssertEqual(estimator.gapStart, start + 1.5)
    }

    func testGapUsesArrivalTimeNotFixTimestamp() {
        var estimator = SpeedEstimator()
        // The fix is stamped 0.8 s before it reaches the app.
        estimator.fix(fix(15, at: 0), arrival: start + 0.8)

        estimator.tick(now: start + 2)

        XCTAssertFalse(estimator.inGap)
    }

    func testNoGapWhileStopped() {
        var estimator = SpeedEstimator()
        estimator.fix(fix(0, stationary: true, at: 0), arrival: start)

        estimator.tick(now: start + 60)
        estimator.unavailable(at: start + 61)

        XCTAssertFalse(estimator.inGap)
    }

    func testUnavailableStartsGap() {
        var estimator = SpeedEstimator()
        estimator.fix(fix(15, at: 0), arrival: start)

        estimator.unavailable(at: start + 0.5)

        XCTAssertEqual(estimator.gapStart, start + 0.5)
    }

    func testUnavailableBeforeAnyFixIsNoGap() {
        var estimator = SpeedEstimator()

        estimator.unavailable(at: start)

        XCTAssertFalse(estimator.inGap)
    }

    func testFixEndsGap() {
        var estimator = SpeedEstimator()
        estimator.fix(fix(15, at: 0), arrival: start)
        estimator.unavailable(at: start + 0.5)

        estimator.fix(fix(15, at: 3), arrival: start + 3)

        XCTAssertFalse(estimator.inGap)
    }

    func testIgnoredFixDoesNotEndGap() {
        var estimator = SpeedEstimator()
        estimator.fix(fix(15, at: 0), arrival: start)
        estimator.unavailable(at: start + 0.5)

        estimator.fix(fix(-1, at: 3), arrival: start + 3)

        XCTAssertTrue(estimator.inGap)
    }

    // MARK: - R20

    func testWeakSignalWhenSigmaAboveLimit() {
        var good = SpeedEstimator()
        good.fix(fix(15, accuracy: 0.5, at: 0), arrival: start)
        XCTAssertFalse(good.isWeakSignal, "σ 0.5 is at the limit, not above it")

        var poor = SpeedEstimator()
        poor.fix(fix(15, accuracy: 3, at: 0), arrival: start)
        XCTAssertTrue(poor.isWeakSignal)
    }

    func testWeakSignalDuringGap() {
        var estimator = SpeedEstimator()
        estimator.fix(fix(15, at: 0), arrival: start)

        estimator.unavailable(at: start + 0.5)

        XCTAssertTrue(estimator.isWeakSignal)
    }

    // MARK: - R19

    func testResetForgetsEstimates() {
        var estimator = SpeedEstimator(configuration: .init(usesPositionSpeed: true))
        estimator.fix(fix(15, at: 0), arrival: start)
        estimator.unavailable(at: start + 0.5)

        estimator.reset()

        XCTAssertNil(estimator.gpsOnly)
        XCTAssertFalse(estimator.inGap)
        XCTAssertEqual(estimator.configuration, .init(usesPositionSpeed: true))
    }
}
