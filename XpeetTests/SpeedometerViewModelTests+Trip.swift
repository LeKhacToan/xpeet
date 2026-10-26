import XCTest
@testable import Xpeet

/// Trip behaviour of `SpeedometerViewModel` (specs/trip-stats). A separate file to keep the main test file under
/// SwiftLint's length limit; it shares that file's helpers.
extension SpeedometerViewModelTests {
    /// Fixes one second apart at `kmh`, ticking between them as the live app does.
    private func drive(_ viewModel: SpeedometerViewModel, clock: TestClock, seconds: Int, kmh: Double) {
        for _ in 0..<seconds {
            viewModel.handle(sample: sample(kmh: kmh, at: clock))
            clock.advance(by: 0.5)
            viewModel.tick()
            clock.advance(by: 0.5)
        }
    }

    // MARK: - trip-stats R1, R11

    func testDrivingGrowsTheTripLine() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        XCTAssertEqual(viewModel.trip.line, "0,0 km · 0 min")

        drive(viewModel, clock: clock, seconds: 121, kmh: 72)

        // 20 m/s for 120 s of chained updates: 2.4 km, 2 min (French decimal comma: the test locale is fr_FR).
        XCTAssertEqual(viewModel.trip.line, "2,4 km · 2 min")
        XCTAssertFalse(viewModel.trip.isEmpty)
    }

    func testWeakSignalGapStillCounts() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        drive(viewModel, clock: clock, seconds: 100, kmh: 72)
        let before = viewModel.trip.distanceValue

        // No fix for 4 s: Live with weak signal, the held speed still counts.
        for _ in 0..<8 {
            clock.advance(by: 0.5)
            viewModel.tick()
        }

        XCTAssertEqual(viewModel.state, .live(weakSignal: true))
        XCTAssertNotEqual(viewModel.trip.distanceValue, before)
    }

    func testTripLineHiddenWhileUnavailable() {
        let viewModel = makeViewModel()
        viewModel.handle(authorization: .denied)
        XCTAssertNil(viewModel.trip.line)

        viewModel.handle(authorization: .authorized)
        XCTAssertNotNil(viewModel.trip.line)
    }

    func testUnitSwitchConvertsTripLine() {
        let clock = TestClock()
        let viewModel = makeViewModel(locale: metric, clock: clock)
        viewModel.handle(authorization: .authorized)
        drive(viewModel, clock: clock, seconds: 101, kmh: 72)
        XCTAssertEqual(viewModel.trip.line, "2,0 km · 1 min")

        viewModel.toggleUnit()

        XCTAssertEqual(viewModel.trip.line, "1,2 mi · 1 min")
    }

    // MARK: - R6, R7

    func testStartNewTrip() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        drive(viewModel, clock: clock, seconds: 20, kmh: 72)

        viewModel.startNewTrip()

        XCTAssertTrue(viewModel.trip.isEmpty)
        XCTAssertEqual(viewModel.trip.line, "0,0 km · 0 min")
        XCTAssertEqual(viewModel.trip.history.count, 1)
    }

    func testRunAfterLongBreakArchivesTrip() async {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        drive(viewModel, clock: clock, seconds: 20, kmh: 72)

        clock.advance(by: TripTracker.newTripAfter + 60)
        let task = Task { await viewModel.run() }
        await waitUntil { viewModel.trip.history.count == 1 }

        XCTAssertTrue(viewModel.trip.isEmpty)
        task.cancel()
        await task.value
    }

    // MARK: - R10

    func testSavesWhileDrivingAndOnRunEnd() async {
        let defaults = makeDefaults()
        let provider = FakeSpeedProvider()
        let clock = TestClock()
        let viewModel = makeViewModel(provider: provider, defaults: defaults, clock: clock)
        viewModel.handle(authorization: .authorized)
        drive(viewModel, clock: clock, seconds: 12, kmh: 72)

        XCTAssertGreaterThan(TripStore(defaults: defaults).load().current.distance, 0, "saved during the drive")

        let task = Task { await viewModel.run() }
        await waitUntil { provider.speedSubscriberCount > 0 }
        viewModel.startNewTrip()
        drive(viewModel, clock: clock, seconds: 3, kmh: 36)
        task.cancel()
        await task.value

        let stored = TripStore(defaults: defaults).load()
        XCTAssertEqual(stored.history.count, 1, "the archived trip")
        XCTAssertGreaterThan(stored.current.distance, 0, "the new trip, saved when the run ended")
    }
}
