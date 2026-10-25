import Foundation

/// Kalman filter on GPS speed alone (specs/speed-accuracy R5). State: speed and acceleration, constant-acceleration
/// model driven by white jerk. Each fix counts according to its variance, so an inaccurate fix moves it less.
struct GPSOnlyFilter: Equatable {
    /// Jerk spectral density, (m/s²)²/s: how fast acceleration may change.
    static let jerkNoise = 4.0
    /// Acceleration uncertainty at the first fix, (m/s²)².
    static let initialAccelerationVariance = 4.0
    /// A fix needing more than this acceleration from the prediction is rejected, m/s².
    static let maxAcceleration = 12.0
    /// Speed variance once stopped, (m/s)².
    static let stoppedVariance = 0.0001

    private(set) var speed: Double
    private(set) var acceleration: Double
    private(set) var timestamp: Date
    // Covariance of [speed, acceleration]; symmetric, so p10 == p01.
    private var p00: Double
    private var p01: Double
    private var p11: Double

    var variance: Double { p00 }

    init(speed: Double, variance: Double, at timestamp: Date) {
        self.speed = speed
        self.acceleration = 0
        self.timestamp = timestamp
        self.p00 = variance
        self.p01 = 0
        self.p11 = Self.initialAccelerationVariance
    }

    static func stopped(at timestamp: Date) -> GPSOnlyFilter {
        GPSOnlyFilter(speed: 0, variance: stoppedVariance, at: timestamp)
    }

    /// Applies one speed measurement. Returns false, leaving the filter unchanged, for a physically impossible jump.
    /// A measurement at or before the last one is applied without a predict step.
    mutating func update(speed measured: Double, variance measurementVariance: Double, at time: Date) -> Bool {
        let interval = time.timeIntervalSince(timestamp)
        // Judged against the last accepted speed, not the prediction: after one accepted glitch the extrapolated
        // acceleration would carry the prediction away and lock out every true fix. At least the nominal 1 s fix
        // interval, so two fixes with one timestamp are not "infinitely fast".
        guard abs(measured - speed) <= Self.maxAcceleration * max(interval, 1) else { return false }

        var next = predicted(at: time)
        let innovation = measured - next.speed
        let innovationVariance = next.p00 + measurementVariance
        let gainSpeed = next.p00 / innovationVariance
        let gainAcceleration = next.p01 / innovationVariance
        next.speed = max(0, next.speed + gainSpeed * innovation)
        let acceleration = next.acceleration + gainAcceleration * innovation
        next.acceleration = min(max(acceleration, -Self.maxAcceleration), Self.maxAcceleration)
        next.p11 -= gainAcceleration * next.p01
        next.p01 -= gainSpeed * next.p01
        next.p00 -= gainSpeed * next.p00
        next.timestamp = max(time, timestamp)
        self = next
        return true
    }

    mutating func stop(at time: Date) {
        self = .stopped(at: max(time, timestamp))
    }

    /// The state predicted forward to `time`, with no measurement. Unchanged for a time at or before the last update.
    func predicted(at time: Date) -> GPSOnlyFilter {
        let interval = time.timeIntervalSince(timestamp)
        guard interval > 0 else { return self }
        var next = self
        next.predict(by: interval)
        next.timestamp = time
        return next
    }

    private mutating func predict(by interval: TimeInterval) {
        let dt = interval
        speed += acceleration * dt
        let q = Self.jerkNoise
        p00 += 2 * dt * p01 + dt * dt * p11 + q * dt * dt * dt / 3
        p01 += dt * p11 + q * dt * dt / 2
        p11 += q * dt
    }
}
