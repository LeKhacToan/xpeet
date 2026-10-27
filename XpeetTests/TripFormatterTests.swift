import XCTest
@testable import Xpeet

final class TripFormatterTests: XCTestCase {
    private var formatter: TripFormatter {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return TripFormatter(locale: Locale(identifier: "en_GB"), calendar: calendar)
    }

    /// Tuesday 27 October 2026, 09:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_793_091_600)

    private func trip(meters: Double, moving: TimeInterval, stopped: TimeInterval = 0, startedAt: Date? = nil) -> Trip {
        var trip = Trip()
        trip.startedAt = startedAt ?? now.addingTimeInterval(-(moving + stopped))
        trip.distance = meters
        trip.movingTime = moving
        trip.stoppedTime = stopped
        return trip
    }

    // MARK: - specs/trip-stats R11

    func testLineText() {
        XCTAssertEqual(formatter.line(for: trip(meters: 12_400, moving: 18 * 60 + 30), unit: .kmh), "12.4 km · 18 min")
        XCTAssertEqual(formatter.line(for: trip(meters: 12_400, moving: 18 * 60), unit: .mph), "7.7 mi · 18 min")
        XCTAssertEqual(formatter.line(for: trip(meters: 142_000, moving: 65 * 60), unit: .kmh), "142 km · 1 h 05 min")
        XCTAssertEqual(formatter.distance(99_960, unit: .kmh).value, "100", "rounds to 100.0, so no decimal")
        XCTAssertEqual(formatter.distance(8_000, unit: .kmh).value, "8.0")
    }

    func testEmptyLine() {
        XCTAssertEqual(formatter.line(for: Trip(), unit: .kmh), "0.0 km · 0 min")
    }

    func testDistanceUsesLocaleDecimalSeparator() {
        let french = TripFormatter(locale: Locale(identifier: "fr_FR"), calendar: formatter.calendar)

        XCTAssertEqual(french.distance(12_400, unit: .kmh).value, "12,4")
    }

    // MARK: - R14

    func testSheetStrings() {
        let startedAt = now.addingTimeInterval(-18 * 60) // 08:42 UTC
        XCTAssertEqual(formatter.started(trip(meters: 12_400, moving: 1_080, startedAt: startedAt)), "Started 08:42")
        XCTAssertEqual(formatter.started(Trip()), "Not started")

        XCTAssertEqual(formatter.day(now.addingTimeInterval(-3_600), now: now), "Today")
        XCTAssertEqual(formatter.day(now.addingTimeInterval(-86_400), now: now), "Yesterday")
        let older = formatter.day(now.addingTimeInterval(-2 * 86_400), now: now)
        XCTAssertTrue(older.contains("25") && older.contains("Oct"), older)

        XCTAssertNil(formatter.averageSpeed(trip(meters: 600, moving: 59), unit: .kmh))
        XCTAssertEqual(formatter.averageSpeed(trip(meters: 12_300, moving: 18 * 60), unit: .kmh), "41 km/h")
    }

    func testDisplayOfTracker() {
        var tracker = TripTracker()
        for second in 0...120 {
            tracker.update(at: now.addingTimeInterval(TimeInterval(second - 200)), reading: .live(metersPerSecond: 10))
        }
        tracker.newTrip()

        let display = formatter.display(of: tracker, unit: .kmh, now: now, showsLine: true)

        XCTAssertEqual(display.line, "0.0 km · 0 min")
        XCTAssertTrue(display.isEmpty)
        XCTAssertEqual(display.averageSpeed, "--")
        XCTAssertEqual(display.history.count, 1)
        XCTAssertEqual(display.history.first?.day, "Today")
        XCTAssertEqual(display.history.first?.values, "1.2 km · 2 min · 36 km/h avg")
        XCTAssertNil(formatter.display(of: tracker, unit: .kmh, now: now, showsLine: false).line, "hidden while Unavailable")
    }

    // MARK: - R17

    func testCardValuesAreSpokenInFull() {
        var tracker = TripTracker()
        for second in 0...3_900 {
            tracker.update(at: now.addingTimeInterval(TimeInterval(second - 4_000)), reading: .live(metersPerSecond: 10))
        }

        let display = formatter.display(of: tracker, unit: .kmh, now: now, showsLine: true)

        XCTAssertEqual(display.distanceSpoken, "39.0 kilometres")
        XCTAssertEqual(display.movingTimeSpoken, "1 hour 5 minutes")
        XCTAssertEqual(display.stoppedTimeSpoken, "0 minutes")
        XCTAssertEqual(display.averageSpeedSpoken, "36 kilometres per hour")
        XCTAssertEqual(formatter.display(of: TripTracker(), unit: .kmh, now: now, showsLine: true).averageSpeedSpoken,
                       "Not available yet")
    }

    func testAccessibilityValue() {
        XCTAssertEqual(
            formatter.lineAccessibilityValue(for: trip(meters: 12_400, moving: 18 * 60), unit: .kmh),
            "12.4 kilometres, 18 minutes moving"
        )
        XCTAssertEqual(
            formatter.lineAccessibilityValue(for: trip(meters: 142_000, moving: 61 * 60), unit: .kmh),
            "142 kilometres, 1 hour 1 minute moving"
        )
    }
}
