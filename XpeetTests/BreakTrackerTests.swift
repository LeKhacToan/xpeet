import XCTest
@testable import Xpeet

final class BreakTrackerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 10_000)
    private let moving = 15.0
    private let stopped = 0.0

    /// Live readings every `step` seconds from `from` (seconds after `start`) for `seconds`. Returns the end time.
    @discardableResult
    private func feed(_ tracker: inout BreakTracker, from: TimeInterval, seconds: TimeInterval, metersPerSecond: Double,
                      step: TimeInterval = 0.5) -> TimeInterval {
        var time = from
        tracker.update(at: start + time, reading: .live(metersPerSecond: metersPerSecond))
        while time < from + seconds {
            time += step
            tracker.update(at: start + time, reading: .live(metersPerSecond: metersPerSecond))
        }
        return time
    }

    // MARK: - R1

    func testLiveUpdatesAddDriveTimeMovingOrStopped() {
        var tracker = BreakTracker()
        var time = feed(&tracker, from: 0, seconds: 600, metersPerSecond: moving)
        time = feed(&tracker, from: time, seconds: 120, metersPerSecond: stopped)
        XCTAssertEqual(tracker.stretch.drivingTime, 720, accuracy: 1e-9, "a short stop counts as driving")
    }

    func testIntervalOverFiveSecondsAddsNothing() {
        var tracker = BreakTracker()
        tracker.update(at: start, reading: .live(metersPerSecond: moving))
        tracker.update(at: start + 4, reading: .live(metersPerSecond: moving))
        tracker.update(at: start + 10, reading: .live(metersPerSecond: moving))
        XCTAssertEqual(tracker.stretch.drivingTime, 4)
    }

    func testAcquiringAndNotMeasuredAddNothing() {
        var tracker = BreakTracker()
        let time = feed(&tracker, from: 0, seconds: 60, metersPerSecond: moving)
        tracker.update(at: start + time + 1, reading: .acquiring)
        tracker.update(at: start + time + 2, reading: .acquiring)
        tracker.update(at: start + time + 3, reading: .notMeasured)
        tracker.update(at: start + time + 4, reading: .live(metersPerSecond: moving))
        XCTAssertEqual(tracker.stretch.drivingTime, 60, accuracy: 1e-9, "the update after a gap starts a new chain")
    }

    func testUsesTheTripThresholds() {
        var tracker = BreakTracker()
        tracker.update(at: start, reading: .live(metersPerSecond: TripTracker.movingThreshold - 0.01))
        XCTAssertTrue(tracker.stretch.isEmpty, "below 1 km/h is stopped")
        tracker.update(at: start + 1, reading: .live(metersPerSecond: TripTracker.movingThreshold))
        XCTAssertFalse(tracker.stretch.isEmpty)
        tracker.update(at: start + 1 + TripTracker.maxInterval, reading: .live(metersPerSecond: moving))
        XCTAssertEqual(tracker.stretch.drivingTime, TripTracker.maxInterval, "exactly the cap still counts")
    }

    // MARK: - R2

    func testStretchStartsAtFirstMovement() {
        var tracker = BreakTracker()
        feed(&tracker, from: 0, seconds: 30, metersPerSecond: moving)
        XCTAssertEqual(tracker.stretch.startedAt, start)
        XCTAssertEqual(tracker.stretch.lastMovementAt, start + 30)
    }

    func testStoppedBeforeFirstMovementIsNotCounted() {
        var tracker = BreakTracker()
        let time = feed(&tracker, from: 0, seconds: 300, metersPerSecond: stopped)
        XCTAssertTrue(tracker.stretch.isEmpty)
        feed(&tracker, from: time + 0.5, seconds: 10, metersPerSecond: moving)
        XCTAssertEqual(tracker.stretch.startedAt, start + time + 0.5)
        XCTAssertEqual(tracker.stretch.drivingTime, 10, accuracy: 1e-9)
    }

    // MARK: - R3

    func testSameTimelineAtThirtyAndOneTwentyGivesSameStretch() {
        func run(kmh: Double) -> [BreakTracker] {
            var tracker = BreakTracker()
            var states: [BreakTracker] = []
            var time: TimeInterval = 0
            // Two hours and a bit, with lights and a 10 min jam between the moving stretches.
            for (seconds, isMoving) in [(3_000.0, true), (60, false), (3_000, true), (600, false), (1_500, true)] {
                time = feed(&tracker, from: time, seconds: seconds, metersPerSecond: isMoving ? kmh / 3.6 : 0, step: 5)
                states.append(tracker)
            }
            return states
        }
        let slow = run(kmh: 30), fast = run(kmh: 120)
        XCTAssertEqual(slow.map(\.stretch), fast.map(\.stretch))
        XCTAssertEqual(slow.map(\.reminderHours), fast.map(\.reminderHours))
        XCTAssertEqual(slow.last?.reminderHours, 2)
    }

    // MARK: - R4

    func testStopOf14m59sThenMovementKeepsStretch() {
        var tracker = BreakTracker()
        var time = feed(&tracker, from: 0, seconds: 600, metersPerSecond: moving)
        time = feed(&tracker, from: time + 0.5, seconds: 899, metersPerSecond: stopped)
        feed(&tracker, from: time + 0.5, seconds: 1, metersPerSecond: moving)
        XCTAssertFalse(tracker.stretch.isEmpty)
        XCTAssertEqual(tracker.stretch.drivingTime, 600 + 0.5 + 899 + 0.5 + 1, accuracy: 1e-6)
    }

    func testStopOf15MinutesIsARest() {
        var tracker = BreakTracker()
        var time = feed(&tracker, from: 0, seconds: 600, metersPerSecond: moving)
        time = feed(&tracker, from: time + 0.5, seconds: 899, metersPerSecond: stopped)
        XCTAssertFalse(tracker.stretch.isEmpty, "the stop is 14:59.5 so far")
        tracker.update(at: start + time + 0.5, reading: .live(metersPerSecond: stopped))
        XCTAssertTrue(tracker.stretch.isEmpty, "15:00 stopped is a rest")
        XCTAssertEqual(tracker.stretch.drivingTime, 0)
        XCTAssertNil(tracker.stretch.lastMovementAt)
    }

    func testAcquiringGapPausesTheStop() {
        var tracker = BreakTracker()
        var time = feed(&tracker, from: 0, seconds: 600, metersPerSecond: moving)
        time = feed(&tracker, from: time + 0.5, seconds: 600, metersPerSecond: stopped)
        tracker.update(at: start + time + 1, reading: .acquiring)
        time = feed(&tracker, from: time + 3, seconds: 300, metersPerSecond: stopped)
        XCTAssertTrue(tracker.stretch.isEmpty, "10 min + 5 min stopped around a 3 s gap is a rest")
    }

    func testEndRunPausesTheStop() {
        var tracker = BreakTracker()
        var time = feed(&tracker, from: 0, seconds: 600, metersPerSecond: moving)
        time = feed(&tracker, from: time + 0.5, seconds: 600, metersPerSecond: stopped)
        tracker.endRun(at: start + time)
        tracker.beginRun(at: start + time + 120)
        feed(&tracker, from: time + 120, seconds: 300, metersPerSecond: stopped)
        XCTAssertTrue(tracker.stretch.isEmpty)
    }

    func testMovementRestartsTheStop() {
        var tracker = BreakTracker()
        var time = feed(&tracker, from: 0, seconds: 600, metersPerSecond: moving)
        time = feed(&tracker, from: time + 0.5, seconds: 600, metersPerSecond: stopped)
        tracker.update(at: start + time + 0.5, reading: .live(metersPerSecond: moving))
        feed(&tracker, from: time + 1, seconds: 600, metersPerSecond: stopped)
        XCTAssertFalse(tracker.stretch.isEmpty, "two 10 min stops split by movement are no rest")
    }

    // MARK: - R5

    func testBeginRunAfter29MinutesKeeps() {
        var tracker = BreakTracker()
        let time = feed(&tracker, from: 0, seconds: 600, metersPerSecond: moving)
        tracker.endRun(at: start + time)
        tracker.beginRun(at: start + time + 29 * 60)
        XCTAssertEqual(tracker.stretch.drivingTime, 600, accuracy: 1e-9)
    }

    func testBeginRunAfter31MinutesClears() {
        var tracker = BreakTracker()
        let time = feed(&tracker, from: 0, seconds: 600, metersPerSecond: moving)
        tracker.endRun(at: start + time)
        tracker.beginRun(at: start + time + 31 * 60)
        XCTAssertTrue(tracker.stretch.isEmpty)
    }

    func testGapAfterNotMeasuredClearsAfter31Minutes() {
        var tracker = BreakTracker()
        let time = feed(&tracker, from: 0, seconds: 600, metersPerSecond: moving)
        tracker.update(at: start + time + 1, reading: .notMeasured)
        tracker.update(at: start + time + 29 * 60, reading: .acquiring)
        XCTAssertFalse(tracker.stretch.isEmpty, "29 min")
        tracker.update(at: start + time + 31 * 60, reading: .acquiring)
        XCTAssertTrue(tracker.stretch.isEmpty, "31 min")
    }

    func testClosedGapThenStoppedClearsJustAfterThirtyMinutes() {
        var tracker = BreakTracker()
        let t0 = feed(&tracker, from: 0, seconds: 600, metersPerSecond: moving)
        tracker.endRun(at: start + t0)
        tracker.beginRun(at: start + t0 + 20 * 60)
        feed(&tracker, from: t0 + 20 * 60, seconds: 10 * 60, metersPerSecond: stopped)
        XCTAssertFalse(tracker.stretch.isEmpty, "kept at t0 + 30 min")
        tracker.update(at: start + t0 + 30 * 60 + 0.5, reading: .live(metersPerSecond: stopped))
        XCTAssertTrue(tracker.stretch.isEmpty, "cleared within 1 s after it")
    }

    // MARK: - R7

    func testClearEmptiesTheStretch() {
        var tracker = BreakTracker()
        feed(&tracker, from: 0, seconds: 600, metersPerSecond: moving)
        tracker.clear()
        XCTAssertEqual(tracker.stretch, DrivingStretch())
    }

    // MARK: - R8, R9

    func testReminderAtTwoHoursNotBefore() {
        var tracker = BreakTracker()
        let time = feed(&tracker, from: 0, seconds: 7_199.5, metersPerSecond: moving)
        XCTAssertNil(tracker.reminderHours, "1:59:59.5")
        tracker.update(at: start + time + 0.5, reading: .live(metersPerSecond: moving))
        XCTAssertEqual(tracker.reminderHours, 2, "2:00:00")
    }

    func testReminderHoursRoundDown() {
        let cases: [(TimeInterval, Int?)] = [(7_199, nil), (7_200, 2), (2 * 3_600 + 59 * 60, 2), (10_800, 3), (36_000, 10)]
        for (drivingTime, hours) in cases {
            let tracker = BreakTracker(stretch: DrivingStretch(startedAt: start, drivingTime: drivingTime, lastMovementAt: start))
            XCTAssertEqual(tracker.reminderHours, hours, "\(drivingTime)")
        }
    }

    // MARK: - R14

    func testInconsistentStretchBecomesEmpty() {
        XCTAssertTrue(BreakTracker(stretch: DrivingStretch(startedAt: start, drivingTime: 60)).stretch.isEmpty)
        XCTAssertTrue(BreakTracker(stretch: DrivingStretch(startedAt: start, drivingTime: -1, lastMovementAt: start))
            .stretch.isEmpty)
        XCTAssertTrue(BreakTracker(stretch: DrivingStretch(startedAt: start, drivingTime: .infinity, lastMovementAt: start))
            .stretch.isEmpty)
    }
}
