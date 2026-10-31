import Foundation

/// Adds up the driving stretch for the break reminder (specs/break-reminder R1-R9). Pure value type, owned by
/// `SpeedometerViewModel` and fed with the same readings, at the same moments, as `TripTracker`.
struct BreakTracker: Equatable {
    /// At least this much drive time shows the reminder (R8).
    static let breakAfter: TimeInterval = 7_200
    /// A stop this long is a rest (R4).
    static let restAfter: TimeInterval = 900

    private(set) var stretch: DrivingStretch
    /// The previous Live update; nil after a gap, so the next update starts a new chain.
    private var previous: Date?
    /// Stopped time since the last moving update. Kept across gaps, so a gap pauses it (R4). Memory only.
    private var stop: TimeInterval = 0

    init(stretch: DrivingStretch = DrivingStretch()) {
        // A stretch that can't be right is treated as unreadable (R14).
        let isConsistent = stretch.isEmpty
            || (stretch.lastMovementAt != nil && stretch.drivingTime.isFinite && stretch.drivingTime >= 0)
        self.stretch = isConsistent ? stretch : DrivingStretch()
    }

    /// Drive time in whole hours once a break is due, else nil (R8, R9).
    var reminderHours: Int? {
        stretch.drivingTime >= Self.breakAfter ? Int(stretch.drivingTime / 3_600) : nil
    }

    mutating func update(at time: Date, reading: TripReading) {
        clearIfRestedAcrossGap(at: time)
        guard case .live(let metersPerSecond) = reading else {
            // Neither driving nor rest: the stop is paused, not ended (R1, R4).
            previous = nil
            return
        }
        let isMoving = metersPerSecond >= TripTracker.movingThreshold
        defer { previous = time }

        if stretch.isEmpty {
            // The stretch starts at its first moving update (R2).
            guard isMoving else { return }
            stretch = DrivingStretch(startedAt: time, drivingTime: 0, lastMovementAt: time)
            stop = 0
            return
        }
        if isMoving {
            stretch.lastMovementAt = time
            stop = 0
        }
        guard let previous else { return }
        let interval = time.timeIntervalSince(previous)
        guard interval > 0, interval <= TripTracker.maxInterval else { return }
        stretch.drivingTime += interval
        if !isMoving {
            stop += interval
            if stop >= Self.restAfter { clear() }
        }
    }

    /// The speed screen starts running: a long enough gap since the last movement was a rest (R5).
    mutating func beginRun(at time: Date) {
        previous = nil
        clearIfRestedAcrossGap(at: time)
    }

    /// The speed screen stops running: nothing is measured until it runs again.
    mutating func endRun(at time: Date) {
        update(at: time, reading: .notMeasured)
    }

    /// A rest, or "Delete all trips" (R4, R5, R7).
    mutating func clear() {
        stretch = DrivingStretch()
        stop = 0
        previous = nil
    }

    private mutating func clearIfRestedAcrossGap(at time: Date) {
        guard let lastMovement = stretch.lastMovementAt,
              time.timeIntervalSince(lastMovement) > TripTracker.newTripAfter else { return }
        clear()
    }
}
