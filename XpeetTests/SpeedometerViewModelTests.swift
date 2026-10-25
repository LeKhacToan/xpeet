import XCTest
@testable import Xpeet

@MainActor
final class SpeedometerViewModelTests: XCTestCase {
    private final class TestClock {
        var now = Date(timeIntervalSince1970: 1_000)
        func advance(by seconds: TimeInterval) { now += seconds }
    }

    private final class IdleTimerRecorder {
        var calls: [Bool] = []
    }

    private let metric = Locale(identifier: "fr_FR")
    private let unitedStates = Locale(identifier: "en_US")

    private func makeDefaults() -> UserDefaults {
        let name = "SpeedometerViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeViewModel(
        provider: FakeSpeedProvider? = nil,
        defaults: UserDefaults? = nil,
        locale: Locale? = nil,
        clock: TestClock = TestClock(),
        idleTimer: IdleTimerRecorder = IdleTimerRecorder(),
        detector: FakeSoundTriggerDetector? = nil,
        motion: FakeMotionProvider? = nil
    ) -> SpeedometerViewModel {
        // Always fakes: tests never touch the real microphone or motion sensors.
        SpeedometerViewModel(
            provider: provider ?? FakeSpeedProvider(),
            motionProvider: motion ?? FakeMotionProvider(),
            defaults: defaults ?? makeDefaults(),
            locale: locale ?? metric,
            now: { clock.now },
            setIdleTimerDisabled: { idleTimer.calls.append($0) },
            engineSound: EngineSoundViewModel(
                detector: detector ?? FakeSoundTriggerDetector(),
                player: FakeSoundPlayer(),
                now: { clock.now }
            )
        )
    }

    private func sample(
        kmh: Double,
        accuracy: Double = 0.5,
        stationary: Bool = false,
        at clock: TestClock
    ) -> SpeedSample {
        SpeedSample(metersPerSecond: kmh / 3.6, accuracy: accuracy, isStationary: stationary, timestamp: clock.now)
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for condition", file: file, line: line)
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - R4

    func testRunFeedsSamplesFromProvider() async {
        let provider = FakeSpeedProvider()
        let clock = TestClock()
        let viewModel = makeViewModel(provider: provider, clock: clock)

        let task = Task { await viewModel.run() }
        await waitUntil { provider.speedSubscriberCount > 0 }
        provider.send(sample(kmh: 72, at: clock))
        await waitUntil { viewModel.displayText == "72" }

        task.cancel()
        await task.value
    }

    func testRunRestartsInAcquiringAfterLive() async {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 50, at: clock))

        let task = Task { await viewModel.run() }
        await waitUntil { viewModel.state == .acquiring }
        XCTAssertEqual(viewModel.statusText, "Searching for GPS…")

        task.cancel()
        await task.value
    }

    // MARK: - speed-accuracy R2

    func testRunFeedsMotionBatchesToEstimator() async {
        let motion = FakeMotionProvider()
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock, motion: motion)

        let task = Task { await viewModel.run() }
        await waitUntil { motion.subscriberCount > 0 }
        let sample = MotionSample(timestamp: 42, userAcceleration: .zero, gravity: Vector3(x: 0, y: 0, z: -1), rotationRate: .zero)
        motion.send([sample])
        await waitUntil { viewModel.estimator.motionClock.offset != nil }

        XCTAssertEqual(viewModel.estimator.motionClock.date(for: 42), clock.now)
        task.cancel()
        await task.value
        await waitUntil { motion.subscriberCount == 0 }
    }

    func testFinishedMotionStreamKeepsGPSOnly() async {
        let provider = FakeSpeedProvider()
        let clock = TestClock()
        let viewModel = makeViewModel(provider: provider, clock: clock, motion: FakeMotionProvider(isAvailable: false))

        let task = Task { await viewModel.run() }
        await waitUntil { provider.speedSubscriberCount > 0 }
        provider.send(sample(kmh: 72, at: clock))
        await waitUntil { viewModel.displayText == "72" }

        XCTAssertEqual(viewModel.estimator.shown?.source, .gpsOnly)
        task.cancel()
        await task.value
    }

    // MARK: - R5

    func testNegativeSpeedIsIgnored() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 50, at: clock))

        viewModel.handle(sample: SpeedSample(metersPerSecond: -1, accuracy: 0.5, isStationary: false, timestamp: clock.now))

        XCTAssertEqual(viewModel.displayText, "50")
    }

    func testNegativeAccuracyIsIgnored() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 50, at: clock))

        viewModel.handle(sample: sample(kmh: 90, accuracy: -1, at: clock))

        XCTAssertEqual(viewModel.displayText, "50")
    }

    // MARK: - R6

    func testShowsDashesBeforeFirstFix() {
        let viewModel = makeViewModel()
        viewModel.handle(authorization: .authorized)

        XCTAssertEqual(viewModel.state, .acquiring)
        XCTAssertEqual(viewModel.displayText, "--")
        XCTAssertEqual(viewModel.statusText, "Searching for GPS…")
    }

    func testBecomesAcquiringWhenFixOlderThanFiveSeconds() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 40, at: clock))

        clock.advance(by: 5)
        viewModel.tick()
        XCTAssertEqual(viewModel.displayText, "40")

        clock.advance(by: 1)
        viewModel.tick()
        XCTAssertEqual(viewModel.state, .acquiring)
        XCTAssertEqual(viewModel.displayText, "--")
    }

    func testStaysAtZeroWhenStationaryUpdatesPause() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 0, stationary: true, at: clock))

        clock.advance(by: 60)
        viewModel.tick()

        XCTAssertEqual(viewModel.displayText, "0")
    }

    func testIgnoresMovingSampleOlderThanFiveSecondsOnArrival() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)

        viewModel.handle(sample: SpeedSample(
            metersPerSecond: 87 / 3.6, accuracy: 0.5, isStationary: false, timestamp: clock.now - 6
        ))

        XCTAssertEqual(viewModel.state, .acquiring)
        XCTAssertEqual(viewModel.displayText, "--")
    }

    func testShowsZeroForOldStationarySample() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)

        viewModel.handle(sample: SpeedSample(metersPerSecond: 0, accuracy: 0.5, isStationary: true, timestamp: clock.now - 600))

        XCTAssertEqual(viewModel.displayText, "0")
    }

    // MARK: - R7

    func testStationaryShowsZero() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 30, at: clock))

        viewModel.handle(sample: sample(kmh: 2, stationary: true, at: clock))

        XCTAssertEqual(viewModel.displayText, "0")
    }

    func testSpeedBelowOneKmhShowsZero() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)

        viewModel.handle(sample: sample(kmh: 0.9, at: clock))

        XCTAssertEqual(viewModel.displayText, "0")
    }

    // MARK: - R8

    func testDisplayRoundsToWholeUnit() {
        let clock = TestClock()
        let down = makeViewModel(clock: clock)
        down.handle(authorization: .authorized)
        down.handle(sample: sample(kmh: 54.4, at: clock))
        XCTAssertEqual(down.displayText, "54")

        let up = makeViewModel(clock: clock)
        up.handle(authorization: .authorized)
        up.handle(sample: sample(kmh: 54.6, at: clock))
        XCTAssertEqual(up.displayText, "55")
    }

    func testDisplayIsNeverNegative() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)

        viewModel.handle(sample: sample(kmh: 0, at: clock))

        XCTAssertEqual(viewModel.displayedSpeed, 0)
    }

    // MARK: - speed-accuracy R5, R15, R19

    func testFollowsHardBrakingWithinOneFix() throws {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        for _ in 1...3 {
            viewModel.handle(sample: sample(kmh: 80, at: clock))
            clock.advance(by: 1)
        }

        // Braking at 0.8 g (28 km/h per second): each fix is matched within 3 km/h when it arrives.
        for kmh in [52.0, 24] {
            viewModel.handle(sample: sample(kmh: kmh, at: clock))
            XCTAssertLessThanOrEqual(abs(try XCTUnwrap(viewModel.displayedSpeed) - Int(kmh)), 3)
            clock.advance(by: 1)
        }
    }

    func testFollowsAccelerationWithinOneFix() throws {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 0, at: clock))

        for kmh in [12.0, 24, 36, 48] {
            clock.advance(by: 1)
            viewModel.handle(sample: sample(kmh: kmh, at: clock))
            XCTAssertLessThanOrEqual(abs(try XCTUnwrap(viewModel.displayedSpeed) - Int(kmh)), 3)
        }
    }

    func testHysteresisHoldsNumber() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 60, at: clock))

        // Same accuracy, same instant: the estimate is the average, 60.55. Plain rounding would show 61.
        viewModel.handle(sample: sample(kmh: 61.1, at: clock))
        XCTAssertEqual(viewModel.displayText, "60")

        // Weights 2:1 toward the estimate: 60.55 + (62 - 60.55) / 3 ≈ 61.03, more than 0.6 away.
        viewModel.handle(sample: sample(kmh: 62, at: clock))
        XCTAssertEqual(viewModel.displayText, "61")
    }

    func testUnitToggleRecomputesWithoutHysteresis() {
        let clock = TestClock()
        let viewModel = makeViewModel(locale: metric, clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 60, at: clock))
        viewModel.handle(sample: sample(kmh: 61.1, at: clock))
        XCTAssertEqual(viewModel.displayText, "60", "held at an estimate of 60.55")

        viewModel.toggleUnit()
        viewModel.toggleUnit()

        XCTAssertEqual(viewModel.displayText, "61", "60.55 rounded afresh")
    }

    func testFilterResetsAfterAcquiring() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 100, at: clock))

        clock.advance(by: 6)
        viewModel.tick()
        viewModel.handle(sample: sample(kmh: 20, at: clock))

        XCTAssertEqual(viewModel.displayText, "20")
    }

    func testFilterResetsWhenSampleArrivesAfterGap() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 100, at: clock))

        clock.advance(by: 6)
        viewModel.handle(sample: sample(kmh: 20, at: clock))

        XCTAssertEqual(viewModel.displayText, "20")
    }

    // MARK: - R13, R14, R15

    func testDefaultUnitIsMphForUSAndUK() {
        XCTAssertEqual(makeViewModel(locale: unitedStates).unit, .mph)
        XCTAssertEqual(makeViewModel(locale: Locale(identifier: "en_GB")).unit, .mph)
    }

    func testDefaultUnitIsKmhForMetric() {
        let viewModel = makeViewModel(locale: metric)

        XCTAssertEqual(viewModel.unit, .kmh)
        XCTAssertEqual(viewModel.unitText, "km/h")
    }

    func testToggleUnitConvertsWithoutResettingFilter() {
        let clock = TestClock()
        let viewModel = makeViewModel(locale: metric, clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 100, at: clock))

        viewModel.toggleUnit()
        XCTAssertEqual(viewModel.unit, .mph)
        XCTAssertEqual(viewModel.unitText, "mph")
        XCTAssertEqual(viewModel.displayText, "62") // 100 km/h = 62.1 mph

        // Filter keeps its history: equal weights at one instant give 95 km/h = 59.0 mph (a reset would show 56).
        viewModel.handle(sample: sample(kmh: 90, at: clock))
        XCTAssertEqual(viewModel.displayText, "59")
    }

    func testUnitPersistsAcrossInstances() {
        let defaults = makeDefaults()
        makeViewModel(defaults: defaults, locale: metric).toggleUnit()

        XCTAssertEqual(makeViewModel(defaults: defaults, locale: metric).unit, .mph)
    }

    func testSavedUnitOverridesLocale() {
        let defaults = makeDefaults()
        defaults.set("kmh", forKey: SpeedometerViewModel.unitDefaultsKey)

        XCTAssertEqual(makeViewModel(defaults: defaults, locale: unitedStates).unit, .kmh)
    }

    // MARK: - R16, R17, R18

    func testRequestsAuthorizationWhenNotDetermined() {
        let provider = FakeSpeedProvider(authorization: .notDetermined)
        let viewModel = makeViewModel(provider: provider)

        viewModel.handle(authorization: .notDetermined)

        XCTAssertEqual(provider.requestAuthorizationCount, 1)
        XCTAssertEqual(viewModel.state, .acquiring)
    }

    func testDeniedShowsUnavailableWithSettingsButton() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)

        viewModel.handle(authorization: .denied)
        viewModel.handle(sample: sample(kmh: 50, at: clock))

        XCTAssertEqual(viewModel.state, .unavailable(.denied))
        XCTAssertEqual(viewModel.displayText, "--")
        XCTAssertEqual(viewModel.statusText, "Location access is off")
        XCTAssertTrue(viewModel.canOpenSettings)
    }

    func testRestrictedShowsUnavailableWithoutSettingsButton() {
        let viewModel = makeViewModel()

        viewModel.handle(authorization: .restricted)

        XCTAssertEqual(viewModel.state, .unavailable(.restricted))
        XCTAssertEqual(viewModel.statusText, "Location access is off")
        XCTAssertFalse(viewModel.canOpenSettings)
    }

    func testServicesOffShowsUnavailable() {
        let viewModel = makeViewModel()

        viewModel.handle(authorization: .servicesOff)

        XCTAssertEqual(viewModel.state, .unavailable(.servicesOff))
        XCTAssertEqual(viewModel.displayText, "--")
        XCTAssertEqual(viewModel.statusText, "Location Services is off")
        XCTAssertFalse(viewModel.canOpenSettings)
    }

    func testGrantingPermissionMovesToAcquiringThenLive() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .denied)

        viewModel.handle(authorization: .authorized)
        XCTAssertEqual(viewModel.state, .acquiring)

        viewModel.handle(sample: sample(kmh: 30, at: clock))
        XCTAssertEqual(viewModel.state, .live(weakSignal: false))
        XCTAssertEqual(viewModel.displayText, "30")
    }

    // MARK: - R19

    func testRunDisablesIdleTimerAndRestoresOnCancel() async {
        let idleTimer = IdleTimerRecorder()
        let viewModel = makeViewModel(idleTimer: idleTimer)

        let task = Task { await viewModel.run() }
        await waitUntil { idleTimer.calls == [true] }

        task.cancel()
        await task.value

        XCTAssertEqual(idleTimer.calls, [true, false])
    }

    // MARK: - Weak signal state

    // speed-accuracy R17, R18, R20

    func testWeakSignalWhenSigmaAboveLimit() {
        let clock = TestClock()
        let poor = makeViewModel(clock: clock)
        poor.handle(authorization: .authorized)
        poor.handle(sample: sample(kmh: 50, accuracy: 2.5, at: clock))
        XCTAssertEqual(poor.state, .live(weakSignal: true))
        XCTAssertEqual(poor.statusText, "Weak GPS signal")

        let good = makeViewModel(clock: clock)
        good.handle(authorization: .authorized)
        good.handle(sample: sample(kmh: 50, accuracy: 0.5, at: clock))
        XCTAssertEqual(good.state, .live(weakSignal: false))
        XCTAssertNil(good.statusText)
    }

    func testGPSOnlyGapHoldsWeakThenAcquiring() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 50, at: clock))

        clock.advance(by: 1.4)
        viewModel.tick()
        XCTAssertEqual(viewModel.state, .live(weakSignal: false))

        clock.advance(by: 0.2)
        viewModel.tick()
        XCTAssertEqual(viewModel.state, .live(weakSignal: true), "no fix for 1.5 s: a gap")
        XCTAssertEqual(viewModel.displayText, "50", "held, not extrapolated")

        clock.advance(by: 3.5)
        viewModel.tick()
        XCTAssertEqual(viewModel.state, .acquiring)
        XCTAssertEqual(viewModel.displayText, "--")
    }

    func testFixAfterGapClearsWeakSignal() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 50, at: clock))
        clock.advance(by: 2)
        viewModel.tick()
        XCTAssertEqual(viewModel.state, .live(weakSignal: true))

        viewModel.handle(sample: sample(kmh: 52, at: clock))

        XCTAssertEqual(viewModel.state, .live(weakSignal: false))
    }

    func testUnavailableUpdateStartsGap() async {
        let provider = FakeSpeedProvider()
        let clock = TestClock()
        let viewModel = makeViewModel(provider: provider, clock: clock)
        let task = Task { await viewModel.run() }
        await waitUntil { provider.speedSubscriberCount > 0 }
        provider.send(sample(kmh: 50, at: clock))
        await waitUntil { viewModel.displayText == "50" }

        provider.sendUnavailable()

        await waitUntil { viewModel.statusText == "Weak GPS signal" }
        XCTAssertEqual(viewModel.displayText, "50")
        task.cancel()
        await task.value
    }

    // MARK: - R21

    func testAccessibilityLabelLive() {
        let clock = TestClock()
        let defaults = makeDefaults()
        defaults.set("kmh", forKey: SpeedometerViewModel.unitDefaultsKey)
        let viewModel = makeViewModel(defaults: defaults, locale: unitedStates, clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 54, at: clock))

        XCTAssertEqual(viewModel.accessibilityLabel, "54 kilometers per hour")
    }

    func testAccessibilityLabelNoSignal() {
        let viewModel = makeViewModel(locale: unitedStates)

        XCTAssertEqual(viewModel.accessibilityLabel, "No GPS signal")
    }

    func testUnitAccessibilityValue() {
        let viewModel = makeViewModel(locale: unitedStates)
        XCTAssertEqual(viewModel.unitAccessibilityValue, "miles per hour")

        viewModel.toggleUnit()
        XCTAssertEqual(viewModel.unitAccessibilityValue, "kilometers per hour")
    }

    // MARK: - Gauge (speedometer-gauge R2, R6)

    func testGaugeFractionIsZeroWithoutReading() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.gaugeFraction, 0)

        viewModel.handle(authorization: .denied)
        XCTAssertEqual(viewModel.gaugeFraction, 0)
    }

    func testGaugeFractionScalesWithKmhMaximum() {
        let clock = TestClock()
        let viewModel = makeViewModel(locale: metric, clock: clock)
        viewModel.handle(authorization: .authorized)

        viewModel.handle(sample: sample(kmh: 100, at: clock))

        XCTAssertEqual(SpeedUnit.kmh.gaugeMaximum, 200)
        XCTAssertEqual(viewModel.gaugeFraction, 0.5, accuracy: 0.0001)
    }

    func testGaugeFractionUsesMphMaximum() {
        let clock = TestClock()
        let viewModel = makeViewModel(locale: unitedStates, clock: clock)
        viewModel.handle(authorization: .authorized)

        viewModel.handle(sample: sample(kmh: 104, at: clock)) // 64.6 mph, displayed as 65

        XCTAssertEqual(SpeedUnit.mph.gaugeMaximum, 130)
        XCTAssertEqual(viewModel.displayText, "65")
        XCTAssertEqual(viewModel.gaugeFraction, 0.5, accuracy: 0.0001)
    }

    func testGaugeFractionClampsAboveMaximum() {
        let clock = TestClock()
        let viewModel = makeViewModel(locale: metric, clock: clock)
        viewModel.handle(authorization: .authorized)

        viewModel.handle(sample: sample(kmh: 250, at: clock))

        XCTAssertEqual(viewModel.displayText, "250")
        XCTAssertEqual(viewModel.gaugeFraction, 1)
    }

    func testStatusSymbolPerState() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        XCTAssertEqual(viewModel.statusSymbol, "location.magnifyingglass")

        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 50, accuracy: 2.5, at: clock))
        XCTAssertEqual(viewModel.statusSymbol, "exclamationmark.triangle")

        viewModel.handle(sample: sample(kmh: 50, accuracy: 0.5, at: clock))
        XCTAssertNil(viewModel.statusSymbol)

        viewModel.handle(authorization: .denied)
        XCTAssertEqual(viewModel.statusSymbol, "location.slash")

        viewModel.handle(authorization: .servicesOff)
        XCTAssertEqual(viewModel.statusSymbol, "location.slash")

        viewModel.handle(authorization: .restricted)
        XCTAssertEqual(viewModel.statusSymbol, "location.slash")
    }

    // MARK: - gauge-themes R11, R12, R13

    func testFaceDefaultsToMinimalRing() {
        XCTAssertEqual(makeViewModel().face, .minimalRing)
    }

    func testSelectFaceUpdatesFace() {
        let viewModel = makeViewModel()
        viewModel.select(.digitalHUD)
        XCTAssertEqual(viewModel.face, .digitalHUD)
    }

    func testFacePersistsAcrossInstances() {
        let defaults = makeDefaults()
        makeViewModel(defaults: defaults).select(.retro)

        XCTAssertEqual(makeViewModel(defaults: defaults).face, .retro)
    }

    func testUnknownSavedFaceFallsBackToMinimalRing() {
        let defaults = makeDefaults()
        defaults.set("neonRemoved", forKey: SpeedometerViewModel.faceDefaultsKey)

        XCTAssertEqual(makeViewModel(defaults: defaults).face, .minimalRing)
    }

    func testChangingFaceKeepsSpeedUnitStateAndLabel() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 87, accuracy: 3, at: clock))
        let before = (viewModel.displayText, viewModel.unit, viewModel.state, viewModel.statusText, viewModel.accessibilityLabel)

        for face in GaugeFace.allCases {
            viewModel.select(face)
            XCTAssertEqual(viewModel.displayText, before.0)
            XCTAssertEqual(viewModel.unit, before.1)
            XCTAssertEqual(viewModel.state, before.2)
            XCTAssertEqual(viewModel.statusText, before.3)
            XCTAssertEqual(viewModel.accessibilityLabel, before.4)
        }
    }

    func testChangingFaceDoesNotResetFilter() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 100, at: clock))

        viewModel.select(.analogSport)
        // Equal weights at one instant give 95 (a reset would show 90): the filter kept its history.
        viewModel.handle(sample: sample(kmh: 90, at: clock))
        XCTAssertEqual(viewModel.displayText, "95")
    }

    // MARK: - speed-mascot R2, R5

    func testMoodFollowsState() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        XCTAssertEqual(viewModel.mood, .searching)

        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 50, at: clock))
        XCTAssertEqual(viewModel.mood, .happy, "first mood after searching is immediate")

        clock.advance(by: 6)
        viewModel.tick()
        XCTAssertEqual(viewModel.state, .acquiring)
        XCTAssertEqual(viewModel.mood, .searching)

        viewModel.handle(authorization: .denied)
        XCTAssertEqual(viewModel.mood, .sad, "ui-redesign R4")
    }

    // MARK: - ui-redesign R4

    func testDeniedShowsSadMascot() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 50, at: clock))
        viewModel.handle(authorization: .denied)
        XCTAssertEqual(viewModel.mood, .sad)
        viewModel.handle(authorization: .restricted)
        XCTAssertEqual(viewModel.mood, .sad)
    }

    func testServicesOffShowsSadMascot() {
        let viewModel = makeViewModel()
        viewModel.handle(authorization: .servicesOff)
        XCTAssertEqual(viewModel.mood, .sad)
    }

    func testNotDeterminedAfterDeniedShowsSearching() {
        let viewModel = makeViewModel()
        viewModel.handle(authorization: .denied)
        viewModel.handle(authorization: .notDetermined)
        XCTAssertEqual(viewModel.state, .acquiring)
        XCTAssertEqual(viewModel.mood, .searching)
    }

    func testRunWhileUnavailableKeepsSad() async {
        let viewModel = makeViewModel(provider: FakeSpeedProvider(authorization: .denied))
        viewModel.handle(authorization: .denied)
        XCTAssertEqual(viewModel.mood, .sad)
        // The scene becomes active again: a new run starts while location is still off.
        let task = Task { await viewModel.run() }
        await Task.yield()
        XCTAssertEqual(viewModel.mood, .sad, "run() does not flash searching while unavailable")
        task.cancel()
        await task.value
        XCTAssertEqual(viewModel.mood, .sad)
    }

    func testAuthorizedAfterDeniedShowsSearching() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .denied)
        XCTAssertEqual(viewModel.mood, .sad)
        viewModel.handle(authorization: .authorized)
        XCTAssertEqual(viewModel.state, .acquiring)
        XCTAssertEqual(viewModel.mood, .searching)
        viewModel.handle(sample: sample(kmh: 50, at: clock))
        XCTAssertEqual(viewModel.mood, .happy)
    }

    func testMoodUsesGPSOnlyEstimate() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 20, at: clock))

        // Two raw 40 km/h fixes would make it happy, but they are vague (±10 m/s): the estimate stays below 30.
        for _ in 1...2 {
            clock.advance(by: 1)
            viewModel.handle(sample: sample(kmh: 40, accuracy: 10, at: clock))
        }

        XCTAssertLessThan(viewModel.displayedSpeed ?? 0, 30)
        XCTAssertEqual(viewModel.mood, .calm)
    }

    func testStationaryTickBecomesSleepy() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 0, stationary: true, at: clock))
        XCTAssertEqual(viewModel.mood, .calm)

        clock.advance(by: 10)
        viewModel.tick()
        XCTAssertEqual(viewModel.mood, .sleepy)
        XCTAssertEqual(viewModel.displayText, "0", "a stationary fix never goes stale")
    }

    func testHardBrakingStartlesThenRecovers() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 60, at: clock))
        clock.advance(by: 1)
        viewModel.handle(sample: sample(kmh: 60, at: clock))
        // Filtered 60 -> about 22 km/h in 1 s: over 10 m/s².
        clock.advance(by: 1)
        viewModel.handle(sample: sample(kmh: 20, at: clock))
        XCTAssertEqual(viewModel.mood, .startled)

        clock.advance(by: 2)
        viewModel.tick()
        XCTAssertNotEqual(viewModel.mood, .startled)
    }

    func testRunResetsMoodToSearching() async {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 50, at: clock))
        XCTAssertEqual(viewModel.mood, .happy)

        let task = Task { await viewModel.run() }
        await waitUntil { viewModel.mood == .searching }
        task.cancel()
        await task.value
    }

    // MARK: - engine-sound R1, R2, R6, R11

    func testRunStartsEngineSoundListening() async {
        let detector = FakeSoundTriggerDetector(authorization: .authorized)
        let viewModel = makeViewModel(detector: detector)

        let task = Task { await viewModel.run() }
        await waitUntil { detector.eventSubscriberCount == 1 }
        XCTAssertEqual(viewModel.engineSound.phase, .listening)

        task.cancel()
        await task.value
        await waitUntil { detector.eventSubscriberCount == 0 }
    }

    func testMicRequestedOnlyAfterLocationAnswered() async {
        let provider = FakeSpeedProvider(authorization: .notDetermined)
        let detector = FakeSoundTriggerDetector(authorization: .notDetermined)
        let viewModel = makeViewModel(provider: provider, detector: detector)

        let task = Task { await viewModel.run() }
        await waitUntil { provider.requestAuthorizationCount == 1 }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(detector.requestAuthorizationCount, 0, "location prompt is still pending")

        provider.send(.authorized)
        await waitUntil { detector.requestAuthorizationCount == 1 }

        task.cancel()
        await task.value
    }

    func testEngineSoundSeesMovingFromDisplayedSpeed() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        XCTAssertFalse(viewModel.engineSound.isMoving(), "acquiring counts as stopped")

        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 30, at: clock))
        XCTAssertTrue(viewModel.engineSound.isMoving())

        viewModel.handle(sample: sample(kmh: 0, stationary: true, at: clock))
        XCTAssertFalse(viewModel.engineSound.isMoving())

        viewModel.handle(authorization: .denied)
        XCTAssertFalse(viewModel.engineSound.isMoving(), "unknown movement counts as stopped")
    }

    func testMicChipShownWhenNoLocationStatus() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 40, at: clock))
        viewModel.engineSound.handle(micAuthorization: .denied)

        XCTAssertEqual(viewModel.statusText, "Microphone off: enable it in Settings to hear engine sounds")
        XCTAssertEqual(viewModel.statusSymbol, "mic.slash")
        XCTAssertFalse(viewModel.canOpenSettings, "the mic hint has no button")
    }

    func testLocationChipTakesPriorityOverMicChip() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.engineSound.handle(micAuthorization: .denied)

        viewModel.handle(authorization: .authorized)
        XCTAssertEqual(viewModel.statusText, "Searching for GPS…")
        XCTAssertEqual(viewModel.statusSymbol, "location.magnifyingglass")

        viewModel.handle(sample: sample(kmh: 40, accuracy: 3, at: clock))
        XCTAssertEqual(viewModel.statusText, "Weak GPS signal")

        viewModel.handle(authorization: .denied)
        XCTAssertEqual(viewModel.statusText, "Location access is off")
        XCTAssertEqual(viewModel.statusSymbol, "location.slash")
    }
}
