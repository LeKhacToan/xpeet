import Observation
import UIKit
import XCTest
@testable import Xpeet

/// The break reminder in `SpeedometerViewModel` (specs/break-reminder). A separate file to keep the main test file
/// under SwiftLint's length limit; it shares that file's helpers.
extension SpeedometerViewModelTests {
    private func seedStretch(_ defaults: UserDefaults, drivingTime: TimeInterval, lastMovementAt: Date) {
        TripStore(defaults: defaults).save(
            DrivingStretch(startedAt: lastMovementAt.addingTimeInterval(-drivingTime), drivingTime: drivingTime,
                           lastMovementAt: lastMovementAt)
        )
    }

    /// A due stretch (2 h), last moved now, and a Live reading at `kmh`.
    private func dueViewModel(clock: TestClock, locale: Locale? = nil, kmh: Double = 40, accuracy: Double = 0.5)
        -> SpeedometerViewModel {
        let defaults = makeDefaults()
        seedStretch(defaults, drivingTime: 7_200, lastMovementAt: clock.now)
        let viewModel = makeViewModel(defaults: defaults, locale: locale, clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: kmh, accuracy: accuracy, at: clock))
        return viewModel
    }

    /// One stationary fix, then ticks every 0.5 s for `seconds`.
    private func stayStopped(_ viewModel: SpeedometerViewModel, clock: TestClock, seconds: TimeInterval) {
        viewModel.handle(sample: sample(kmh: 0, stationary: true, at: clock))
        for _ in 0..<Int(seconds * 2) {
            clock.advance(by: 0.5)
            viewModel.tick()
        }
    }

    // MARK: - R1

    func testDrivingFeedsTheStretch() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)

        drive(viewModel, clock: clock, seconds: 60, kmh: 50)

        XCTAssertEqual(viewModel.breakTracker.stretch.drivingTime, 59.5, accuracy: 1e-9)
        XCTAssertNotNil(viewModel.breakTracker.stretch.startedAt)
    }

    func testWeakSignalStillCountsDriveTime() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 40, accuracy: 3, at: clock))
        XCTAssertEqual(viewModel.state, .live(weakSignal: true))

        clock.advance(by: 0.5)
        viewModel.tick()

        XCTAssertEqual(viewModel.breakTracker.stretch.drivingTime, 0.5, accuracy: 1e-9)
    }

    func testNoReadingAddsNoDriveTime() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        drive(viewModel, clock: clock, seconds: 10, kmh: 50)

        // Acquiring: the last fix goes stale. Until then the held reading is still Live and counts.
        for _ in 0..<20 {
            clock.advance(by: 0.5)
            viewModel.tick()
        }
        XCTAssertEqual(viewModel.state, .acquiring)
        let before = viewModel.breakTracker.stretch.drivingTime
        for _ in 0..<20 {
            clock.advance(by: 0.5)
            viewModel.tick()
        }
        for authorization in [LocationAuthorization.denied, .servicesOff, .restricted, .authorizedApproximate] {
            viewModel.handle(authorization: authorization)
            for _ in 0..<20 {
                clock.advance(by: 0.5)
                viewModel.tick()
            }
        }

        XCTAssertEqual(viewModel.breakTracker.stretch.drivingTime, before)
    }

    func testRoughFixesLeaveTheStretch() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        drive(viewModel, clock: clock, seconds: 10, kmh: 50)
        let before = viewModel.breakTracker

        for _ in 0..<5 {
            clock.advance(by: 1)
            viewModel.handle(approximateFix: sample(kmh: 50, at: clock))
            viewModel.handle(approximateFix: sample(kmh: 0, stationary: true, at: clock))
        }

        XCTAssertEqual(viewModel.breakTracker, before)
    }

    // MARK: - R5

    func testRunAfterLongBreakClearsTheStretch() async {
        let clock = TestClock()
        let defaults = makeDefaults()
        seedStretch(defaults, drivingTime: 7_200, lastMovementAt: clock.now.addingTimeInterval(-31 * 60))
        let viewModel = makeViewModel(defaults: defaults, clock: clock)
        XCTAssertEqual(viewModel.breakReminderHours, 2)

        let task = Task { await viewModel.run() }
        await waitUntil { viewModel.breakTracker.stretch.isEmpty }
        XCTAssertNil(viewModel.breakReminderHours)
        XCTAssertEqual(TripStore(defaults: defaults).loadStretch(), DrivingStretch(), "saved at once")

        task.cancel()
        await task.value
    }

    // MARK: - R6, R7

    func testNewTripKeepsTheStretch() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        drive(viewModel, clock: clock, seconds: 30, kmh: 50)
        let before = viewModel.breakTracker.stretch

        viewModel.startNewTrip()

        XCTAssertEqual(viewModel.breakTracker.stretch, before)
    }

    func testDeleteAllTripsClearsAndSavesTheStretch() {
        let clock = TestClock()
        let defaults = makeDefaults()
        let viewModel = dueViewModelWithDefaults(defaults, clock: clock)
        XCTAssertEqual(viewModel.breakReminderHours, 2)

        viewModel.deleteAllTrips()

        XCTAssertTrue(viewModel.breakTracker.stretch.isEmpty)
        XCTAssertNil(viewModel.breakReminderHours)
        XCTAssertEqual(TripStore(defaults: defaults).loadStretch(), DrivingStretch())
    }

    func testDeleteOneTripKeepsTheStretch() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        drive(viewModel, clock: clock, seconds: 30, kmh: 50)
        viewModel.startNewTrip()
        let before = viewModel.breakTracker.stretch
        let id = try? XCTUnwrap(viewModel.tripTracker.history.first?.id)

        if let id { viewModel.deleteTrip(id: id) }

        XCTAssertEqual(viewModel.breakTracker.stretch, before)
    }

    private func dueViewModelWithDefaults(_ defaults: UserDefaults, clock: TestClock) -> SpeedometerViewModel {
        seedStretch(defaults, drivingTime: 7_200, lastMovementAt: clock.now)
        let viewModel = makeViewModel(defaults: defaults, clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 40, at: clock))
        return viewModel
    }

    // MARK: - R8

    func testReminderAppearsAtTwoHoursOfDriveTime() {
        let clock = TestClock()
        let defaults = makeDefaults()
        seedStretch(defaults, drivingTime: 7_190, lastMovementAt: clock.now)
        let viewModel = makeViewModel(defaults: defaults, clock: clock)
        viewModel.handle(authorization: .authorized)

        drive(viewModel, clock: clock, seconds: 10, kmh: 50)
        // 7 190 + 9.5 s: one tick short.
        XCTAssertNil(viewModel.breakReminderHours)
        XCTAssertNotEqual(viewModel.statusSymbol, SpeedometerViewModel.breakReminderSymbol)

        viewModel.handle(sample: sample(kmh: 50, at: clock))
        XCTAssertEqual(viewModel.breakReminderHours, 2)
        XCTAssertEqual(viewModel.statusText, "2 h driving · time for a break")
    }

    func testReminderGoesAfterFifteenMinutesStopped() {
        let clock = TestClock()
        let viewModel = dueViewModel(clock: clock)
        XCTAssertEqual(viewModel.breakReminderHours, 2)

        stayStopped(viewModel, clock: clock, seconds: 899.5)
        XCTAssertEqual(viewModel.breakReminderHours, 2, "14:59.5 stopped")

        clock.advance(by: 0.5)
        viewModel.tick()
        XCTAssertNil(viewModel.breakReminderHours, "15:00 stopped is a rest")
        XCTAssertNil(viewModel.statusText)
    }

    func testDueStretchShowsAgainAfterRelaunch() async {
        let clock = TestClock()
        let defaults = makeDefaults()
        seedStretch(defaults, drivingTime: 7_300, lastMovementAt: clock.now)
        clock.advance(by: 20 * 60)
        let provider = FakeSpeedProvider()
        let viewModel = makeViewModel(provider: provider, defaults: defaults, clock: clock)

        let task = Task { await viewModel.run() }
        await waitUntil { provider.speedSubscriberCount > 0 && viewModel.state == .acquiring }
        XCTAssertEqual(viewModel.statusText, "Searching for GPS…")
        provider.send(sample(kmh: 40, at: clock))
        await waitUntil { viewModel.statusText == "2 h driving · time for a break" }

        task.cancel()
        await task.value
    }

    // MARK: - R9

    func testReminderTextAndSymbol() {
        let clock = TestClock()
        let viewModel = dueViewModel(clock: clock)

        XCTAssertEqual(viewModel.statusText, "2 h driving · time for a break")
        XCTAssertEqual(viewModel.statusSymbol, "cup.and.saucer")
        XCTAssertNotNil(UIImage(systemName: SpeedometerViewModel.breakReminderSymbol))
    }

    // MARK: - R10

    func testLocationStatusesRankAboveTheReminder() {
        let clock = TestClock()
        let viewModel = dueViewModel(clock: clock, accuracy: 3)
        viewModel.engineSound.handle(micAuthorization: .denied)
        XCTAssertEqual(viewModel.statusText, "Weak GPS signal")
        XCTAssertEqual(viewModel.breakReminderHours, 2, "due, but ranked below the location status")

        let cases: [(LocationAuthorization, String)] = [
            (.denied, "Location access is off"),
            (.restricted, "Location access is off"),
            (.servicesOff, "Location Services is off"),
            (.authorizedApproximate, "Precise Location is off"),
            (.authorized, "Searching for GPS…"),
        ]
        for (authorization, text) in cases {
            viewModel.handle(authorization: authorization)
            XCTAssertEqual(viewModel.statusText, text, "\(authorization)")
            XCTAssertEqual(viewModel.breakReminderHours, 2, "still due: \(authorization)")
            XCTAssertNotEqual(viewModel.statusSymbol, SpeedometerViewModel.breakReminderSymbol, "\(authorization)")
            XCTAssertNil(viewModel.statusAccessibilityLabel)
        }
    }

    func testReminderRanksAboveTheMicChip() {
        let clock = TestClock()
        let viewModel = dueViewModel(clock: clock)
        viewModel.engineSound.handle(micAuthorization: .denied)

        XCTAssertEqual(viewModel.statusText, "2 h driving · time for a break")
        XCTAssertEqual(viewModel.statusSymbol, "cup.and.saucer")

        // After a rest the mic chip shows again.
        stayStopped(viewModel, clock: clock, seconds: 900)
        XCTAssertEqual(viewModel.statusText, "Microphone off: enable it in Settings to hear engine sounds")
    }

    func testReminderShowsWhenTheLocationChipGoes() {
        let clock = TestClock()
        let viewModel = dueViewModel(clock: clock, accuracy: 3)
        XCTAssertEqual(viewModel.statusText, "Weak GPS signal")

        for _ in 0..<5 {
            clock.advance(by: 1)
            viewModel.handle(sample: sample(kmh: 40, at: clock))
        }

        XCTAssertEqual(viewModel.statusText, "2 h driving · time for a break")
    }

    // MARK: - R12

    func testReminderChangesNothingElse() {
        let clock = TestClock()
        let plainDefaults = makeDefaults()
        let dueDefaults = makeDefaults()
        seedStretch(dueDefaults, drivingTime: 7_200, lastMovementAt: clock.now)
        let plain = makeViewModel(defaults: plainDefaults, clock: clock)
        let due = makeViewModel(defaults: dueDefaults, clock: clock)
        XCTAssertEqual(due.breakReminderHours, 2)

        for viewModel in [plain, due] { viewModel.handle(authorization: .authorized) }
        for second in 0..<20 {
            for viewModel in [plain, due] {
                viewModel.handle(sample: sample(kmh: second < 10 ? 60 : 0, stationary: second >= 10, at: clock))
                viewModel.tick()
            }
            clock.advance(by: 1)
        }

        XCTAssertEqual(due.displayedSpeed, plain.displayedSpeed)
        XCTAssertEqual(due.mood, plain.mood)
        XCTAssertEqual(due.tripTracker.current.distance, plain.tripTracker.current.distance)
        XCTAssertEqual(due.tripTracker.current.movingTime, plain.tripTracker.current.movingTime)
        XCTAssertEqual(due.mapScene, plain.mapScene)
        XCTAssertEqual(due.engineSound.isMoving(), plain.engineSound.isMoving())
    }

    // MARK: - R14

    func testStretchSavedWithTheTrip() {
        let clock = TestClock()
        let defaults = makeDefaults()
        let viewModel = makeViewModel(defaults: defaults, clock: clock)
        viewModel.handle(authorization: .authorized)

        drive(viewModel, clock: clock, seconds: 30, kmh: 50)
        viewModel.startNewTrip()

        XCTAssertEqual(TripStore(defaults: defaults).loadStretch(), viewModel.breakTracker.stretch)
    }

    func testRelaunchWithinThirtyMinutesKeepsDriveTime() async {
        let clock = TestClock()
        let defaults = makeDefaults()
        let provider = FakeSpeedProvider()
        let first = makeViewModel(provider: provider, defaults: defaults, clock: clock)
        let task = Task { await first.run() }
        await waitUntil { provider.speedSubscriberCount > 0 }
        drive(first, clock: clock, seconds: 60, kmh: 50)
        let driven = first.breakTracker.stretch.drivingTime
        task.cancel()
        await task.value

        clock.advance(by: 20 * 60)
        let second = makeViewModel(defaults: defaults, clock: clock)

        XCTAssertEqual(second.breakTracker.stretch.drivingTime, driven, accuracy: 10)
    }

    // MARK: - R15

    func testStatusAccessibilityLabel() {
        let clock = TestClock()
        let viewModel = dueViewModel(clock: clock, locale: unitedStates)

        XCTAssertEqual(viewModel.statusAccessibilityLabel, "2 hours driving, time for a break")

        viewModel.engineSound.handle(micAuthorization: .denied)
        viewModel.handle(authorization: .denied)
        XCTAssertNil(viewModel.statusAccessibilityLabel)
    }

    // MARK: - Non-functional

    func testTicksDoNotInvalidateTheReminder() {
        let clock = TestClock()
        let defaults = makeDefaults()
        seedStretch(defaults, drivingTime: 7_300, lastMovementAt: clock.now)
        let viewModel = makeViewModel(defaults: defaults, clock: clock)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 50, at: clock))

        final class Flag: @unchecked Sendable { var isSet = false }
        let changed = Flag()
        withObservationTracking {
            _ = viewModel.breakReminderHours
        } onChange: {
            changed.isSet = true
        }
        for _ in 0..<100 {
            clock.advance(by: 0.5)
            viewModel.tick()
        }

        XCTAssertFalse(changed.isSet)
        XCTAssertEqual(viewModel.breakReminderHours, 2)
    }
}
