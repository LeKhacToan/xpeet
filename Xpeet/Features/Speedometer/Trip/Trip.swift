import Foundation

/// One trip's totals (specs/trip-stats R9). Only totals and times: no position, course or speed history.
struct Trip: Codable, Equatable {
    /// Average moving speed is shown only after this much moving time (R4).
    static let averageMinimumMovingTime: TimeInterval = 60
    /// A trip is approximate when more than this share of its moving + lost time was lost (R3).
    static let approximateLostShare = 0.05

    /// The first moving update. Nil while the trip is empty (R5).
    var startedAt: Date?
    var lastUpdateAt: Date?
    var lastMovementAt: Date?
    /// Metres.
    var distance: Double = 0
    var movingTime: TimeInterval = 0
    var stoppedTime: TimeInterval = 0
    /// GPS lost (Acquiring) while moving (R3).
    var lostTime: TimeInterval = 0

    var isEmpty: Bool { startedAt == nil }

    /// Time the app was measuring: moving + stopped (R19).
    var measuredTime: TimeInterval { movingTime + stoppedTime }

    /// m/s, or nil before `averageMinimumMovingTime` of moving.
    var averageMovingSpeed: Double? {
        movingTime >= Self.averageMinimumMovingTime ? distance / movingTime : nil
    }

    var isApproximate: Bool {
        let total = movingTime + lostTime
        return total > 0 && lostTime / total > Self.approximateLostShare
    }

    /// From the start to `end`, including time not measured (R4). Zero for an empty trip.
    func totalTime(until end: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, end.timeIntervalSince(startedAt))
    }
}
