import AVFoundation
import XCTest
@testable import Xpeet

@MainActor
final class EngineSoundViewModelTests: XCTestCase {
    private final class TestClock {
        var now = Date(timeIntervalSince1970: 1_000)
        func advance(by seconds: TimeInterval) { now += seconds }
    }

    private var clock = TestClock()
    private lazy var detector = FakeSoundTriggerDetector()
    private lazy var player = FakeSoundPlayer()
    private var randomValue = 0.0
    private var moving = false

    private func makeViewModel() -> EngineSoundViewModel {
        let viewModel = EngineSoundViewModel(
            detector: detector,
            player: player,
            now: { [clock] in clock.now },
            random: { [unowned self] in randomValue }
        )
        viewModel.isMoving = { [unowned self] in moving }
        return viewModel
    }

    /// A listening view model, as `run()` leaves it once the mic is authorized.
    private func makeListening() -> EngineSoundViewModel {
        let viewModel = makeViewModel()
        viewModel.handle(micAuthorization: .authorized)
        viewModel.handleListeningStarted()
        return viewModel
    }

    /// One analysis window 0.75 s after the previous one.
    private func window(_ confidence: Double, label: String = "engine_starting") -> SoundTriggerEvent {
        clock.advance(by: 0.75)
        return SoundTriggerEvent(label: label, confidence: confidence, timestamp: clock.now)
    }

    /// Two qualifying windows: the rule fires.
    private func detect(_ viewModel: EngineSoundViewModel) -> SoundFile? {
        _ = viewModel.handle(event: window(0.9))
        return viewModel.handle(event: window(0.9))
    }

    private func waitUntil(timeout: TimeInterval = 2, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for condition", file: file, line: line)
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - R1

    func testRunSubscribesToEventsWhenAuthorized() async {
        let viewModel = makeViewModel()
        let task = Task { await viewModel.run() }
        await waitUntil { detector.eventSubscriberCount == 1 }
        XCTAssertEqual(viewModel.phase, .listening)
        task.cancel()
        await task.value
    }

    func testCancellingRunStopsEvents() async {
        let viewModel = makeViewModel()
        let task = Task { await viewModel.run() }
        await waitUntil { detector.eventSubscriberCount == 1 }
        task.cancel()
        await task.value
        await waitUntil { detector.eventSubscriberCount == 0 }
        XCTAssertEqual(viewModel.phase, .idle)
    }

    func testRunDoesNotListenWhenDenied() async {
        detector = FakeSoundTriggerDetector(authorization: .denied)
        let viewModel = makeViewModel()
        await viewModel.run()
        XCTAssertEqual(detector.eventSubscriberCount, 0)
        XCTAssertEqual(viewModel.phase, .idle)
    }

    func testRunListensAfterAuthorizationGranted() async {
        detector = FakeSoundTriggerDetector(authorization: .notDetermined, grantOnRequest: .authorized)
        let viewModel = makeViewModel()
        let task = Task { await viewModel.run() }
        await waitUntil { viewModel.micAuthorization == .notDetermined }
        viewModel.handle(locationAuthorizationResolved: true)
        await waitUntil { detector.eventSubscriberCount == 1 }
        task.cancel()
        await task.value
    }

    // MARK: - R2

    func testDoesNotRequestMicWhileLocationNotDetermined() {
        let viewModel = makeViewModel()
        viewModel.handle(micAuthorization: .notDetermined)
        viewModel.handle(locationAuthorizationResolved: false)
        XCTAssertEqual(detector.requestAuthorizationCount, 0)
    }

    func testRequestsMicOnceAfterLocationResolved() {
        let viewModel = makeViewModel()
        viewModel.handle(micAuthorization: .notDetermined)
        viewModel.handle(locationAuthorizationResolved: true)
        viewModel.handle(locationAuthorizationResolved: true)
        viewModel.handle(micAuthorization: .notDetermined)
        XCTAssertEqual(detector.requestAuthorizationCount, 1)
    }

    func testRequestsMicWhenLocationResolvedBeforeMicStatusArrives() {
        let viewModel = makeViewModel()
        viewModel.handle(locationAuthorizationResolved: true)
        XCTAssertEqual(detector.requestAuthorizationCount, 0, "mic status unknown yet")
        viewModel.handle(micAuthorization: .notDetermined)
        XCTAssertEqual(detector.requestAuthorizationCount, 1)
    }

    func testNeverRequestsMicWhenAlreadyAnswered() {
        let viewModel = makeViewModel()
        viewModel.handle(locationAuthorizationResolved: true)
        viewModel.handle(micAuthorization: .denied)
        viewModel.handle(micAuthorization: .authorized)
        XCTAssertEqual(detector.requestAuthorizationCount, 0)
    }

    // MARK: - R3

    func testTwoConsecutiveQualifyingWindowsFire() {
        XCTAssertNotNil(detect(makeListening()))
    }

    func testSingleQualifyingWindowDoesNotFire() {
        XCTAssertNil(makeListening().handle(event: window(0.95)))
    }

    func testLowConfidenceWindowBreaksStreak() {
        let viewModel = makeListening()
        XCTAssertNil(viewModel.handle(event: window(0.9)))
        XCTAssertNil(viewModel.handle(event: window(0.59)))
        XCTAssertNil(viewModel.handle(event: window(0.9)), "streak restarted")
        XCTAssertNotNil(viewModel.handle(event: window(0.9)))
    }

    func testConfidenceExactlyThresholdQualifies() {
        let viewModel = makeListening()
        _ = viewModel.handle(event: window(0.6))
        XCTAssertNotNil(viewModel.handle(event: window(0.6)))
    }

    func testEveryTriggerLabelQualifies() {
        for label in EngineSoundViewModel.triggerLabels {
            let viewModel = makeListening()
            _ = viewModel.handle(event: window(0.9, label: label))
            XCTAssertNotNil(viewModel.handle(event: window(0.9, label: label)), label)
        }
    }

    func testNonTriggerLabelDoesNotQualify() {
        let viewModel = makeListening()
        _ = viewModel.handle(event: window(0.99, label: "car_horn"))
        XCTAssertNil(viewModel.handle(event: window(0.99, label: "car_horn")))
    }

    func testGapBetweenWindowsBreaksStreak() {
        let viewModel = makeListening()
        _ = viewModel.handle(event: window(0.9))
        clock.advance(by: 1)
        XCTAssertNil(viewModel.handle(event: window(0.9)), "1.75 s gap")
    }

    func testConstants() {
        XCTAssertEqual(EngineSoundViewModel.triggerLabels, ["engine_starting", "engine_accelerating_revving", "motorcycle"])
        XCTAssertEqual(EngineSoundViewModel.confidenceThreshold, 0.6)
        XCTAssertEqual(EngineSoundViewModel.requiredConsecutiveWindows, 2)
        XCTAssertEqual(EngineSoundViewModel.cooldown, 60)
        XCTAssertEqual(EngineSoundViewModel.playbackTail, 0.5)
    }

    // MARK: - R5

    func testRandomLowPicksOhayo() {
        randomValue = 0.1
        XCTAssertEqual(detect(makeListening()), .ohayo)
    }

    func testRandomHighPicksVroom() {
        randomValue = 0.9
        XCTAssertEqual(detect(makeListening()), .vroom)
    }

    func testRandomOneIsClamped() {
        randomValue = 1
        XCTAssertEqual(detect(makeListening()), .vroom)
    }

    func testBundledSoundsExistAndAreAtMostThreeSeconds() throws {
        for file in SoundFile.allCases {
            let url = try XCTUnwrap(file.url, "\(file.rawValue).m4a is not in the bundle")
            let audio = try AVAudioPlayer(contentsOf: url)
            XCTAssertGreaterThan(audio.duration, 0.3, file.rawValue)
            XCTAssertLessThanOrEqual(audio.duration, 3, file.rawValue)
        }
    }

    // MARK: - R6

    func testEventWhileMovingIsDropped() {
        moving = true
        XCTAssertNil(detect(makeListening()))
    }

    func testEventWhenStoppedPlays() {
        let viewModel = makeListening()
        XCTAssertNotNil(detect(viewModel))
        XCTAssertEqual(viewModel.phase, .playing)
    }

    func testDroppedWhileMovingIsNotQueued() {
        let viewModel = makeListening()
        moving = true
        XCTAssertNil(detect(viewModel))
        moving = false
        XCTAssertNil(viewModel.handle(event: window(0.9)), "a new streak is needed")
        XCTAssertNotNil(viewModel.handle(event: window(0.9)))
    }

    // MARK: - R7

    func testEventsDuringCooldownAreDropped() {
        let viewModel = makeListening()
        XCTAssertNotNil(detect(viewModel))
        clock.advance(by: 2)
        viewModel.handlePlaybackFinished()
        clock.advance(by: 50)
        XCTAssertNil(detect(viewModel), "about 54 s after the start")
    }

    func testPlaysAgainAfterSixtySeconds() {
        let viewModel = makeListening()
        XCTAssertNotNil(detect(viewModel))
        clock.advance(by: 2)
        viewModel.handlePlaybackFinished()
        clock.advance(by: 57)
        XCTAssertNotNil(detect(viewModel), "60.5 s after the start")
    }

    func testFailedPlaybackStartsNoCooldown() {
        let viewModel = makeListening()
        XCTAssertNotNil(detect(viewModel))
        viewModel.handlePlaybackFailed()
        clock.advance(by: 1)
        XCTAssertNotNil(detect(viewModel))
    }

    // MARK: - R8

    func testEventsWhilePlayingAreDropped() {
        let viewModel = makeListening()
        XCTAssertNotNil(detect(viewModel))
        XCTAssertNil(detect(viewModel))
        XCTAssertEqual(viewModel.phase, .playing)
    }

    func testEventsWithinHalfSecondAfterEndAreDropped() {
        let viewModel = makeListening()
        XCTAssertNotNil(detect(viewModel))
        viewModel.handlePlaybackFailed()
        clock.advance(by: 0.2)
        _ = viewModel.handle(event: SoundTriggerEvent(label: "engine_starting", confidence: 0.9, timestamp: clock.now))
        clock.advance(by: 0.2)
        let event = SoundTriggerEvent(label: "engine_starting", confidence: 0.9, timestamp: clock.now)
        XCTAssertNil(viewModel.handle(event: event), "0.4 s after the sound ended")
    }

    func testEventAfterTailPlays() {
        let viewModel = makeListening()
        XCTAssertNotNil(detect(viewModel))
        viewModel.handlePlaybackFailed()
        XCTAssertNotNil(detect(viewModel), "1.5 s after the end")
    }

    func testPausesDetectorWhilePlayingAndResumesAfter() {
        let viewModel = makeListening()
        XCTAssertNotNil(detect(viewModel))
        XCTAssertEqual(detector.pauseCount, 1)
        XCTAssertEqual(detector.resumeCount, 0)
        viewModel.handlePlaybackFinished()
        XCTAssertEqual(detector.resumeCount, 1)
        XCTAssertEqual(viewModel.phase, .listening)
    }

    // MARK: - R11

    func testDeniedShowsMicChip() {
        let viewModel = makeViewModel()
        viewModel.handle(micAuthorization: .denied)
        XCTAssertEqual(viewModel.chipText, "Microphone off: enable it in Settings to hear engine sounds")
        XCTAssertEqual(viewModel.chipSymbol, "mic.slash")
    }

    func testAuthorizedAndNotDeterminedShowNoChip() {
        let viewModel = makeViewModel()
        XCTAssertNil(viewModel.chipText)
        viewModel.handle(micAuthorization: .notDetermined)
        XCTAssertNil(viewModel.chipText)
        viewModel.handle(micAuthorization: .authorized)
        XCTAssertNil(viewModel.chipSymbol)
    }

    // MARK: - R12

    func testFailingDetectorSetsFailedSilently() async {
        detector.failOnStart = true
        let viewModel = makeViewModel()
        await viewModel.run()
        XCTAssertEqual(viewModel.phase, .failed)
        XCTAssertNil(viewModel.chipText, "no error is shown")
    }

    func testStreamEndingMidRunSetsFailed() async {
        let viewModel = makeViewModel()
        let task = Task { await viewModel.run() }
        await waitUntil { detector.eventSubscriberCount == 1 }
        detector.finishEvents()
        await task.value
        XCTAssertEqual(viewModel.phase, .failed)
    }

    func testFailedRunRetriesOnNextRun() async {
        detector.failOnStart = true
        let viewModel = makeViewModel()
        await viewModel.run()
        XCTAssertEqual(viewModel.phase, .failed)

        detector.failOnStart = false
        let task = Task { await viewModel.run() }
        await waitUntil { viewModel.phase == .listening }
        task.cancel()
        await task.value
    }

    // MARK: - End to end

    func testRunPlaysThroughPlayerAndReturnsToListening() async {
        let viewModel = makeViewModel()
        let task = Task { await viewModel.run() }
        await waitUntil { detector.eventSubscriberCount == 1 }

        detector.send(window(0.9))
        detector.send(window(0.9))
        await waitUntil { player.isPlaying }
        XCTAssertEqual(player.played.count, 1)
        XCTAssertEqual(viewModel.phase, .playing)

        player.finishPlayback()
        await waitUntil { viewModel.phase == .listening }
        XCTAssertEqual(detector.resumeCount, 1)

        task.cancel()
        await task.value
    }
}
