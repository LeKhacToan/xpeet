import Foundation
import Observation
import UIKit

enum SpeedUnit: String {
    case kmh
    case mph

    var unitSpeed: UnitSpeed {
        switch self {
        case .kmh: .kilometersPerHour
        case .mph: .milesPerHour
        }
    }

    var symbol: String {
        switch self {
        case .kmh: "km/h"
        case .mph: "mph"
        }
    }

    /// Exact factors (1 km/h = 1/3.6 m/s, 1 mph = 0.44704 m/s). Foundation's own converter rounds its coefficient,
    /// which moves values off hysteresis boundaries.
    func value(fromMetersPerSecond metersPerSecond: Double) -> Double {
        switch self {
        case .kmh: metersPerSecond * 3.6
        case .mph: metersPerSecond / 0.44704
        }
    }

    /// Speed at which the gauge arc is full.
    var gaugeMaximum: Int {
        switch self {
        case .kmh: 200
        case .mph: 130
        }
    }

    /// How full the gauge is for a displayed speed, 0...1.
    func gaugeFraction(for speed: Int) -> Double {
        min(1, Double(speed) / Double(gaugeMaximum))
    }

    var spokenName: String {
        switch self {
        case .kmh: String(localized: "kilometers per hour")
        case .mph: String(localized: "miles per hour")
        }
    }

    /// Road speeds are in mph in the US and UK, km/h elsewhere.
    static func defaultUnit(for locale: Locale) -> SpeedUnit {
        switch locale.measurementSystem {
        case .us, .uk: .mph
        default: .kmh
        }
    }
}

enum SpeedometerState: Equatable {
    enum UnavailableReason: Equatable {
        case denied
        case restricted
        case servicesOff
    }

    case acquiring
    case live(weakSignal: Bool)
    case unavailable(UnavailableReason)

    /// The state as written in a recorded drive's `shown` lines.
    var recordedName: String {
        switch self {
        case .acquiring: "acquiring"
        case .live(let weakSignal): weakSignal ? "liveWeak" : "live"
        case .unavailable: "unavailable"
        }
    }
}

@Observable
@MainActor
final class SpeedometerViewModel {
    /// A moving fix this old is stale: on arrival it is ignored; once the last fix is this old the state is Acquiring.
    static let staleInterval: TimeInterval = 5
    static let zeroClampMetersPerSecond = 1 / 3.6
    /// The shown number changes only once the estimate is this far from it, in the selected unit (speed-accuracy R15).
    static let displayHysteresis = 0.6
    /// Often enough to start a 1.5 s gap on time (speed-accuracy R17).
    static let tickInterval: Duration = .milliseconds(500)
    static let unitDefaultsKey = "speedUnit"
    static let faceDefaultsKey = "gaugeFace"

    private(set) var state: SpeedometerState = .acquiring
    private(set) var unit: SpeedUnit
    private(set) var face: GaugeFace
    /// The mascot's expression. Fed once per fix with the GPS-only estimate (speed-accuracy R21).
    private(set) var mood: Mood = .searching
    private var moodResolver = MoodResolver()
    /// Updated on every input, so it must not invalidate the view; only `shownSpeed` and `state` are observed.
    @ObservationIgnored private(set) var estimator: SpeedEstimator
    /// The whole-unit number on screen while Live. Changes only when the rounded value moves.
    private var shownSpeed: Int?
    private var lastSample: SpeedSample?
    /// The current run's drive recorder (Debug, opt-in), with a token so an ending run can't clear a newer one.
    @ObservationIgnored private var recorder: DriveLogging?
    @ObservationIgnored private var recorderRun: UUID?

    /// Plays a sound on engine start while stopped (specs/engine-sound-clip). Shares this screen's lifecycle.
    let engineSound: EngineSoundViewModel

    private let provider: SpeedProvider
    private let motionProvider: MotionProvider
    private let defaults: UserDefaults
    private let locale: Locale
    private let now: () -> Date
    private let setIdleTimerDisabled: @MainActor (Bool) -> Void
    private let makeRecorder: () -> DriveLogging?

    init(
        provider: SpeedProvider? = nil,
        motionProvider: MotionProvider? = nil,
        defaults: UserDefaults = .standard,
        locale: Locale = .current,
        now: @escaping () -> Date = Date.init,
        setIdleTimerDisabled: @escaping @MainActor (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 },
        engineSound: EngineSoundViewModel? = nil,
        estimatorConfiguration: SpeedEstimator.Configuration = .launchDefault(),
        makeRecorder: @escaping () -> DriveLogging? = DriveLog.makeRecorder
    ) {
        self.makeRecorder = makeRecorder
        self.provider = provider ?? CoreLocationSpeedProvider()
        self.motionProvider = motionProvider ?? CoreMotionProvider()
        self.estimator = SpeedEstimator(configuration: estimatorConfiguration)
        self.engineSound = engineSound ?? EngineSoundViewModel()
        self.defaults = defaults
        self.locale = locale
        self.now = now
        self.setIdleTimerDisabled = setIdleTimerDisabled
        self.unit = defaults.string(forKey: Self.unitDefaultsKey).flatMap(SpeedUnit.init(rawValue:))
            ?? SpeedUnit.defaultUnit(for: locale)
        self.face = defaults.string(forKey: Self.faceDefaultsKey).flatMap(GaugeFace.init(rawValue:))
            ?? GaugeFace.defaultFace
        // No sound once the vehicle moves (R6). Read live when a detection fires; no reading counts as stopped.
        self.engineSound.isMoving = { [weak self] in (self?.displayedSpeed ?? 0) > 0 }
    }

    // MARK: - Output

    /// Speed in the selected unit, or nil when there is no live reading.
    var displayedSpeed: Int? {
        guard case .live = state else { return nil }
        return shownSpeed
    }

    var displayText: String {
        displayedSpeed.map(String.init) ?? "--"
    }

    var unitText: String { unit.symbol }

    /// How full the gauge arc is, 0...1. Uses the displayed (rounded) speed so the arc matches the number.
    var gaugeFraction: Double {
        guard let speed = displayedSpeed else { return 0 }
        return unit.gaugeFraction(for: speed)
    }

    /// Location status first; the mic-off hint only when there is none (engine-sound R11).
    var statusText: String? {
        locationStatusText ?? engineSound.chipText
    }

    var statusSymbol: String? {
        locationStatusText != nil ? locationStatusSymbol : engineSound.chipSymbol
    }

    private var locationStatusText: String? {
        switch state {
        case .acquiring: String(localized: "Searching for GPS…")
        case .live(let weakSignal): weakSignal ? String(localized: "Weak GPS signal") : nil
        case .unavailable(.denied), .unavailable(.restricted): String(localized: "Location access is off")
        case .unavailable(.servicesOff): String(localized: "Location Services is off")
        }
    }

    /// SF Symbol shown next to the location status.
    private var locationStatusSymbol: String? {
        switch state {
        case .acquiring: "location.magnifyingglass"
        case .live(let weakSignal): weakSignal ? "exclamationmark.triangle" : nil
        case .unavailable: "location.slash"
        }
    }

    var canOpenSettings: Bool { state == .unavailable(.denied) }

    var accessibilityLabel: String {
        guard let speed = displayedSpeed else { return String(localized: "No GPS signal") }
        return Measurement(value: Double(speed), unit: unit.unitSpeed)
            .formatted(.measurement(width: .wide, usage: .asProvided).locale(locale))
    }

    var unitAccessibilityValue: String { unit.spokenName }

    // MARK: - Input

    /// Streams provider updates into the handlers until cancelled. Keeps the screen awake meanwhile.
    func run() async {
        setIdleTimerDisabled(true)
        let run = startRecording()
        defer {
            setIdleTimerDisabled(false)
            stopRecording(run)
        }
        resetFilter()
        // Core Motion's clock pauses while the phone sleeps, so the offset from the last run may be wrong now.
        estimator.reset(keepingMotionClock: false)
        if case .live = state { state = .acquiring }
        if case .unavailable = state {
            mood = moodResolver.unavailable()
        } else {
            mood = moodResolver.lost()
        }

        let authorizations = provider.authorizationUpdates()
        let samples = provider.speedUpdates()
        let motion = motionProvider.motionUpdates()
        let tickInterval = Self.tickInterval
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await authorization in authorizations { await self.handle(authorization: authorization) }
            }
            group.addTask {
                for await update in samples {
                    switch update {
                    case .fix(let sample): await self.handle(sample: sample)
                    case .unavailable: await self.handleLocationUnavailable()
                    }
                }
            }
            group.addTask {
                // Ends at once without motion sensors (e.g. Simulator); the reading stays GPS-only.
                for await batch in motion { await self.handle(motion: batch) }
            }
            group.addTask {
                while !Task.isCancelled {
                    try? await Task.sleep(for: tickInterval)
                    await self.tick()
                }
            }
            group.addTask {
                await self.runEngineSound()
            }
        }
    }

    private func runEngineSound() async {
        await engineSound.run()
    }

    func handle(authorization: LocationAuthorization) {
        switch authorization {
        case .notDetermined:
            if case .unavailable = state { mood = moodResolver.lost() }
            state = .acquiring
            provider.requestAuthorization()
        case .authorized:
            if case .unavailable = state {
                state = .acquiring
                mood = moodResolver.lost()
            }
        case .denied:
            becomeUnavailable(.denied)
        case .restricted:
            becomeUnavailable(.restricted)
        case .servicesOff:
            becomeUnavailable(.servicesOff)
        }
        // The mic prompt waits until the location prompt is answered, so the two never stack (engine-sound R2).
        engineSound.handle(locationAuthorizationResolved: authorization != .notDetermined)
    }

    func handle(sample: SpeedSample) {
        recorder?.record(.fix(sample, arrival: now()))
        if case .unavailable = state { return }
        // The first update is often a cached fix. A moving fix that old is not the current speed; a stationary
        // one still is, because iOS reports stationary with the last known location while updates are paused.
        if !sample.isStationary, now().timeIntervalSince(sample.timestamp) > Self.staleInterval { return }

        // After a long silence start again from this fix (speed-accuracy R19), but only if it is usable.
        var next = estimator
        let resumed = lastSample.map { sample.timestamp.timeIntervalSince($0.timestamp) > Self.staleInterval } ?? false
        if resumed { next.reset() }
        let outcome = next.fix(sample, arrival: now())
        // An unused fix still leaves its position behind for position-derived speed (R13); only a reset that
        // found nothing usable is thrown away, so the old reading runs out on its own clock.
        if outcome == .accepted || !resumed { estimator = next }
        guard outcome == .accepted, let gpsOnly = estimator.gpsOnly else { return }
        if resumed { shownSpeed = nil }
        lastSample = sample
        state = .live(weakSignal: estimator.isWeakSignal)
        updateShownSpeed()
        mood = moodResolver.sample(metersPerSecond: gpsOnly.metersPerSecond, timestamp: sample.timestamp, now: now())
        recordShown()
    }

    /// One batch of device motion (speed-accuracy R2). Fusion is not built yet, so nothing on screen changes.
    func handle(motion batch: [MotionSample]) {
        let arrival = now()
        if let recorder {
            batch.forEach { recorder.record(.motion($0, arrival: arrival)) }
        }
        estimator.motion(batch, arrival: arrival)
    }

    /// iOS 18+ reported that location is unavailable: keep the reading, flagged as weak signal (speed-accuracy R18).
    func handleLocationUnavailable() {
        recorder?.record(.unavailable(arrival: now()))
        guard case .live = state else { return }
        estimator.unavailable(at: now())
        updateWeakSignal()
        recordShown()
    }

    /// Falls back to Acquiring when the last fix is too old. iOS pauses updates while stationary, so a
    /// stationary fix never goes stale.
    func tick() {
        guard case .live = state, let last = lastSample else { return }
        // Before the stationary guard: sleepy must start while iOS pauses updates. Assign only on change, so
        // the observed property does not invalidate the screen on every tick.
        let next = moodResolver.tick(at: now())
        if next != mood { mood = next }
        defer { recordShown() }
        if !last.isStationary, now().timeIntervalSince(last.timestamp) > Self.staleInterval {
            resetFilter()
            state = .acquiring
            mood = moodResolver.lost()
            return
        }
        estimator.tick(now: now())
        updateWeakSignal()
    }

    func toggleUnit() {
        unit = unit == .kmh ? .mph : .kmh
        defaults.set(unit.rawValue, forKey: Self.unitDefaultsKey)
        // A new unit is a new number, not a small move: no hysteresis (speed-accuracy R15).
        shownSpeed = nil
        updateShownSpeed()
    }

    /// Switches the gauge face. Speed, unit, state and filter are untouched.
    func select(_ face: GaugeFace) {
        self.face = face
        defaults.set(face.rawValue, forKey: Self.faceDefaultsKey)
    }

    // MARK: - Private

    private func becomeUnavailable(_ reason: SpeedometerState.UnavailableReason) {
        resetFilter()
        state = .unavailable(reason)
        mood = moodResolver.unavailable()
    }

    private func resetFilter() {
        estimator.reset()
        shownSpeed = nil
        lastSample = nil
    }

    /// Starts this run's recording, if recording is on (speed-accuracy R22). Returns the run's token.
    private func startRecording() -> UUID {
        let run = UUID()
        recorder?.finish()
        recorder = makeRecorder()
        recorderRun = run
        recorder?.record(.header(.current(startedAt: now(), constants: recordedConstants)))
        return run
    }

    /// Every constant behind what is shown, for the recording's header (R22).
    private var recordedConstants: [String: Double] {
        SpeedEstimator.recordedConstants(estimator.configuration).merging([
            "staleInterval": Self.staleInterval,
            "zeroClampMetersPerSecond": Self.zeroClampMetersPerSecond,
            "displayHysteresis": Self.displayHysteresis,
            "tickInterval": Double(Self.tickInterval.components.seconds)
                + Double(Self.tickInterval.components.attoseconds) / 1e18,
            "motionSampleRate": CoreMotionProvider.sampleRate,
            "motionBatchSize": Double(CoreMotionProvider.batchSize),
        ]) { current, _ in current }
    }

    private func stopRecording(_ run: UUID) {
        guard recorderRun == run else { return }
        recorder?.finish()
        recorder = nil
        recorderRun = nil
    }

    private func recordShown() {
        guard let recorder else { return }
        let shown = estimator.shown
        recorder.record(.shown(DriveShown(
            time: now(),
            displayed: displayedSpeed,
            unit: unit.rawValue,
            state: state.recordedName,
            source: shown?.source,
            gpsOnly: estimator.gpsOnly,
            fused: estimator.fused,
            inGap: estimator.inGap
        )))
    }

    private func updateWeakSignal() {
        let next = SpeedometerState.live(weakSignal: estimator.isWeakSignal)
        if next != state { state = next }
    }

    private func updateShownSpeed() {
        guard let shown = estimator.shown else { return }
        let next = Self.displayValue(for: shown.estimate.metersPerSecond, in: unit, holding: shownSpeed)
        if next != shownSpeed { shownSpeed = next }
    }

    /// The estimate in whole units. A shown number holds until the estimate moves more than `displayHysteresis`
    /// away from it, so it does not flicker between two values (speed-accuracy R15).
    static func displayValue(for metersPerSecond: Double, in unit: SpeedUnit, holding previous: Int?) -> Int {
        guard metersPerSecond >= Self.zeroClampMetersPerSecond else { return 0 }
        let value = unit.value(fromMetersPerSecond: metersPerSecond)
        // The tolerance absorbs rounding in the conversion, so an estimate exactly 0.6 away still holds.
        if let previous, abs(value - Double(previous)) <= Self.displayHysteresis + 1e-9 { return previous }
        return max(0, Int(value.rounded()))
    }
}
