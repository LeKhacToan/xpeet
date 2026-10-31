import XCTest
@testable import Xpeet

/// The "Engine sounds" Focus filter in `SpeedometerViewModel` (specs/engine-clip-toggle R16-R18), with a fake
/// provider. A separate file to keep the main test file under SwiftLint's length limit.
extension SpeedometerViewModelTests {
    // MARK: - R16

    func testFocusOverrideStopsListeningAndLeavesTheStoredSwitch() async {
        let defaults = makeDefaults()
        let detector = FakeSoundTriggerDetector(authorization: .authorized)
        let focus = FakeFocusFilterProvider(initialOverride: false)
        let viewModel = makeViewModel(defaults: defaults, detector: detector, focus: focus)

        let task = Task { await viewModel.run() }
        await waitUntil { detector.eventSubscriberCount == 1 }

        focus.send(true)
        await waitUntil { detector.eventSubscriberCount == 0 }
        XCTAssertTrue(viewModel.engineSoundsOffByFocus)
        XCTAssertTrue(viewModel.engineSoundsOn, "the switch keeps the user's choice")
        XCTAssertNil(defaults.object(forKey: SpeedometerViewModel.engineSoundsDefaultsKey), "nothing is stored")

        focus.send(false)
        await waitUntil { detector.eventSubscriberCount == 1 }
        XCTAssertFalse(viewModel.engineSoundsOffByFocus)

        task.cancel()
        await task.value
    }

    func testFocusOverrideHidesTheMicChip() {
        let clock = TestClock()
        let focus = FakeFocusFilterProvider()
        let viewModel = makeViewModel(clock: clock, focus: focus)
        viewModel.handle(authorization: .authorized)
        viewModel.handle(sample: sample(kmh: 40, at: clock))
        viewModel.engineSound.handle(micAuthorization: .denied)
        XCTAssertEqual(viewModel.statusSymbol, "mic.slash")

        viewModel.handle(focusOverride: true)
        XCTAssertNil(viewModel.statusText)

        viewModel.handle(focusOverride: false)
        XCTAssertEqual(viewModel.statusSymbol, "mic.slash")
    }

    func testSwitchOffStaysOffWhenTheFocusEnds() {
        let viewModel = makeViewModel(focus: FakeFocusFilterProvider())
        viewModel.setEngineSounds(false)
        viewModel.handle(focusOverride: true)
        viewModel.handle(focusOverride: false)
        XCTAssertFalse(viewModel.engineSound.isEnabled)
        XCTAssertFalse(viewModel.engineSoundsOn)
    }

    func testFocusEndingDoesNotAskForTheMicUntilTheNextRun() async {
        let provider = FakeSpeedProvider()
        let detector = FakeSoundTriggerDetector(authorization: .notDetermined)
        let focus = FakeFocusFilterProvider()
        let viewModel = makeViewModel(provider: provider, detector: detector, focus: focus)

        let task = Task { await viewModel.run() }
        await waitUntil { provider.speedSubscriberCount > 0 && focus.subscriberCount == 1 }
        focus.send(true)
        await waitUntil { viewModel.engineSoundsOffByFocus }
        focus.send(false)
        await waitUntil { viewModel.engineSound.isEnabled }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(detector.requestAuthorizationCount, 0, "no prompt pops up when the Focus ends")

        task.cancel()
        await task.value

        let nextRun = Task { await viewModel.run() }
        await waitUntil { focus.subscriberCount == 1 }
        focus.send(false)
        await waitUntil { detector.requestAuthorizationCount == 1 }

        nextRun.cancel()
        await nextRun.value
    }

    func testTurningTheSwitchOnAsksForAHeldMicPrompt() async {
        let provider = FakeSpeedProvider()
        let detector = FakeSoundTriggerDetector(authorization: .notDetermined)
        let focus = FakeFocusFilterProvider(initialOverride: true)
        let viewModel = makeViewModel(provider: provider, detector: detector, focus: focus)

        let task = Task { await viewModel.run() }
        await waitUntil { viewModel.engineSoundsOffByFocus && provider.speedSubscriberCount > 0 }
        focus.send(false)
        await waitUntil { viewModel.engineSound.isEnabled }
        XCTAssertEqual(detector.requestAuthorizationCount, 0)

        viewModel.setEngineSounds(false)
        viewModel.setEngineSounds(true)
        await waitUntil { detector.requestAuthorizationCount == 1 }

        task.cancel()
        await task.value
    }

    // MARK: - R17

    func testNothingListensUntilTheRunsFirstFocusValue() async {
        let provider = FakeSpeedProvider()
        let detector = FakeSoundTriggerDetector(authorization: .authorized)
        let focus = FakeFocusFilterProvider()
        let viewModel = makeViewModel(provider: provider, detector: detector, focus: focus)

        let task = Task { await viewModel.run() }
        await waitUntil { provider.speedSubscriberCount > 0 && focus.subscriberCount == 1 }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(detector.eventSubscriberCount, 0)
        XCTAssertFalse(viewModel.engineSoundsOffByFocus, "the sheet shows the stored switch until then")

        focus.send(false)
        await waitUntil { detector.eventSubscriberCount == 1 }

        task.cancel()
        await task.value
    }

    func testNoMicPromptUntilTheRunsFirstFocusValue() async {
        let provider = FakeSpeedProvider()
        let detector = FakeSoundTriggerDetector(authorization: .notDetermined)
        let focus = FakeFocusFilterProvider()
        let viewModel = makeViewModel(provider: provider, detector: detector, focus: focus)

        let task = Task { await viewModel.run() }
        await waitUntil { provider.speedSubscriberCount > 0 && focus.subscriberCount == 1 }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(detector.requestAuthorizationCount, 0)

        focus.send(false)
        await waitUntil { detector.requestAuthorizationCount == 1 }

        task.cancel()
        await task.value
    }

    func testEachRunWaitsForTheFocusValueAgain() async {
        let detector = FakeSoundTriggerDetector(authorization: .authorized)
        let focus = FakeFocusFilterProvider()
        let viewModel = makeViewModel(detector: detector, focus: focus)

        let first = Task { await viewModel.run() }
        await waitUntil { focus.subscriberCount == 1 }
        focus.send(false)
        await waitUntil { detector.eventSubscriberCount == 1 }
        first.cancel()
        await first.value

        let second = Task { await viewModel.run() }
        await waitUntil { focus.subscriberCount == 1 }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(detector.eventSubscriberCount, 0, "a Focus may have started while the app was away")
        XCTAssertNil(viewModel.focusOverride)

        focus.send(true)
        await waitUntil { viewModel.engineSoundsOffByFocus }
        XCTAssertEqual(detector.eventSubscriberCount, 0)

        second.cancel()
        await second.value
    }
}
