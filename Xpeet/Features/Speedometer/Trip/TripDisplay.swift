import Foundation

/// Everything the trip line and the trip sheet show, already formatted (specs/trip-stats R11, R14, R17).
/// `SpeedometerViewModel` assigns a new one only when a string changes, so ticks don't redraw the screen.
struct TripDisplay: Equatable {
    struct Row: Equatable, Identifiable {
        var id: Int
        /// "Today", "Yesterday" or a weekday with date.
        var day: String
        var startTime: String
        /// "8.6 km · 15 min · 34 km/h avg".
        var values: String
        var isApproximate: Bool
        var accessibilityLabel: String
    }

    /// "12.4 km · 18 min"; nil hides the line (location off, R11).
    var line: String?
    /// "12.4 kilometres, 18 minutes moving".
    var lineAccessibilityValue: String
    /// "Started 08:42" or "Not started".
    var started: String
    var isEmpty: Bool
    var distanceValue: String
    var distanceUnit: String
    var movingTime: String
    var stoppedTime: String
    var totalTime: String
    /// "41 km/h" or "--".
    var averageSpeed: String
    var isApproximate: Bool
    /// Newest first.
    var history: [Row]
}
