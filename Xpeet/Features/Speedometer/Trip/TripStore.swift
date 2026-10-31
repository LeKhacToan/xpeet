import Foundation

/// Keeps the current trip and the history in `UserDefaults`, as JSON (specs/trip-stats R9-R10). Totals only.
/// Also the driving stretch behind the break reminder, under its own key (specs/break-reminder R13, R14).
struct TripStore {
    static let currentKey = "trip.current"
    static let historyKey = "trip.history"
    static let stretchKey = "trip.stretch"

    let defaults: UserDefaults

    /// The stored tracker. Missing or unreadable data gives an empty trip and empty history, never a crash.
    func load() -> TripTracker {
        let decoder = Self.decoder
        let current = defaults.data(forKey: Self.currentKey).flatMap { try? decoder.decode(Trip.self, from: $0) }
        let history = defaults.data(forKey: Self.historyKey).flatMap { try? decoder.decode([Trip].self, from: $0) }
        guard let current, let history else { return TripTracker() }
        return TripTracker(current: current, history: Array(history.prefix(TripTracker.historyLimit)))
    }

    func save(_ tracker: TripTracker) {
        let encoder = Self.encoder
        guard let current = try? encoder.encode(tracker.current),
              let history = try? encoder.encode(tracker.history) else { return }
        defaults.set(current, forKey: Self.currentKey)
        defaults.set(history, forKey: Self.historyKey)
    }

    /// The stored stretch. Missing or unreadable data gives an empty stretch; the trip keys are never touched.
    func loadStretch() -> DrivingStretch {
        defaults.data(forKey: Self.stretchKey).flatMap { try? Self.decoder.decode(DrivingStretch.self, from: $0) }
            ?? DrivingStretch()
    }

    func save(_ stretch: DrivingStretch) {
        guard let data = try? Self.encoder.encode(stretch) else { return }
        defaults.set(data, forKey: Self.stretchKey)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
