import Foundation

/// Keeps the current trip and the history in `UserDefaults`, as JSON (specs/trip-stats R9-R10). Totals only.
struct TripStore {
    static let currentKey = "trip.current"
    static let historyKey = "trip.history"

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
