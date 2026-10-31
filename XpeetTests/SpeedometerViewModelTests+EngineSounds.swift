import XCTest
@testable import Xpeet

/// The "Engine sounds" switch in `SpeedometerViewModel` (specs/engine-clip-toggle). A separate file to keep the
/// main test file under SwiftLint's length limit; it shares that file's helpers.
extension SpeedometerViewModelTests {
    // MARK: - R2

    func testEngineSoundsOnWhenNothingStored() {
        let viewModel = makeViewModel()
        XCTAssertTrue(viewModel.engineSoundsOn)
        XCTAssertTrue(viewModel.engineSound.isEnabled)
    }

    func testEngineSoundsOnWhenStoredValueIsNotBool() {
        for stored: Any in ["NO", 0, "off", Data()] {
            let defaults = makeDefaults()
            defaults.set(stored, forKey: SpeedometerViewModel.engineSoundsDefaultsKey)
            XCTAssertTrue(makeViewModel(defaults: defaults).engineSoundsOn, "\(stored)")
        }
    }

    func testEngineSoundsOffIsRestored() {
        let defaults = makeDefaults()
        makeViewModel(defaults: defaults).setEngineSounds(false)

        let relaunched = makeViewModel(defaults: defaults)
        XCTAssertFalse(relaunched.engineSoundsOn)
        XCTAssertFalse(relaunched.engineSound.isEnabled)

        relaunched.setEngineSounds(true)
        XCTAssertTrue(makeViewModel(defaults: defaults).engineSoundsOn)
    }

    // MARK: - R3

    func testTogglingEngineSoundsChangesNothingElse() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 72, at: clock))
        let state = viewModel.state, speed = viewModel.displayedSpeed, unit = viewModel.unit, face = viewModel.face
        let mode = viewModel.screenMode, trip = viewModel.trip, hours = viewModel.breakReminderHours
        let estimator = viewModel.estimator, status = viewModel.statusText

        viewModel.setEngineSounds(false)
        viewModel.setEngineSounds(true)

        XCTAssertEqual(viewModel.state, state)
        XCTAssertEqual(viewModel.displayedSpeed, speed)
        XCTAssertEqual(viewModel.unit, unit)
        XCTAssertEqual(viewModel.face, face)
        XCTAssertEqual(viewModel.screenMode, mode)
        XCTAssertEqual(viewModel.trip, trip)
        XCTAssertEqual(viewModel.breakReminderHours, hours)
        XCTAssertEqual(viewModel.estimator, estimator)
        XCTAssertEqual(viewModel.statusText, status)
    }

    // MARK: - R4, R9

    func testEngineSoundsOffStopsListeningWhileRunContinues() async {
        let provider = FakeSpeedProvider()
        let detector = FakeSoundTriggerDetector(authorization: .authorized)
        let viewModel = makeViewModel(provider: provider, detector: detector)

        let task = Task { await viewModel.run() }
        await waitUntil { detector.eventSubscriberCount == 1 && provider.speedSubscriberCount > 0 }
        viewModel.setEngineSounds(false)
        await waitUntil { detector.eventSubscriberCount == 0 }
        XCTAssertGreaterThan(provider.speedSubscriberCount, 0, "location keeps running")

        viewModel.setEngineSounds(true)
        await waitUntil { detector.eventSubscriberCount == 1 }

        task.cancel()
        await task.value
    }

    func testRunWhileEngineSoundsOffNeverListens() async {
        let defaults = makeDefaults()
        defaults.set(false, forKey: SpeedometerViewModel.engineSoundsDefaultsKey)
        let provider = FakeSpeedProvider()
        let detector = FakeSoundTriggerDetector(authorization: .authorized)
        let viewModel = makeViewModel(provider: provider, defaults: defaults, detector: detector)

        let task = Task { await viewModel.run() }
        await waitUntil { provider.speedSubscriberCount > 0 }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(detector.eventSubscriberCount, 0)

        task.cancel()
        await task.value
    }

    // MARK: - R6

    func testEngineSoundsOffDefersMicPromptWithPreciseLocationOff() async {
        let provider = FakeSpeedProvider(authorization: .notDetermined)
        let detector = FakeSoundTriggerDetector(authorization: .notDetermined)
        let viewModel = makeViewModel(provider: provider, detector: detector)
        viewModel.setEngineSounds(false)

        let task = Task { await viewModel.run() }
        await waitUntil { provider.requestAuthorizationCount == 1 }
        provider.send(.authorizedApproximate)
        await waitUntil { viewModel.state == .unavailable(.preciseOff) }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(detector.requestAuthorizationCount, 0)

        viewModel.setEngineSounds(true)
        await waitUntil { detector.requestAuthorizationCount == 1 }

        task.cancel()
        await task.value
    }

    // MARK: - R7, R11

    func testEngineSoundsOffHidesMicChip() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 40, at: clock))
        viewModel.engineSound.handle(micAuthorization: .denied)
        XCTAssertEqual(viewModel.statusText, "Microphone off: enable it in Settings to hear engine sounds")

        viewModel.setEngineSounds(false)
        XCTAssertNil(viewModel.statusText)
        XCTAssertNil(viewModel.statusSymbol)
    }

    func testChipOrderWithEngineSoundsOnAndOff() {
        let clock = TestClock()
        let defaults = makeDefaults()
        TripStore(defaults: defaults).save(
            DrivingStretch(startedAt: clock.now - 7_200, drivingTime: 7_200, lastMovementAt: clock.now)
        )
        let viewModel = makeViewModel(defaults: defaults, clock: clock)
        viewModel.engineSound.handle(micAuthorization: .denied)

        for on in [true, false] {
            viewModel.setEngineSounds(on)
            viewModel.handle(authorization: .authorized)
            XCTAssertEqual(viewModel.statusText, "Searching for GPS…", "location first, engine sounds \(on)")
            XCTAssertEqual(viewModel.statusSymbol, "location.magnifyingglass")

            viewModel.handle(sample: sample(kmh: 40, at: clock))
            XCTAssertEqual(viewModel.statusText, "2 h driving · time for a break", "reminder next, engine sounds \(on)")
            XCTAssertEqual(viewModel.statusSymbol, "cup.and.saucer")
            viewModel.handle(authorization: .denied)
        }

        // After a rest only the mic chip is left, and only while the switch is on.
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 0, stationary: true, at: clock))
        for _ in 0..<1_800 {
            clock.advance(by: 0.5)
            viewModel.tick()
        }
        XCTAssertNil(viewModel.breakReminderHours)
        XCTAssertNil(viewModel.statusText, "engine sounds off: nothing below the reminder")
        viewModel.setEngineSounds(true)
        XCTAssertEqual(viewModel.statusText, "Microphone off: enable it in Settings to hear engine sounds")
        XCTAssertEqual(viewModel.statusSymbol, "mic.slash")
    }
}
