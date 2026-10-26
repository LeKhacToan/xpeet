import XCTest
@testable import Xpeet

/// speed-accuracy behaviour of `SpeedometerViewModel`. A separate file only to keep the main test file under SwiftLint's
/// length limit; it shares that file's helpers.
extension SpeedometerViewModelTests {
    // MARK: - speed-accuracy R2, R3

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

    func testEachRunStartsAFreshMotionClock() async {
        let motion = FakeMotionProvider()
        let viewModel = makeViewModel(motion: motion)
        let reading = MotionSample(timestamp: 42, userAcceleration: .zero, gravity: Vector3(x: 0, y: 0, z: -1), rotationRate: .zero)
        let first = Task { await viewModel.run() }
        await waitUntil { motion.subscriberCount > 0 }
        motion.send([reading])
        await waitUntil { viewModel.estimator.motionClock.offset != nil }
        first.cancel()
        await first.value

        // Core Motion's clock pauses while the phone sleeps: the old offset may be wrong in the next run.
        let second = Task { await viewModel.run() }
        await waitUntil { motion.subscriberCount > 0 }
        XCTAssertNil(viewModel.estimator.motionClock.offset)
        second.cancel()
        await second.value
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

    // MARK: - speed-accuracy R5, R13, R15

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

    func testHysteresisHoldsSpecWobble() {
        // R15's own example: an estimate wobbling 59.4 <-> 60.4 km/h keeps showing 60.
        var shown = 60
        for kmh in [59.4, 60.4, 59.4, 60.4, 59.4] {
            shown = SpeedometerViewModel.displayValue(for: kmh / 3.6, in: .kmh, holding: shown)
            XCTAssertEqual(shown, 60, "at \(kmh)")
        }
        XCTAssertEqual(SpeedometerViewModel.displayValue(for: 59.3 / 3.6, in: .kmh, holding: 60), 59)
        XCTAssertEqual(SpeedometerViewModel.displayValue(for: 60.7 / 3.6, in: .kmh, holding: 60), 61)
        XCTAssertEqual(SpeedometerViewModel.displayValue(for: 0.44704 * 40.6, in: .mph, holding: 40), 40)
    }

    func testPositionSpeedStartsFromAcquiring() throws {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock, configuration: .init(usesPositionSpeed: true))
        viewModel.handle(authorization: .authorized)

        // Fixes without Doppler speed, 20 m/s north: the third has a partner 2 s back (R13).
        for second in 0...2 {
            viewModel.handle(sample: SpeedSample(
                metersPerSecond: -1, accuracy: -1, isStationary: false, timestamp: clock.now,
                latitude: Double(second) * 20 / 111_194.93, longitude: 0, horizontalAccuracy: 5
            ))
            if second < 2 { clock.advance(by: 1) }
        }

        XCTAssertEqual(try XCTUnwrap(viewModel.displayedSpeed), 72)
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

    // MARK: - speed-accuracy R17, R18, R20

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

    // MARK: - speed-accuracy R22, R23

    func testRunRecordsHeaderInputsAndShown() async {
        let provider = FakeSpeedProvider()
        let motion = FakeMotionProvider()
        let spy = SpyDriveLog()
        let clock = TestClock()
        let viewModel = makeViewModel(provider: provider, clock: clock, motion: motion, recorder: spy)

        let task = Task { await viewModel.run() }
        await waitUntil { provider.speedSubscriberCount > 0 && motion.subscriberCount > 0 }
        let fix = sample(kmh: 72, at: clock)
        provider.send(fix)
        let reading = MotionSample(timestamp: 7, userAcceleration: .zero, gravity: Vector3(x: 0, y: 0, z: -1), rotationRate: .zero)
        motion.send([reading])
        await waitUntil { spy.events.count >= 4 }

        guard case .header = spy.events.first else { return XCTFail("header first: \(spy.events)") }
        XCTAssertTrue(spy.events.contains(.fix(fix, arrival: clock.now)))
        XCTAssertTrue(spy.events.contains(.motion(reading, arrival: clock.now)))
        XCTAssertTrue(spy.events.contains { event in
            if case .shown(let shown) = event { return shown.displayed == 72 && shown.source == .gpsOnly }
            return false
        })
        task.cancel()
        await task.value
        XCTAssertTrue(spy.isFinished)
    }

    func testFailingRecorderDoesNotChangeOutput() async {
        let provider = FakeSpeedProvider()
        let clock = TestClock()
        let viewModel = makeViewModel(provider: provider, clock: clock, recorder: DriveRecorder(sink: FailingDriveSink()))

        let task = Task { await viewModel.run() }
        await waitUntil { provider.speedSubscriberCount > 0 }
        provider.send(sample(kmh: 72, at: clock))
        await waitUntil { viewModel.displayText == "72" }
        clock.advance(by: 1)
        provider.send(sample(kmh: 74, at: clock))
        await waitUntil { viewModel.displayText == "74" }

        XCTAssertEqual(viewModel.state, .live(weakSignal: false))
        task.cancel()
        await task.value
    }
}
