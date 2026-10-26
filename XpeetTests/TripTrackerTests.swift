import XCTest
@testable import Xpeet

final class TripTrackerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 10_000)

    /// Feeds Live readings: (seconds from `start`, m/s).
    private func feed(_ tracker: inout TripTracker, _ readings: [(TimeInterval, Double)]) {
        for (seconds, speed) in readings {
            tracker.update(at: start + seconds, reading: .live(metersPerSecond: speed))
        }
    }

    /// A tracker whose current trip has moved `seconds` at `speed` from `start`, one update a second.
    private func moving(for seconds: Int, at speed: Double = 10) -> TripTracker {
        var tracker = TripTracker()
        feed(&tracker, (0...seconds).map { (TimeInterval($0), speed) })
        return tracker
    }

    // MARK: - specs/trip-stats R1

    func testMovingAddsTrapezoidDistanceAndMovingTime() {
        var tracker = TripTracker()

        feed(&tracker, [(0, 10), (1, 12), (2, 14)])

        XCTAssertEqual(tracker.current.distance, 11 + 13, accuracy: 1e-9)
        XCTAssertEqual(tracker.current.movingTime, 2, accuracy: 1e-9)
        XCTAssertEqual(tracker.current.stoppedTime, 0)
    }

    func testStoppedAddsStoppedTimeOnly() {
        var tracker = TripTracker()

        // Braking to a stop still covers ground (trapezoid to 0); standing still covers none.
        feed(&tracker, [(0, 10), (1, 0), (2, 0), (3, 0.1)])

        XCTAssertEqual(tracker.current.distance, 5, accuracy: 1e-9)
        XCTAssertEqual(tracker.current.movingTime, 0)
        XCTAssertEqual(tracker.current.stoppedTime, 3, accuracy: 1e-9)
    }

    func testWeakSignalStillCounts() {
        var tracker = TripTracker()

        // While the reading is still Live, a held speed counts like any other.
        feed(&tracker, [(0, 20), (1, 20), (1.5, 20), (2, 20), (3.5, 20)])

        XCTAssertEqual(tracker.current.distance, 70, accuracy: 1e-9)
        XCTAssertEqual(tracker.current.movingTime, 3.5, accuracy: 1e-9)
    }

    // MARK: - R2

    func testLongIntervalIsNotMeasured() {
        var tracker = TripTracker()
        feed(&tracker, [(0, 10), (1, 10)])

        feed(&tracker, [(7, 10), (8, 10)])

        XCTAssertEqual(tracker.current.movingTime, 2, accuracy: 1e-9, "the 6 s stall adds nothing")
        XCTAssertEqual(tracker.current.distance, 20, accuracy: 1e-9)
    }

    // MARK: - R3

    func testAcquiringAfterMovingIsLost() {
        var tracker = moving(for: 2)

        tracker.update(at: start + 3, reading: .acquiring)
        feed(&tracker, [(33, 10)])

        XCTAssertEqual(tracker.current.lostTime, 30, accuracy: 1e-9)
        XCTAssertEqual(tracker.current.movingTime, 2, accuracy: 1e-9, "the update after a gap starts a new chain")
    }

    func testLostGapIsCappedAtTenMinutes() {
        var tracker = moving(for: 2)

        tracker.update(at: start + 3, reading: .acquiring)
        feed(&tracker, [(1_003, 10)])

        XCTAssertEqual(tracker.current.lostTime, TripTracker.maxLostGap, accuracy: 1e-9)
    }

    func testAcquiringAtStartIsNotLost() {
        var tracker = TripTracker()
        tracker.update(at: start, reading: .acquiring)
        feed(&tracker, [(20, 10), (21, 10), (22, 0)])
        tracker.update(at: start + 23, reading: .acquiring)
        feed(&tracker, [(50, 0)])

        XCTAssertEqual(tracker.current.lostTime, 0, "only a gap that interrupts movement is lost")
    }

    func testApproximateAboveFivePercent() {
        var exact = moving(for: 100)
        exact.update(at: start + 101, reading: .acquiring)
        feed(&exact, [(106, 10)])
        XCTAssertFalse(exact.current.isApproximate, "5 of 105 s is under 5%")

        var approximate = moving(for: 100)
        approximate.update(at: start + 101, reading: .acquiring)
        feed(&approximate, [(107, 10)])
        XCTAssertTrue(approximate.current.isApproximate, "6 of 106 s is over 5%")
    }

    func testNotMeasuredIsNeitherLostNorCounted() {
        var tracker = moving(for: 2)

        tracker.update(at: start + 3, reading: .notMeasured)
        feed(&tracker, [(60, 10)])

        XCTAssertEqual(tracker.current.lostTime, 0)
        XCTAssertEqual(tracker.current.movingTime, 2, accuracy: 1e-9)
    }

    // MARK: - R4

    func testAverageNeedsSixtySeconds() throws {
        XCTAssertNil(moving(for: 59).current.averageMovingSpeed)

        let average = try XCTUnwrap(moving(for: 60, at: 12).current.averageMovingSpeed)
        XCTAssertEqual(average, 12, accuracy: 1e-9)
    }

    func testTotalTimeIncludesUnmeasured() {
        var tracker = moving(for: 10)
        tracker.endRun(at: start + 11)

        XCTAssertEqual(tracker.current.totalTime(until: start + 100), 100, accuracy: 1e-9)
        XCTAssertEqual(tracker.current.measuredTime, 10, accuracy: 1e-9)
    }

    // MARK: - R5

    func testEmptyTripHasNoStart() {
        var tracker = TripTracker()

        feed(&tracker, [(0, 0), (1, 0), (2, 0.2)])

        XCTAssertTrue(tracker.current.isEmpty)
        XCTAssertNil(tracker.current.startedAt)
        XCTAssertEqual(tracker.current, Trip())
    }

    func testTripStartsAtFirstMovement() {
        var tracker = TripTracker()

        feed(&tracker, [(0, 0), (1, 0), (2, 5)])

        XCTAssertEqual(tracker.current.startedAt, start + 2)
        XCTAssertEqual(tracker.current.measuredTime, 0, "time before the start is not part of the trip")
    }

    // MARK: - R6

    func testBeginRunAfterThirtyMinutesStartsNewTrip() {
        var tracker = moving(for: 20)
        let trip = tracker.current
        tracker.endRun(at: start + 21)

        tracker.beginRun(at: start + 20 + TripTracker.newTripAfter + 1)

        XCTAssertEqual(tracker.history, [trip])
        XCTAssertTrue(tracker.current.isEmpty)
    }

    func testShortBreakContinues() {
        var tracker = moving(for: 20)
        let trip = tracker.current
        tracker.endRun(at: start + 21)

        tracker.beginRun(at: start + 20 + TripTracker.newTripAfter - 1)

        XCTAssertEqual(tracker.current, trip)
        XCTAssertEqual(tracker.history, [])
    }

    // MARK: - R7, R8

    func testNewTripArchivesCurrent() {
        var tracker = moving(for: 20)
        let trip = tracker.current

        tracker.newTrip()

        XCTAssertEqual(tracker.history, [trip])
        XCTAssertTrue(tracker.current.isEmpty)
    }

    func testShortTripIsDropped() {
        var tracker = moving(for: 9)
        XCTAssertLessThan(tracker.current.distance, TripTracker.minimumDistance)

        tracker.newTrip()

        XCTAssertEqual(tracker.history, [])
    }

    func testHistoryKeepsTenNewest() {
        var tracker = TripTracker()
        for index in 0..<12 {
            let offset = TimeInterval(index * 100)
            feed(&tracker, (0...20).map { (offset + TimeInterval($0), 10 + Double(index)) })
            tracker.newTrip()
        }

        XCTAssertEqual(tracker.history.count, TripTracker.historyLimit)
        XCTAssertEqual(tracker.history.first?.startedAt, start + 1_100, "newest first")
        XCTAssertEqual(tracker.history.last?.startedAt, start + 200)
    }

    // MARK: - R18, R19

    func testConstantSpeedDistanceWithinHalfPercent() {
        var tracker = TripTracker()

        feed(&tracker, (0...400).map { (TimeInterval($0) / 2, 25) })

        XCTAssertEqual(tracker.current.distance, 25 * tracker.current.movingTime, accuracy: 25 * 200 * 0.005)
        XCTAssertEqual(tracker.current.movingTime, 200, accuracy: 1e-9)
    }

    func testMovingPlusStoppedEqualsLiveTime() {
        var tracker = TripTracker()
        let readings: [(TimeInterval, Double)] = [
            (0, 8), (0.5, 9), (1.3, 0), (2.1, 0), (4.0, 3), (4.5, 12), (8.9, 12), (9.4, 0), (10.0, 0.1), (11.2, 14),
        ]

        feed(&tracker, readings)

        // Date keeps about 1e-7 s of precision this far from its reference date.
        XCTAssertEqual(tracker.current.measuredTime, 11.2, accuracy: 1e-6)
        XCTAssertEqual(tracker.current.movingTime + tracker.current.stoppedTime, tracker.current.measuredTime)
    }
}
