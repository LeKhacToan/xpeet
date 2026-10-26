import XCTest
@testable import Xpeet

final class MotionClockTests: XCTestCase {
    private let boot = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - specs/speed-accuracy R3

    func testNoDateBeforeFirstSample() {
        XCTAssertNil(MotionClock().date(for: 10))
    }

    func testMapsMotionTimestampToDate() {
        var clock = MotionClock()

        clock.observe(timestamp: 100, arrival: boot + 100)

        XCTAssertEqual(clock.date(for: 105), boot + 105)
    }

    func testOffsetIsRunningMinimum() {
        var clock = MotionClock()
        clock.observe(timestamp: 100, arrival: boot + 100.08)
        clock.observe(timestamp: 101, arrival: boot + 101.02)
        clock.observe(timestamp: 102, arrival: boot + 102.30)

        // The least-delayed sample (20 ms) wins; a late delivery does not move it.
        XCTAssertEqual(clock.offset ?? 0, boot.timeIntervalSince1970 + 0.02, accuracy: 1e-6)
    }
}
