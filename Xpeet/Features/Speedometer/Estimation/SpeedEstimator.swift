import Foundation

/// Turns location fixes (and, later, motion) into the speed to show (specs/speed-accuracy R4-R20).
/// Pure value type: the same inputs always give the same outputs, so recorded drives replay exactly.
struct SpeedEstimator: Equatable {
    struct Configuration: Equatable, Sendable {
        static let fusionLaunchArgumentKey = "XpeetFusion"

        /// Show the fused estimate when it is ready (R14). Off until the accuracy gate passes (R28).
        var fusionEnabled = false
        /// Use speed from position change for fixes without Doppler speed (R13).
        var usesPositionSpeed = false

        /// As shipped; in Debug builds `-XpeetFusion YES` turns fusion on for a test drive (R14).
        static func launchDefault(_ arguments: [String: Any] = LaunchArguments.current) -> Configuration {
            var configuration = Configuration()
            #if DEBUG
            configuration.fusionEnabled = LaunchArguments.bool(fusionLaunchArgumentKey, in: arguments)
            #endif
            return configuration
        }
    }

    struct Estimate: Equatable, Codable, Sendable {
        var metersPerSecond: Double
        /// 1σ uncertainty, m/s.
        var sigma: Double
    }

    enum Source: String, Codable, Sendable {
        case gpsOnly
        case fused
    }

    enum FixOutcome: Equatable {
        case accepted
        /// Failed the physics bound.
        case rejected
        /// Carried no usable speed.
        case ignored
    }

    // MARK: Constants (spec Data & API table)

    /// k_R: scales the reported speed accuracy into the fix's 1σ.
    static let speedAccuracyScale = 1.0
    /// Floor for the reported speed accuracy, m/s, so no fix is treated as perfect.
    static let minimumSpeedAccuracy = 0.1
    /// No accepted fix for this long while moving starts a gap (R17).
    static let gapStartInterval: TimeInterval = 1.5
    /// Above this 1σ the reading is flagged as weak signal (R20), m/s.
    static let weakSignalSigma = 0.5
    /// Position-derived speed needs both fixes at least this accurate, m (R13).
    static let positionSpeedMaxAccuracy = 10.0
    /// ... and this far apart.
    static let positionSpeedInterval: ClosedRange<TimeInterval> = 2...5

    /// Every tuning constant, written into each recorded drive's header so a replay knows what produced it (R22).
    static func recordedConstants(_ configuration: Configuration) -> [String: Double] {
        [
            "speedAccuracyScale": speedAccuracyScale,
            "minimumSpeedAccuracy": minimumSpeedAccuracy,
            "gapStartInterval": gapStartInterval,
            "weakSignalSigma": weakSignalSigma,
            "positionSpeedMaxAccuracy": positionSpeedMaxAccuracy,
            "positionSpeedMinInterval": positionSpeedInterval.lowerBound,
            "positionSpeedMaxInterval": positionSpeedInterval.upperBound,
            "stoppedVariance": GPSOnlyFilter.stoppedVariance,
            "jerkNoise": GPSOnlyFilter.jerkNoise,
            "initialAccelerationVariance": GPSOnlyFilter.initialAccelerationVariance,
            "maxAcceleration": GPSOnlyFilter.maxAcceleration,
            "fusionEnabled": configuration.fusionEnabled ? 1 : 0,
            "usesPositionSpeed": configuration.usesPositionSpeed ? 1 : 0,
        ]
    }

    let configuration: Configuration
    /// Kept across an in-run `reset()`; see `reset(keepingMotionClock:)`.
    private(set) var motionClock = MotionClock()
    private var filter: GPSOnlyFilter?
    /// Recent fixes with a good position, oldest first, for position-derived speed.
    private var positions: [SpeedSample] = []
    private var lastFixArrival: Date?
    /// The last accepted fix was stationary: the speed is exactly 0 and no gap can start (R18).
    private(set) var isStopped = false
    private(set) var gapStart: Date?

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: Output

    var gpsOnly: Estimate? {
        filter.map { Estimate(metersPerSecond: $0.speed, sigma: $0.variance.squareRoot()) }
    }

    /// Motion-fused estimate. Not built yet (specs/speed-accuracy plan, PR 2).
    var fused: Estimate? { nil }

    /// What the screen shows, and where it came from (R14).
    var shown: (estimate: Estimate, source: Source)? {
        gpsOnly.map { ($0, .gpsOnly) }
    }

    var inGap: Bool { gapStart != nil }

    var isWeakSignal: Bool {
        inGap || (shown?.estimate.sigma ?? 0) > Self.weakSignalSigma
    }

    // MARK: Input

    /// One fix from the location source. `arrival` is when it reached the app, on the app's clock.
    @discardableResult
    mutating func fix(_ sample: SpeedSample, arrival: Date) -> FixOutcome {
        defer { remember(sample) }
        if sample.isStationary {
            if filter == nil {
                filter = .stopped(at: sample.timestamp)
            } else {
                filter?.stop(at: sample.timestamp)
            }
            accept(arrival: arrival, stopped: true)
            return .accepted
        }
        guard let (speed, variance) = measurement(for: sample) else { return .ignored }
        if var updated = filter {
            guard updated.update(speed: speed, variance: variance, at: sample.timestamp) else { return .rejected }
            filter = updated
        } else {
            filter = GPSOnlyFilter(speed: speed, variance: variance, at: sample.timestamp)
        }
        accept(arrival: arrival, stopped: false)
        return .accepted
    }

    /// One batch of device motion, as it reached the app. Only aligns clocks for now; fusion uses it in PR 2.
    mutating func motion(_ batch: [MotionSample], arrival: Date) {
        guard let latest = batch.last else { return }
        motionClock.observe(timestamp: latest.timestamp, arrival: arrival)
    }

    /// iOS reported that location is unavailable (iOS 18+): a gap starts now (R17).
    mutating func unavailable(at time: Date) {
        guard filter != nil, !isStopped, gapStart == nil else { return }
        gapStart = time
    }

    /// Advances time with no new input. Starts a gap once fixes stop arriving (R17).
    mutating func tick(now: Date) {
        guard filter != nil, !isStopped, gapStart == nil, let lastFixArrival,
              now.timeIntervalSince(lastFixArrival) > Self.gapStartInterval else { return }
        gapStart = lastFixArrival.addingTimeInterval(Self.gapStartInterval)
    }

    /// Forgets every estimate, e.g. after Acquiring (R19).
    /// Keeps the motion clock by default: within one run the boot-time offset holds. Core Motion's clock pauses while
    /// the phone sleeps, so a new run must start a fresh one.
    mutating func reset(keepingMotionClock: Bool = true) {
        let motionClock = motionClock
        self = SpeedEstimator(configuration: configuration)
        if keepingMotionClock { self.motionClock = motionClock }
    }

    // MARK: Private

    private mutating func accept(arrival: Date, stopped: Bool) {
        lastFixArrival = arrival
        isStopped = stopped
        gapStart = nil
    }

    /// The fix's speed and its variance, or nil when it carries no usable speed.
    private func measurement(for sample: SpeedSample) -> (speed: Double, variance: Double)? {
        if sample.metersPerSecond >= 0, sample.accuracy >= 0 {
            let sigma = Self.speedAccuracyScale * max(sample.accuracy, Self.minimumSpeedAccuracy)
            return (sample.metersPerSecond, sigma * sigma)
        }
        guard configuration.usesPositionSpeed, sample.metersPerSecond < 0, Self.hasGoodPosition(sample) else { return nil }
        let earlier = positions.last { previous in
            Self.positionSpeedInterval.contains(sample.timestamp.timeIntervalSince(previous.timestamp))
        }
        guard let earlier else { return nil }
        let interval = sample.timestamp.timeIntervalSince(earlier.timestamp)
        let speed = Self.distance(from: earlier, to: sample) / interval
        let positionVariance = earlier.horizontalAccuracy * earlier.horizontalAccuracy
            + sample.horizontalAccuracy * sample.horizontalAccuracy
        return (speed, 2 * positionVariance / (interval * interval))
    }

    private mutating func remember(_ sample: SpeedSample) {
        guard Self.hasGoodPosition(sample) else { return }
        positions.removeAll { sample.timestamp.timeIntervalSince($0.timestamp) > Self.positionSpeedInterval.upperBound }
        positions.append(sample)
    }

    private static func hasGoodPosition(_ sample: SpeedSample) -> Bool {
        sample.horizontalAccuracy >= 0 && sample.horizontalAccuracy <= positionSpeedMaxAccuracy
    }

    /// Ground distance in metres. Equirectangular: exact enough over the few hundred metres used here.
    static func distance(from start: SpeedSample, to end: SpeedSample) -> Double {
        let earthRadius = 6_371_000.0
        let toRadians = Double.pi / 180
        let meanLatitude = (start.latitude + end.latitude) / 2 * toRadians
        let north = (end.latitude - start.latitude) * toRadians * earthRadius
        let east = (end.longitude - start.longitude) * toRadians * earthRadius * cos(meanLatitude)
        return (north * north + east * east).squareRoot()
    }
}
