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
        /// Allowed, with Precise Location off (specs/precise-location R4).
        case preciseOff
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
    /// The "Engine sounds" switch (specs/engine-clip-toggle R2).
    static let engineSoundsDefaultsKey = "engineSound.enabled"
    /// The current trip is saved at most this often while running (trip-stats R10).
    static let tripSaveInterval: TimeInterval = 10

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
    /// When the state last left "Precise Location off". A fix taken before it may be a cached rough one
    /// (specs/precise-location R6).
    @ObservationIgnored private var preciseOffEndedAt: Date?
    /// The trip line and sheet (specs/trip-stats), already formatted. Assigned only when a string changes.
    private(set) var trip: TripDisplay
    /// Internal, not private: `SpeedometerViewModel+Map.swift` reads it.
    @ObservationIgnored var tripTracker: TripTracker
    @ObservationIgnored private var lastTripSave: Date?
    /// When the trip was last fed; a longer pause than `TripTracker.maxInterval` breaks the route (osm-map R17).
    @ObservationIgnored var lastTripUpdate: Date?
    private let tripStore: TripStore
    private let tripFormatter: TripFormatter
    /// The driving stretch behind the break reminder (specs/break-reminder). Internal: `+Map.swift` clears it.
    @ObservationIgnored var breakTracker: BreakTracker
    /// Whole hours of drive time once a break is due, else nil. Assigned only when it changes (R8, R9).
    private(set) var breakReminderHours: Int?
    static let breakReminderSymbol = "cup.and.saucer"

    // MARK: Map (specs/osm-map; logic in SpeedometerViewModel+Map.swift)

    static let screenModeDefaultsKey = "screenMode"
    static let mapNoticeDefaultsKey = "map.noticeAccepted"

    /// Gauge or map; gauge until I choose the map (R1).
    var screenMode: ScreenMode
    /// The OpenStreetMap notice shows over the first map until "OK" (R2).
    var isMapNoticePending: Bool
    /// What the live map draws. Assigned only when it changes.
    var mapScene = MapScene()
    /// The latest tile request failed (R13).
    var isMapOffline = false
    /// A fix with a valid position has arrived since launch; until then the map is a placeholder (R9).
    var hasPosition = false
    @ObservationIgnored var lastPosition: MapCoordinate?
    @ObservationIgnored var routeRecorder: RouteRecorder
    /// The trip the recorder's route belongs to; nil while the trip is empty.
    @ObservationIgnored var routeTripID: UUID?
    /// The route last written, so an unchanged route isn't rewritten every 10 s.
    @ObservationIgnored var lastSavedRoute: (id: UUID, route: Route)?
    @ObservationIgnored var mapFollower = MapFollower()
    let routeStore: RouteStore
    let tileFetcher: TileFetcher

    /// Plays a sound on engine start while stopped (specs/engine-sound-clip). Shares this screen's lifecycle.
    let engineSound: EngineSoundViewModel
    /// The "Engine sounds" switch in the gauge style sheet; on unless turned off (specs/engine-clip-toggle R2).
    private(set) var engineSoundsOn: Bool
    /// The "Engine sounds" Focus filter (specs/engine-clip-toggle R15-R18); nil without one.
    let focusFilter: FocusFilterProvider?
    /// True while a Focus turns engine sounds off; nil until this run's first value arrives (R17). Internal, not
    /// private: set by SpeedometerViewModel+Focus.swift.
    var focusOverride: Bool? = false

    private let provider: SpeedProvider
    private let motionProvider: MotionProvider
    let defaults: UserDefaults
    private let locale: Locale
    let now: () -> Date
    private let setIdleTimerDisabled: @MainActor (Bool) -> Void
    private let makeRecorder: () -> DriveLogging?

    init(
        provider: SpeedProvider? = nil,
        motionProvider: MotionProvider? = nil,
        defaults: UserDefaults = .standard,
        locale: Locale = .current,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        setIdleTimerDisabled: @escaping @MainActor (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 },
        engineSound: EngineSoundViewModel? = nil,
        estimatorConfiguration: SpeedEstimator.Configuration = .launchDefault(),
        makeRecorder: @escaping () -> DriveLogging? = DriveLog.makeRecorder,
        routeStore: RouteStore = .standard,
        tileFetcher: TileFetcher? = nil,
        focusFilter: FocusFilterProvider? = AppIntentsFocusFilterProvider()
    ) {
        self.makeRecorder = makeRecorder
        self.provider = provider ?? CoreLocationSpeedProvider()
        self.motionProvider = motionProvider ?? CoreMotionProvider()
        self.estimator = SpeedEstimator(configuration: estimatorConfiguration)
        self.engineSound = engineSound ?? EngineSoundViewModel()
        self.engineSoundsOn = Self.engineSoundsSetting(from: defaults.object(forKey: Self.engineSoundsDefaultsKey))
        self.focusFilter = focusFilter
        self.defaults = defaults
        self.locale = locale
        self.now = now
        self.setIdleTimerDisabled = setIdleTimerDisabled
        let unit = defaults.string(forKey: Self.unitDefaultsKey).flatMap(SpeedUnit.init(rawValue:))
            ?? SpeedUnit.defaultUnit(for: locale)
        self.unit = unit
        let tripStore = TripStore(defaults: defaults)
        let tripTracker = tripStore.load()
        let tripFormatter = TripFormatter(locale: locale, calendar: calendar)
        self.tripStore = tripStore
        self.tripTracker = tripTracker
        self.tripFormatter = tripFormatter
        self.trip = tripFormatter.display(of: tripTracker, unit: unit, now: now(), showsLine: true)
        let breakTracker = BreakTracker(stretch: tripStore.loadStretch())
        self.breakTracker = breakTracker
        self.breakReminderHours = breakTracker.reminderHours
        let face = defaults.string(forKey: Self.faceDefaultsKey).flatMap(GaugeFace.init(rawValue:))
            ?? GaugeFace.defaultFace
        self.face = face
        self.routeStore = routeStore
        self.tileFetcher = tileFetcher ?? URLSessionTileFetcher()
        self.screenMode = defaults.string(forKey: Self.screenModeDefaultsKey).flatMap(ScreenMode.init(rawValue:)) ?? .gauge
        self.isMapNoticePending = !defaults.bool(forKey: Self.mapNoticeDefaultsKey)
        // A trip that continues after a relaunch keeps drawing onto its stored route (osm-map R19).
        self.routeTripID = tripTracker.current.id
        self.routeRecorder = RouteRecorder(route: tripTracker.current.id.flatMap(routeStore.load(id:)) ?? Route())
        self.mapScene = MapScene()
        // No sound once the vehicle moves (R6). Read live when a detection fires; no reading counts as stopped.
        self.engineSound.isMoving = { [weak self] in (self?.displayedSpeed ?? 0) > 0 }
        self.engineSound.handle(enabled: engineSoundsEffective)
    }

    /// Only a stored Bool counts; nothing, or anything else, means on (specs/engine-clip-toggle R2).
    nonisolated static func engineSoundsSetting(from stored: Any?) -> Bool {
        guard let number = stored as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return true }
        return number.boolValue
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

    var statusText: String? { chip?.text }

    var statusSymbol: String? { chip?.symbol }

    /// What VoiceOver reads for the chip when it differs from the text: the break reminder's hours spelled out
    /// (specs/break-reminder R15). Nil for every other chip.
    var statusAccessibilityLabel: String? { chip?.spoken }

    /// The one chip on screen: the first tier that applies (specs/precise-location R8). Location statuses, then
    /// the break reminder (specs/break-reminder R10), then the mic chip (engine-sound R11).
    private var chip: (text: String, symbol: String?, spoken: String?)? {
        if let text = locationStatusText { return (text, locationStatusSymbol, nil) }
        if let hours = breakReminderHours {
            return (tripFormatter.breakReminder(hours: hours), Self.breakReminderSymbol,
                    tripFormatter.breakReminderSpoken(hours: hours))
        }
        if let text = engineSound.chipText { return (text, engineSound.chipSymbol, nil) }
        return nil
    }

    private var locationStatusText: String? {
        switch state {
        case .acquiring: String(localized: "Searching for GPS…")
        case .live(let weakSignal): weakSignal ? String(localized: "Weak GPS signal") : nil
        case .unavailable(.denied), .unavailable(.restricted): String(localized: "Location access is off")
        case .unavailable(.servicesOff): String(localized: "Location Services is off")
        case .unavailable(.preciseOff): String(localized: "Precise Location is off")
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

    var canOpenSettings: Bool { openSettingsHint != nil }

    /// The line under "Open Settings", which shows only with it (specs/precise-location R5).
    var openSettingsHint: String? {
        switch state {
        case .unavailable(.denied): String(localized: "Enable Location in Settings to see your speed")
        case .unavailable(.preciseOff): String(localized: "Turn on Precise Location under Location to see your speed")
        default: nil
        }
    }

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
            // Nothing is measured while the screen isn't running (trip-stats R1, R10).
            tripTracker.endRun(at: now())
            breakTracker.endRun(at: now())
            routeRecorder.breakSegment()
            saveTrip()
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
        // After a long break this starts a new trip (trip-stats R6).
        tripTracker.beginRun(at: now())
        // After 30 min without movement the driving stretch was a rest (specs/break-reminder R5).
        breakTracker.beginRun(at: now())
        refreshBreakReminder()
        // Each run starts a new route segment (osm-map R17).
        routeRecorder.breakSegment()
        saveTrip()
        refreshTrip()
        refreshMapScene()
        beginFocusRun()

        let authorizations = provider.authorizationUpdates()
        let samples = provider.speedUpdates()
        let motion = motionProvider.motionUpdates()
        let tileStatuses = await tileFetcher.statusUpdates()
        let tickInterval = Self.tickInterval
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await authorization in authorizations { await self.handle(authorization: authorization) }
            }
            group.addTask {
                for await update in samples {
                    switch update {
                    case .fix(let sample): await self.handle(sample: sample)
                    case .approximateFix(let sample): await self.handle(approximateFix: sample)
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
            group.addTask {
                await self.runFocusFilter()
            }
            group.addTask {
                for await status in tileStatuses { await self.handle(tileStatus: status) }
            }
        }
    }

    private func runEngineSound() async {
        await engineSound.runFollowingSwitch()
    }

    func handle(authorization: LocationAuthorization) {
        // Any way out of "Precise Location off", not only back to allowed: a later fix may still be a rough one
        // taken before (specs/precise-location R6).
        if state == .unavailable(.preciseOff), authorization != .authorizedApproximate { preciseOffEndedAt = now() }
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
        case .authorizedApproximate:
            becomeUnavailable(.preciseOff)
        case .denied:
            becomeUnavailable(.denied)
        case .restricted:
            becomeUnavailable(.restricted)
        case .servicesOff:
            becomeUnavailable(.servicesOff)
        }
        // The mic prompt waits until the location prompt is answered, so the two never stack (engine-sound R2).
        engineSound.handle(locationAuthorizationResolved: authorization != .notDetermined)
        refreshTrip()
        refreshMapScene()
    }

    func handle(sample: SpeedSample) {
        recorder?.record(.fix(sample, arrival: now()))
        if case .unavailable = state { return }
        if let preciseOffEndedAt, sample.timestamp < preciseOffEndedAt { return }
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
        updateWeakSignal()
        updateShownSpeed()
        updateTrip(liveTripReading)
        updateMap(with: sample)
        // Observed properties are assigned only on change, so a refresh never invalidates the view for nothing.
        let nextMood = moodResolver.sample(metersPerSecond: gpsOnly.metersPerSecond, timestamp: sample.timestamp, now: now())
        if nextMood != mood { mood = nextMood }
        recordShown()
    }

    /// A fix iOS sent while Precise Location was off: recorded, then dropped. It moves nothing, in any state
    /// (specs/precise-location R9, R11).
    func handle(approximateFix sample: SpeedSample) {
        recorder?.record(.fix(sample, arrival: now()))
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
        tickMap()
        guard case .live = state, let last = lastSample else {
            // Total time keeps counting with the trip sheet open, even without a reading (trip-stats R4, R15).
            refreshTrip()
            return
        }
        // Before the stationary guard: sleepy must start while iOS pauses updates. Assign only on change, so
        // the observed property does not invalidate the screen on every tick.
        let next = moodResolver.tick(at: now())
        if next != mood { mood = next }
        defer { recordShown() }
        if !last.isStationary, now().timeIntervalSince(last.timestamp) > Self.staleInterval {
            resetFilter()
            state = .acquiring
            mood = moodResolver.lost()
            updateTrip(.acquiring)
            refreshMapScene()
            return
        }
        estimator.tick(now: now())
        updateWeakSignal()
        updateTrip(liveTripReading)
        if lastTripSave.map({ now().timeIntervalSince($0) >= Self.tripSaveInterval }) ?? true { saveTrip() }
    }

    func toggleUnit() {
        unit = unit == .kmh ? .mph : .kmh
        defaults.set(unit.rawValue, forKey: Self.unitDefaultsKey)
        // A new unit is a new number, not a small move: no hysteresis (speed-accuracy R15).
        shownSpeed = nil
        updateShownSpeed()
        refreshTrip()
    }

    /// "New trip" in the trip sheet: the current trip goes to history (trip-stats R7).
    func startNewTrip() {
        // The finished trip keeps everything recorded up to now (osm-map R19).
        saveRoute()
        tripTracker.newTrip()
        saveTrip()
        refreshTrip()
        refreshMapScene()
    }

    /// The "Engine sounds" switch. Saved at once; touches nothing but engine sound (specs/engine-clip-toggle R2-R4).
    /// Turning it on may make a held mic request (R6, R16).
    func setEngineSounds(_ on: Bool) {
        engineSoundsOn = on
        defaults.set(on, forKey: Self.engineSoundsDefaultsKey)
        engineSound.handle(enabled: engineSoundsEffective)
        if on { engineSound.releaseMicPrompt() }
    }

    /// Switches the gauge face. Speed, unit, state and filter are untouched.
    func select(_ face: GaugeFace) {
        self.face = face
        defaults.set(face.rawValue, forKey: Self.faceDefaultsKey)
        refreshMapScene()
    }

    // MARK: - Private

    private func becomeUnavailable(_ reason: SpeedometerState.UnavailableReason) {
        resetFilter()
        state = .unavailable(reason)
        mood = moodResolver.unavailable()
        updateTrip(.notMeasured)
        refreshMapScene()
    }

    // MARK: Trip (specs/trip-stats)

    /// The estimate behind the shown number; 0 when stopped.
    private var liveTripReading: TripReading {
        .live(metersPerSecond: estimator.shown?.estimate.metersPerSecond ?? 0)
    }

    private func updateTrip(_ reading: TripReading) {
        // The route breaks wherever the trip's measuring chain does (osm-map R17).
        let isLive = if case .live = reading { true } else { false }
        if !isLive || lastTripUpdate.map({ now().timeIntervalSince($0) > TripTracker.maxInterval }) == true {
            routeRecorder.breakSegment()
        }
        lastTripUpdate = now()
        tripTracker.update(at: now(), reading: reading)
        // The same readings, at the same moments, as the trip (specs/break-reminder R1).
        breakTracker.update(at: now(), reading: reading)
        refreshTrip()
        refreshBreakReminder()
    }

    /// Internal for `SpeedometerViewModel+Map.swift`. Assigned only on change, so ticks never invalidate the view.
    func refreshBreakReminder() {
        let next = breakTracker.reminderHours
        if next != breakReminderHours { breakReminderHours = next }
    }

    /// The line is hidden while location is off (trip-stats R11). Internal for `SpeedometerViewModel+Map.swift`.
    func refreshTrip() {
        var showsLine = true
        if case .unavailable = state { showsLine = false }
        let next = tripFormatter.display(of: tripTracker, unit: unit, now: now(), showsLine: showsLine)
        if next != trip { trip = next }
    }

    /// Internal for `SpeedometerViewModel+Map.swift`. The route is saved with the trip (osm-map R20).
    func saveTrip() {
        tripStore.save(tripTracker)
        // Saved with the trip, at the same moments (specs/break-reminder R14).
        tripStore.save(breakTracker.stretch)
        saveRoute()
        lastTripSave = now()
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
