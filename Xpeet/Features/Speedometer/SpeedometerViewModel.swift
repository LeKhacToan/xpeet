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
}

@Observable
@MainActor
final class SpeedometerViewModel {
    static let smoothingFactor = 0.6
    static let staleInterval: TimeInterval = 5
    static let zeroClampMetersPerSecond = 1 / 3.6
    static let weakAccuracyMetersPerSecond = 2.0
    static let unitDefaultsKey = "speedUnit"
    static let faceDefaultsKey = "gaugeFace"

    private(set) var state: SpeedometerState = .acquiring
    private(set) var unit: SpeedUnit
    private(set) var face: GaugeFace
    /// The mascot's expression. Follows the same filtered speed as the number.
    private(set) var mood: Mood = .searching
    private var moodResolver = MoodResolver()
    private var smoothedMetersPerSecond: Double?
    private var lastSample: SpeedSample?

    private let provider: SpeedProvider
    private let defaults: UserDefaults
    private let locale: Locale
    private let now: () -> Date
    private let setIdleTimerDisabled: @MainActor (Bool) -> Void

    init(
        provider: SpeedProvider? = nil,
        defaults: UserDefaults = .standard,
        locale: Locale = .current,
        now: @escaping () -> Date = Date.init,
        setIdleTimerDisabled: @escaping @MainActor (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 }
    ) {
        self.provider = provider ?? CoreLocationSpeedProvider()
        self.defaults = defaults
        self.locale = locale
        self.now = now
        self.setIdleTimerDisabled = setIdleTimerDisabled
        self.unit = defaults.string(forKey: Self.unitDefaultsKey).flatMap(SpeedUnit.init(rawValue:))
            ?? SpeedUnit.defaultUnit(for: locale)
        self.face = defaults.string(forKey: Self.faceDefaultsKey).flatMap(GaugeFace.init(rawValue:))
            ?? GaugeFace.defaultFace
    }

    // MARK: - Output

    /// Speed in the selected unit, or nil when there is no live reading.
    var displayedSpeed: Int? {
        guard case .live = state, let metersPerSecond = smoothedMetersPerSecond else { return nil }
        guard metersPerSecond >= Self.zeroClampMetersPerSecond else { return 0 }
        let value = Measurement(value: metersPerSecond, unit: UnitSpeed.metersPerSecond).converted(to: unit.unitSpeed).value
        return max(0, Int(value.rounded()))
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

    var statusText: String? {
        switch state {
        case .acquiring: String(localized: "Searching for GPS…")
        case .live(let weakSignal): weakSignal ? String(localized: "Weak GPS signal") : nil
        case .unavailable(.denied), .unavailable(.restricted): String(localized: "Location access is off")
        case .unavailable(.servicesOff): String(localized: "Location Services is off")
        }
    }

    /// SF Symbol shown next to `statusText`.
    var statusSymbol: String? {
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
        defer { setIdleTimerDisabled(false) }
        resetFilter()
        if case .live = state { state = .acquiring }
        mood = moodResolver.lost()

        let authorizations = provider.authorizationUpdates()
        let samples = provider.speedUpdates()
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await authorization in authorizations { await self.handle(authorization: authorization) }
            }
            group.addTask {
                for await sample in samples { await self.handle(sample: sample) }
            }
            group.addTask {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    await self.tick()
                }
            }
        }
    }

    func handle(authorization: LocationAuthorization) {
        switch authorization {
        case .notDetermined:
            state = .acquiring
            provider.requestAuthorization()
        case .authorized:
            if case .unavailable = state { state = .acquiring }
        case .denied:
            becomeUnavailable(.denied)
        case .restricted:
            becomeUnavailable(.restricted)
        case .servicesOff:
            becomeUnavailable(.servicesOff)
        }
    }

    func handle(sample: SpeedSample) {
        guard sample.metersPerSecond >= 0, sample.accuracy >= 0 else { return }
        if case .unavailable = state { return }
        // The first update is often a cached fix. A moving fix that old is not the current speed; a stationary
        // one still is, because iOS reports stationary with the last known location while updates are paused.
        if !sample.isStationary, now().timeIntervalSince(sample.timestamp) > Self.staleInterval { return }

        if let last = lastSample, sample.timestamp.timeIntervalSince(last.timestamp) > Self.staleInterval {
            resetFilter()
        }
        if sample.isStationary {
            smoothedMetersPerSecond = 0
        } else if let previous = smoothedMetersPerSecond {
            smoothedMetersPerSecond = previous + Self.smoothingFactor * (sample.metersPerSecond - previous)
        } else {
            smoothedMetersPerSecond = sample.metersPerSecond
        }
        lastSample = sample
        state = .live(weakSignal: sample.accuracy > Self.weakAccuracyMetersPerSecond)
        mood = moodResolver.sample(metersPerSecond: smoothedMetersPerSecond ?? 0, timestamp: sample.timestamp, now: now())
    }

    /// Falls back to Acquiring when the last fix is too old. iOS pauses updates while stationary, so a
    /// stationary fix never goes stale.
    func tick() {
        guard case .live = state, let last = lastSample else { return }
        // Before the stationary guard: sleepy must start while iOS pauses updates. Assign only on change, so
        // the observed property does not invalidate the screen every second.
        let next = moodResolver.tick(at: now())
        if next != mood { mood = next }
        if !last.isStationary, now().timeIntervalSince(last.timestamp) > Self.staleInterval {
            resetFilter()
            state = .acquiring
            mood = moodResolver.lost()
        }
    }

    func toggleUnit() {
        unit = unit == .kmh ? .mph : .kmh
        defaults.set(unit.rawValue, forKey: Self.unitDefaultsKey)
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
        mood = moodResolver.lost()
    }

    private func resetFilter() {
        smoothedMetersPerSecond = nil
        lastSample = nil
    }
}
