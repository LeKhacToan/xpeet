import Foundation

/// What the speed screen shows at one moment, as far as a trip is concerned.
enum TripReading: Equatable {
    /// Live (with or without weak signal): the estimate behind the shown number, m/s.
    case live(metersPerSecond: Double)
    /// No usable fix: the screen shows "--".
    case acquiring
    /// Nothing is measured: location off, or the screen is not running.
    case notMeasured
}

/// Adds up the current trip and keeps the history (specs/trip-stats R1-R8). Pure value type, owned by
/// `SpeedometerViewModel`, fed from the same places that update the shown speed.
struct TripTracker: Equatable {
    /// One update adds at most this much time; a longer stall is not measured (R2). Same as the stale interval.
    static let maxInterval: TimeInterval = 5
    /// At or above this the car is moving (the speedometer's zero clamp, 1 km/h).
    static let movingThreshold = 1 / 3.6
    /// One GPS gap adds at most this much lost time (R3).
    static let maxLostGap: TimeInterval = 600
    /// Opening the app this long after the last movement starts a new trip (R6).
    static let newTripAfter: TimeInterval = 1_800
    /// Shorter trips are not kept in history (R8).
    static let minimumDistance = 100.0
    static let historyLimit = 10

    private struct Update: Equatable {
        var time: Date
        /// 0 when stopped.
        var metersPerSecond: Double

        var isMoving: Bool { metersPerSecond > 0 }
    }

    private(set) var current: Trip
    /// Finished trips, newest first.
    private(set) var history: [Trip]
    /// The previous Live update; nil after a gap, so the next update starts a new chain.
    private var previous: Update?
    /// When a GPS gap interrupted movement (R3).
    private var lostSince: Date?

    init(current: Trip = Trip(), history: [Trip] = []) {
        self.current = current
        self.history = history
    }

    mutating func update(at time: Date, reading: TripReading) {
        switch reading {
        case .live(let metersPerSecond):
            live(metersPerSecond, at: time)
        case .acquiring:
            if previous?.isMoving == true, lostSince == nil { lostSince = time }
            previous = nil
        case .notMeasured:
            previous = nil
            lostSince = nil
        }
    }

    /// The speed screen starts running. After a long break the current trip is finished (R6).
    mutating func beginRun(at time: Date) {
        previous = nil
        lostSince = nil
        if let lastMovement = current.lastMovementAt, time.timeIntervalSince(lastMovement) > Self.newTripAfter {
            finishCurrent()
        }
    }

    /// The speed screen stops running: nothing is measured until it runs again.
    mutating func endRun(at time: Date) {
        update(at: time, reading: .notMeasured)
    }

    /// "New trip": the current trip goes to history and an empty one begins (R7).
    mutating func newTrip() {
        finishCurrent()
        previous = nil
        lostSince = nil
    }

    // MARK: Private

    private mutating func live(_ metersPerSecond: Double, at time: Date) {
        if let lostSince {
            current.lostTime += min(max(0, time.timeIntervalSince(lostSince)), Self.maxLostGap)
            self.lostSince = nil
        }
        let update = Update(time: time, metersPerSecond: metersPerSecond >= Self.movingThreshold ? metersPerSecond : 0)
        defer { previous = update }

        if current.isEmpty {
            // The trip starts at its first moving update; time before it is not part of it (R5).
            guard update.isMoving else { return }
            current.startedAt = time
            current.lastUpdateAt = time
            current.lastMovementAt = time
            return
        }
        current.lastUpdateAt = time
        if update.isMoving { current.lastMovementAt = time }

        guard let previous, case let interval = time.timeIntervalSince(previous.time),
              interval > 0, interval <= Self.maxInterval else { return }
        // The newer update decides moving or stopped; distance is the trapezoid of both shown speeds (R1).
        current.distance += (previous.metersPerSecond + update.metersPerSecond) / 2 * interval
        if update.isMoving {
            current.movingTime += interval
        } else {
            current.stoppedTime += interval
        }
    }

    private mutating func finishCurrent() {
        if current.distance >= Self.minimumDistance {
            history.insert(current, at: 0)
            if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
        }
        current = Trip()
    }
}
