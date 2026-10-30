import XCTest
@testable import Xpeet

/// "Precise Location is off" in `SpeedometerViewModel` (specs/precise-location). A separate file to keep the main
/// test file under SwiftLint's length limit; it shares that file's helpers.
extension SpeedometerViewModelTests {
    /// A fix with a valid position, so the map would move if it were used.
    private func positionedFix(kmh: Double, stationary: Bool = false, latitude: Double = 45, at time: Date) -> SpeedSample {
        SpeedSample(
            metersPerSecond: kmh / 3.6, accuracy: 0.5, isStationary: stationary, timestamp: time,
            latitude: latitude, longitude: 120, horizontalAccuracy: 5, course: 0, courseAccuracy: 5
        )
    }

    // MARK: - R3

    func testFollowsPreciseLocationChangesWhileRunning() async {
        let provider = FakeSpeedProvider()
        let viewModel = makeViewModel(provider: provider)

        let task = Task { await viewModel.run() }
        await waitUntil { viewModel.state == .acquiring && provider.speedSubscriberCount > 0 }
        provider.send(.authorizedApproximate)
        await waitUntil { viewModel.state == .unavailable(.preciseOff) }
        provider.send(.authorized)
        await waitUntil { viewModel.state == .acquiring }

        task.cancel()
        await task.value
    }

    func testNewRunPicksUpAChangeMadeInSettings() async {
        let provider = FakeSpeedProvider()
        let viewModel = makeViewModel(provider: provider)

        let first = Task { await viewModel.run() }
        await waitUntil { provider.speedSubscriberCount > 0 }
        first.cancel()
        await first.value

        // Changed in Settings while the app was not active: the next subscription starts with the new value.
        provider.send(.authorizedApproximate)
        let second = Task { await viewModel.run() }
        await waitUntil { viewModel.state == .unavailable(.preciseOff) }

        second.cancel()
        await second.value
    }

    // MARK: - R4

    func testPreciseOffShowsItsOwnUnavailableReason() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)

        viewModel.handle(authorization: .authorizedApproximate)
        viewModel.handle(sample: sample(kmh: 50, at: clock))

        XCTAssertEqual(viewModel.state, .unavailable(.preciseOff))
        XCTAssertEqual(viewModel.displayText, "--")
        XCTAssertEqual(viewModel.gaugeFraction, 0)
        XCTAssertEqual(viewModel.statusText, "Precise Location is off")
        XCTAssertEqual(viewModel.statusSymbol, "location.slash")
    }

    func testPreciseOffClearsALiveReading() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 60, at: clock))
        XCTAssertEqual(viewModel.displayText, "60")

        viewModel.handle(authorization: .authorizedApproximate)

        XCTAssertEqual(viewModel.displayText, "--")
        XCTAssertEqual(viewModel.gaugeFraction, 0)
        XCTAssertEqual(viewModel.statusText, "Precise Location is off")
    }

    // MARK: - R5

    func testOpenSettingsAndHintForEachReason() {
        let viewModel = makeViewModel()
        let cases: [(LocationAuthorization, Bool, String?)] = [
            (.denied, true, "Enable Location in Settings to see your speed"),
            (.authorizedApproximate, true, "Turn on Precise Location under Location to see your speed"),
            (.restricted, false, nil),
            (.servicesOff, false, nil),
            (.authorized, false, nil),
        ]
        for (authorization, button, hint) in cases {
            viewModel.handle(authorization: authorization)
            XCTAssertEqual(viewModel.canOpenSettings, button, "\(authorization)")
            XCTAssertEqual(viewModel.openSettingsHint, hint, "\(authorization)")
        }
    }

    // MARK: - R6

    func testPreciseBackOnGoesAcquiringThenLive() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorizedApproximate)
        XCTAssertEqual(viewModel.mood, .sad)

        clock.advance(by: 30)
        viewModel.handle(authorization: .authorized)
        XCTAssertEqual(viewModel.state, .acquiring)
        XCTAssertEqual(viewModel.statusText, "Searching for GPS…")
        XCTAssertEqual(viewModel.mood, .searching)

        clock.advance(by: 1)
        viewModel.handle(sample: sample(kmh: 40, at: clock))
        XCTAssertEqual(viewModel.state, .live(weakSignal: false))
        XCTAssertEqual(viewModel.displayText, "40")
    }

    func testFixTakenBeforePreciseCameBackIsDropped() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorizedApproximate)
        let roughTime = clock.now
        clock.advance(by: 60)
        viewModel.handle(authorization: .authorized)
        let tripBefore = viewModel.tripTracker.current

        // A cached stationary fix from before the switch: today's rule would take it at any age.
        viewModel.handle(sample: positionedFix(kmh: 0, stationary: true, at: roughTime))
        XCTAssertEqual(viewModel.state, .acquiring)
        XCTAssertEqual(viewModel.displayText, "--")
        XCTAssertEqual(viewModel.tripTracker.current, tripBefore)

        clock.advance(by: 1)
        viewModel.handle(sample: positionedFix(kmh: 0, stationary: true, at: clock.now))
        XCTAssertEqual(viewModel.displayText, "0", "a fix taken after the switch is used")
    }

    func testPreciseOffToDeniedShowsTheNewReason() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorizedApproximate)

        viewModel.handle(authorization: .denied)
        XCTAssertEqual(viewModel.state, .unavailable(.denied))
        XCTAssertEqual(viewModel.statusText, "Location access is off")

        // Back to allowed by way of denied: a rough fix from before still doesn't count.
        let earlier = clock.now.addingTimeInterval(-1)
        clock.advance(by: 10)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: SpeedSample(metersPerSecond: 0, accuracy: 0.5, isStationary: true, timestamp: earlier))
        XCTAssertEqual(viewModel.displayText, "--")
    }

    func testFixTakenBeforePreciseCameBackSetsNoPosition() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorizedApproximate)
        let roughTime = clock.now
        clock.advance(by: 60)
        viewModel.handle(authorization: .authorized)

        viewModel.handle(sample: positionedFix(kmh: 0, stationary: true, latitude: 46, at: roughTime))

        XCTAssertFalse(viewModel.hasPosition)
        XCTAssertNil(viewModel.lastPosition)
        XCTAssertTrue(viewModel.showsMapPlaceholder)
    }

    // MARK: - R7

    func testPreciseOffShowsSadMascot() {
        let viewModel = makeViewModel()
        viewModel.handle(authorization: .authorizedApproximate)
        XCTAssertEqual(viewModel.mood, .sad)
    }

    func testEngineSoundCountsPreciseOffAsStopped() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 30, at: clock))
        XCTAssertTrue(viewModel.engineSound.isMoving())

        viewModel.handle(authorization: .authorizedApproximate)
        XCTAssertFalse(viewModel.engineSound.isMoving(), "unknown movement counts as stopped (engine-sound R6)")
    }

    func testMicRequestedAfterPreciseOffAnswer() async {
        let provider = FakeSpeedProvider(authorization: .notDetermined)
        let detector = FakeSoundTriggerDetector(authorization: .notDetermined)
        let viewModel = makeViewModel(provider: provider, detector: detector)

        let task = Task { await viewModel.run() }
        await waitUntil { provider.requestAuthorizationCount == 1 }
        provider.send(.authorizedApproximate)
        await waitUntil { detector.requestAuthorizationCount == 1 }

        task.cancel()
        await task.value
    }

    func testTripLineHiddenWhilePreciseOff() {
        let viewModel = makeViewModel()
        viewModel.handle(authorization: .authorized)
        XCTAssertNotNil(viewModel.trip.line)

        viewModel.handle(authorization: .authorizedApproximate)
        XCTAssertNil(viewModel.trip.line)
    }

    func testPlaceholderWithoutMarkerWhilePreciseOff() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: positionedFix(kmh: 40, at: clock.now))
        XCTAssertNotNil(viewModel.mapScene.marker)

        viewModel.handle(authorization: .authorizedApproximate)

        XCTAssertTrue(viewModel.showsMapPlaceholder)
        XCTAssertNil(viewModel.mapScene.marker)
    }

    // MARK: - R8

    func testPreciseOffChipOutranksMicChip() {
        let viewModel = makeViewModel()
        viewModel.engineSound.handle(micAuthorization: .denied)

        viewModel.handle(authorization: .authorizedApproximate)

        XCTAssertEqual(viewModel.statusText, "Precise Location is off")
        XCTAssertEqual(viewModel.statusSymbol, "location.slash")
    }

    // MARK: - R9

    func testRoughFixesNeverMoveTheReading() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        let rough = [
            positionedFix(kmh: 0, stationary: true, latitude: 46, at: clock.now),
            positionedFix(kmh: 80, latitude: 46.1, at: clock.now),
            positionedFix(kmh: 0, stationary: true, latitude: 46.2, at: clock.now.addingTimeInterval(-600)),
        ]

        func assertUnchanged(_ when: String) {
            let state = viewModel.state, text = viewModel.displayText, mood = viewModel.mood
            let estimator = viewModel.estimator, trip = viewModel.tripTracker.current, scene = viewModel.mapScene
            let position = viewModel.lastPosition
            rough.forEach(viewModel.handle(approximateFix:))
            XCTAssertEqual(viewModel.state, state, when)
            XCTAssertEqual(viewModel.displayText, text, when)
            XCTAssertEqual(viewModel.mood, mood, when)
            XCTAssertEqual(viewModel.estimator, estimator, when)
            XCTAssertEqual(viewModel.tripTracker.current, trip, when)
            XCTAssertEqual(viewModel.mapScene, scene, when)
            XCTAssertEqual(viewModel.lastPosition, position, when)
        }

        viewModel.handle(authorization: .authorized)
        assertUnchanged("acquiring")

        viewModel.handle(sample: positionedFix(kmh: 50, at: clock.now))
        assertUnchanged("live")

        // The stale timer was not refreshed: 6 s after the last precise fix it still drops to Acquiring.
        clock.advance(by: 6)
        rough.forEach(viewModel.handle(approximateFix:))
        viewModel.tick()
        XCTAssertEqual(viewModel.state, .acquiring)

        viewModel.handle(authorization: .authorizedApproximate)
        assertUnchanged("unavailable")
    }

    func testRoughFixBeforeFirstAuthorizationIsIgnored() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)

        viewModel.handle(approximateFix: positionedFix(kmh: 0, stationary: true, at: clock.now.addingTimeInterval(-300)))

        XCTAssertEqual(viewModel.displayText, "--")
        XCTAssertEqual(viewModel.mood, .searching)
        XCTAssertFalse(viewModel.hasPosition)
    }

    func testRoughFixesDoNotGrowTheTrip() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 50, at: clock))
        let before = viewModel.tripTracker.current

        for second in 1...10 {
            clock.advance(by: 1)
            viewModel.handle(approximateFix: positionedFix(kmh: 50, latitude: 45 + Double(second) / 1_000, at: clock.now))
        }

        XCTAssertEqual(viewModel.tripTracker.current.distance, before.distance)
        XCTAssertEqual(viewModel.tripTracker.current.movingTime, before.movingTime)
        XCTAssertEqual(viewModel.tripTracker.current.stoppedTime, before.stoppedTime)
    }

    func testRoughFixesDoNotMoveTheMap() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: positionedFix(kmh: 40, at: clock.now))
        let scene = viewModel.mapScene, position = viewModel.lastPosition, route = viewModel.routeRecorder.route

        // Kilometres away, as rough positions are.
        viewModel.handle(approximateFix: positionedFix(kmh: 40, latitude: 45.05, at: clock.now.addingTimeInterval(1)))

        XCTAssertTrue(viewModel.hasPosition)
        XCTAssertEqual(viewModel.lastPosition, position)
        XCTAssertEqual(viewModel.mapScene, scene)
        XCTAssertEqual(viewModel.routeRecorder.route, route)
    }

    // MARK: - R10, R11

    func testRoughFixesAreRecordedButNotShown() async {
        let provider = FakeSpeedProvider()
        let clock = TestClock()
        let spy = SpyDriveLog()
        let viewModel = makeViewModel(provider: provider, clock: clock, recorder: spy)
        let fix = sample(kmh: 50, at: clock)

        let task = Task { await viewModel.run() }
        await waitUntil { provider.speedSubscriberCount > 0 && viewModel.state == .acquiring }
        provider.sendApproximate(fix)
        await waitUntil { spy.events.contains(.fix(fix, arrival: clock.now)) }
        XCTAssertEqual(viewModel.state, .acquiring)
        XCTAssertEqual(viewModel.displayText, "--")

        task.cancel()
        await task.value
    }

    // MARK: - R14

    func testPreciseLocationStrings() {
        let viewModel = makeViewModel(locale: unitedStates)
        viewModel.handle(authorization: .authorizedApproximate)

        XCTAssertEqual(viewModel.statusText, "Precise Location is off")
        XCTAssertEqual(viewModel.openSettingsHint, "Turn on Precise Location under Location to see your speed")
        XCTAssertEqual(viewModel.accessibilityLabel, "No GPS signal")
    }
}
