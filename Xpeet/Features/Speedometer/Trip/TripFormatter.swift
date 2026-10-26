import Foundation

/// Turns trip totals into the strings the line and the sheet show (specs/trip-stats R11, R14, R17).
/// Pure: the locale and calendar (with its time zone) are injected, so tests are stable.
struct TripFormatter {
    static let metersPerMile = 1_609.344

    let locale: Locale
    let calendar: Calendar

    func display(of tracker: TripTracker, unit: SpeedUnit, now: Date, showsLine: Bool) -> TripDisplay {
        let trip = tracker.current
        let distance = distance(trip.distance, unit: unit)
        return TripDisplay(
            line: showsLine ? line(for: trip, unit: unit) : nil,
            lineAccessibilityValue: lineAccessibilityValue(for: trip, unit: unit),
            started: started(trip),
            isEmpty: trip.isEmpty,
            distanceValue: distance.value,
            distanceUnit: distance.unit,
            movingTime: duration(trip.movingTime),
            stoppedTime: duration(trip.stoppedTime),
            totalTime: duration(trip.totalTime(until: now)),
            averageSpeed: averageSpeed(trip, unit: unit) ?? "--",
            distanceSpoken: spokenDistance(trip.distance, unit: unit),
            movingTimeSpoken: spokenDuration(trip.movingTime),
            stoppedTimeSpoken: spokenDuration(trip.stoppedTime),
            totalTimeSpoken: spokenDuration(trip.totalTime(until: now)),
            averageSpeedSpoken: trip.averageMovingSpeed.map { spokenSpeed($0, unit: unit) } ?? String(localized: "Not available yet"),
            isApproximate: trip.isApproximate,
            history: tracker.history.enumerated().map { index, trip in row(trip, id: index, unit: unit, now: now) }
        )
    }

    // MARK: Pieces

    /// "12.4 km · 18 min" (R11).
    func line(for trip: Trip, unit: SpeedUnit) -> String {
        let distance = distance(trip.distance, unit: unit)
        return "\(distance.value) \(distance.unit) · \(duration(trip.movingTime))"
    }

    /// "12.4 kilometres, 18 minutes moving" (R17).
    func lineAccessibilityValue(for trip: Trip, unit: SpeedUnit) -> String {
        String(localized: "\(spokenDistance(trip.distance, unit: unit)), \(spokenDuration(trip.movingTime)) moving")
    }

    /// One decimal below 100, none from 100 up (R11).
    func distance(_ meters: Double, unit: SpeedUnit) -> (value: String, unit: String) {
        let value = unit == .kmh ? meters / 1_000 : meters / Self.metersPerMile
        let digits = (value * 10).rounded() / 10 < 100 ? 1 : 0
        return (value.formatted(.number.precision(.fractionLength(digits)).locale(locale)), unit == .kmh ? "km" : "mi")
    }

    /// "0 min" … "59 min", then "1 h 05 min".
    func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        guard minutes >= 60 else { return String(localized: "\(minutes) min") }
        let remainder = String(format: "%02d", minutes % 60)
        return String(localized: "\(minutes / 60) h \(remainder) min")
    }

    func averageSpeed(_ trip: Trip, unit: SpeedUnit) -> String? {
        trip.averageMovingSpeed.map { "\(Int(unit.value(fromMetersPerSecond: $0).rounded())) \(unit.symbol)" }
    }

    /// "Started 08:42" or "Not started" (R14).
    func started(_ trip: Trip) -> String {
        guard let startedAt = trip.startedAt else { return String(localized: "Not started") }
        return String(localized: "Started \(time(startedAt))")
    }

    /// "Today", "Yesterday", or a weekday with date.
    func day(_ date: Date, now: Date) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday")
        }
        return date.formatted(dateStyle.weekday(.abbreviated).day().month(.abbreviated))
    }

    // MARK: Private

    private var dateStyle: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    private func time(_ date: Date) -> String {
        date.formatted(dateStyle.hour().minute())
    }

    private func row(_ trip: Trip, id: Int, unit: SpeedUnit, now: Date) -> TripDisplay.Row {
        let start = trip.startedAt ?? now
        let distance = distance(trip.distance, unit: unit)
        var values = "\(distance.value) \(distance.unit) · \(duration(trip.movingTime))"
        var spoken = "\(day(start, now: now)) \(time(start)), \(spokenDistance(trip.distance, unit: unit)), "
            + String(localized: "\(spokenDuration(trip.movingTime)) moving")
        if let average = averageSpeed(trip, unit: unit) {
            values += " · " + String(localized: "\(average) avg")
            spoken += ", " + String(localized: "average \(spokenSpeed(trip.averageMovingSpeed ?? 0, unit: unit))")
        }
        if trip.isApproximate { spoken += ", " + String(localized: "approximate") }
        return TripDisplay.Row(
            id: id,
            day: day(start, now: now),
            startTime: time(start),
            values: values,
            isApproximate: trip.isApproximate,
            accessibilityLabel: spoken
        )
    }

    private func spokenDistance(_ meters: Double, unit: SpeedUnit) -> String {
        let measurement = unit == .kmh
            ? Measurement(value: meters / 1_000, unit: UnitLength.kilometers)
            : Measurement(value: meters / Self.metersPerMile, unit: UnitLength.miles)
        let digits = (measurement.value * 10).rounded() / 10 < 100 ? 1 : 0
        return measurement.formatted(.measurement(
            width: .wide, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(digits))
        ).locale(locale))
    }

    private func spokenDuration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        let style = Measurement<UnitDuration>.FormatStyle(width: .wide, locale: locale)
        let minutePart = Measurement(value: Double(minutes % 60), unit: UnitDuration.minutes).formatted(style)
        guard minutes >= 60 else { return minutePart }
        return Measurement(value: Double(minutes / 60), unit: UnitDuration.hours).formatted(style) + " " + minutePart
    }

    private func spokenSpeed(_ metersPerSecond: Double, unit: SpeedUnit) -> String {
        Measurement(value: unit.value(fromMetersPerSecond: metersPerSecond).rounded(), unit: unit.unitSpeed)
            .formatted(.measurement(width: .wide, usage: .asProvided).locale(locale))
    }
}
