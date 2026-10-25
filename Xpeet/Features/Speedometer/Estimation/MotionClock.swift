import Foundation

/// Maps Core Motion timestamps (seconds since boot) to wall-clock dates, so motion lines up with fixes
/// (specs/speed-accuracy R3). The offset is the smallest (arrival − timestamp) seen: the least-delayed sample is
/// closest to the true offset. Avoids `ProcessInfo.systemUptime`, a required-reason API.
struct MotionClock: Equatable {
    /// Wall-clock seconds since 1970 minus seconds since boot. Nil until the first sample.
    private(set) var offset: TimeInterval?

    mutating func observe(timestamp: TimeInterval, arrival: Date) {
        let candidate = arrival.timeIntervalSince1970 - timestamp
        offset = min(offset ?? candidate, candidate)
    }

    func date(for timestamp: TimeInterval) -> Date? {
        offset.map { Date(timeIntervalSince1970: timestamp + $0) }
    }
}
