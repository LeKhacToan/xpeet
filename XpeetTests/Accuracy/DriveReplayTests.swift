import XCTest
@testable import Xpeet

@MainActor
final class DriveReplayTests: XCTestCase {
    private final class TestClock {
        var now = Date(timeIntervalSince1970: 500)
        func advance(by seconds: TimeInterval) { now += seconds }
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "timed out")
    }

    private func sample(kmh: Double, at clock: TestClock) -> SpeedSample {
        SpeedSample(metersPerSecond: kmh / 3.6, accuracy: 0.5, isStationary: false, timestamp: clock.now)
    }

    // MARK: - specs/speed-accuracy R26

    /// Records a live run (fixes, a gap, iOS "unavailable", motion and real ticks), then replays the recording:
    /// every recorded `shown` line must come out the same.
    func testReplayMatchesLiveFeed() async throws {
        let provider = FakeSpeedProvider()
        let motion = FakeMotionProvider()
        let spy = SpyDriveLog()
        let clock = TestClock()
        let viewModel = SpeedometerViewModel(
            provider: provider,
            motionProvider: motion,
            defaults: try XCTUnwrap(UserDefaults(suiteName: "DriveReplayTests-\(UUID().uuidString)")),
            locale: Locale(identifier: "fr_FR"),
            now: { clock.now },
            setIdleTimerDisabled: { _ in },
            engineSound: EngineSoundViewModel(detector: FakeSoundTriggerDetector(), player: FakeSoundPlayer(), now: { clock.now }),
            makeRecorder: { spy }
        )
        let task = Task { await viewModel.run() }
        await waitUntil { provider.speedSubscriberCount > 0 && motion.subscriberCount > 0 }

        for kmh in [30.0, 34, 37, 38.2, 38.6] {
            provider.send(sample(kmh: kmh, at: clock))
            let reading = MotionSample(
                timestamp: clock.now.timeIntervalSince1970 - 400,
                userAcceleration: Vector3(x: 0.3, y: 0, z: 0),
                gravity: Vector3(x: 0, y: 0, z: -1),
                rotationRate: .zero
            )
            motion.send([reading])
            await waitUntil { spy.events.contains(.fix(self.sample(kmh: kmh, at: clock), arrival: clock.now)) }
            clock.advance(by: 1)
        }
        // A gap: no fix for 2 s (weak signal), then iOS reports unavailable, then fixes stop for good (Acquiring).
        clock.advance(by: 1)
        let ticksBefore = spy.events.count
        await waitUntil { spy.events.count > ticksBefore }
        provider.sendUnavailable()
        await waitUntil { spy.events.contains(.unavailable(arrival: clock.now)) }
        clock.advance(by: 4)
        await waitUntil { viewModel.state == .acquiring }
        task.cancel()
        await task.value

        let comparisons = DriveReplay.compare(spy.events)

        XCTAssertGreaterThan(comparisons.count, 6)
        XCTAssertTrue(comparisons.contains { $0.recorded.state == "liveWeak" }, "the gap was recorded")
        for comparison in comparisons {
            XCTAssertTrue(comparison.matchesExactly, "\(comparison)")
        }
    }

    /// A clip cut from the middle of a drive lacks the filter's history; after 10 s of fixes the replay has
    /// caught up with what was recorded.
    func testClipFromMiddleMatchesAfterWarmUp() throws {
        var events: [DriveEvent] = []
        let clock = TestClock()
        let viewModel = SpeedometerViewModel(
            provider: FakeSpeedProvider(),
            motionProvider: FakeMotionProvider(),
            defaults: try XCTUnwrap(UserDefaults(suiteName: "DriveReplayTests-\(UUID().uuidString)")),
            locale: Locale(identifier: "fr_FR"),
            now: { clock.now },
            setIdleTimerDisabled: { _ in },
            engineSound: EngineSoundViewModel(detector: FakeSoundTriggerDetector(), player: FakeSoundPlayer(), now: { clock.now }),
            makeRecorder: { nil }
        )
        viewModel.handle(authorization: .authorized)
        for second in 0..<60 {
            let kmh = 60 + 25 * sin(Double(second) / 6)
            let fix = sample(kmh: kmh, at: clock)
            events.append(.fix(fix, arrival: clock.now))
            viewModel.handle(sample: fix)
            events.append(.shown(DriveShown(
                time: clock.now, displayed: viewModel.displayedSpeed, unit: viewModel.unit.rawValue,
                state: viewModel.state.recordedName, source: .gpsOnly, gpsOnly: viewModel.estimator.gpsOnly,
                fused: nil, inGap: false
            )))
            clock.advance(by: 1)
        }

        let clip = Array(events.dropFirst(60))
        let comparisons = DriveReplay.compare(clip, warmUp: 10)

        XCTAssertEqual(comparisons.count, 20)
        for comparison in comparisons {
            XCTAssertTrue(comparison.matchesEstimate(tolerance: 0.05), "\(comparison)")
        }
    }

    /// Every committed clip replays like it was recorded, once the filter has warmed up.
    func testFixturesReplayAfterWarmUp() throws {
        let fixtures = DriveFile.files(in: DriveFile.fixturesDirectory)
        try XCTSkipIf(fixtures.isEmpty, "No committed drive clips yet (made with scripts/make-fixture.py).")
        for url in fixtures {
            let drive = try DriveFile.load(url, requireAnonymised: true)
            for comparison in DriveReplay.compare(drive.events, warmUp: 10) {
                XCTAssertTrue(comparison.matchesEstimate(tolerance: 0.05), "\(drive.name): \(comparison)")
            }
        }
    }

    // MARK: - R31

    func testFixturesHaveNoAbsoluteCoordinates() throws {
        for url in DriveFile.files(in: DriveFile.fixturesDirectory) {
            XCTAssertNoThrow(try DriveFile.load(url, requireAnonymised: true), url.lastPathComponent)
        }
    }

    func testLoaderRejectsAbsoluteCoordinates() throws {
        let real = SpeedSample(
            metersPerSecond: 10, accuracy: 0.5, isStationary: false, timestamp: Date(timeIntervalSince1970: 12),
            latitude: 21.03, longitude: 105.85, horizontalAccuracy: 5
        )
        let anonymised = SpeedSample(
            metersPerSecond: 10, accuracy: 0.5, isStationary: false, timestamp: Date(timeIntervalSince1970: 12),
            latitude: 0.0004, longitude: -0.0002, horizontalAccuracy: 5
        )
        let realDate = DriveEvent.unavailable(arrival: Date(timeIntervalSince1970: 1_800_000_000))

        XCTAssertFalse(DriveFile.isAnonymised(.fix(real, arrival: Date(timeIntervalSince1970: 12))))
        XCTAssertFalse(DriveFile.isAnonymised(realDate))
        XCTAssertTrue(DriveFile.isAnonymised(.fix(anonymised, arrival: Date(timeIntervalSince1970: 12.3))))

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DriveReplayTests-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let line = try DriveEvent.makeEncoder().encode(DriveEvent.fix(real, arrival: Date(timeIntervalSince1970: 12)))
        try line.write(to: url)
        XCTAssertThrowsError(try DriveFile.load(url, requireAnonymised: true)) { error in
            XCTAssertEqual(error as? DriveFile.LoadError, .notAnonymised(line: 1))
        }
    }
}
