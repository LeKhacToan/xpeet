import Foundation
@testable import Xpeet

/// Feeds a recorded drive back through a fresh `SpeedometerViewModel`, on the recorded clock (specs/speed-accuracy
/// R26). Going through the ViewModel, not just the estimator, replays the stale and reset rules too.
@MainActor
enum DriveReplay {
    struct Comparison: Equatable {
        var recorded: DriveShown
        var replayedDisplayed: Int?
        var replayedState: String
        var replayedGPSOnly: SpeedEstimator.Estimate?

        /// Same number and state: expected for a recording replayed from its start.
        var matchesExactly: Bool { recorded.displayed == replayedDisplayed && recorded.state == replayedState }

        /// Same state and GPS-only estimate within `tolerance` m/s: expected for a clip cut from the middle of a
        /// drive once the filter has forgotten the history the clip lacks. The number itself may differ by one,
        /// because hysteresis holds whichever whole value each run reached.
        func matchesEstimate(tolerance: Double) -> Bool {
            guard recorded.state == replayedState else { return false }
            switch (recorded.gpsOnly, replayedGPSOnly) {
            case (nil, nil): return true
            case let (recorded?, replayed?): return abs(recorded.metersPerSecond - replayed.metersPerSecond) <= tolerance
            default: return false
            }
        }
    }

    private final class Clock {
        var now = Date(timeIntervalSince1970: 0)
    }

    /// Replays `events` in order. At each recorded `shown` line the ViewModel ticks, as the live app did, and what it
    /// shows is compared with what was recorded. A tick right after a fix changes nothing, so fix-driven lines compare
    /// the same way. Lines within `warmUp` seconds of the first fix are skipped.
    static func compare(
        _ events: [DriveEvent],
        configuration: SpeedEstimator.Configuration = .init(),
        warmUp: TimeInterval = 0
    ) -> [Comparison] {
        let clock = Clock()
        let viewModel = makeViewModel(clock: clock, configuration: configuration)
        var comparisons: [Comparison] = []
        var firstFix: Date?
        // Motion arrives in batches; samples recorded with one arrival time were one batch.
        var batch: (arrival: Date, samples: [MotionSample])?

        func flushMotion() {
            guard let pending = batch else { return }
            clock.now = pending.arrival
            viewModel.handle(motion: pending.samples)
            batch = nil
        }

        for event in events {
            if case let .motion(sample, arrival) = event {
                if let pending = batch, pending.arrival != arrival { flushMotion() }
                batch = (arrival, (batch?.samples ?? []) + [sample])
                continue
            }
            flushMotion()
            switch event {
            case .header, .motion:
                break
            case let .fix(sample, arrival):
                clock.now = arrival
                firstFix = firstFix ?? arrival
                viewModel.handle(sample: sample)
            case .unavailable(let arrival):
                clock.now = arrival
                viewModel.handleLocationUnavailable()
            case .shown(let shown):
                clock.now = shown.time
                // Unit changes aren't recorded as events; follow the unit each line was shown in.
                if viewModel.unit.rawValue != shown.unit { viewModel.toggleUnit() }
                viewModel.tick()
                guard let firstFix, shown.time.timeIntervalSince(firstFix) >= warmUp else { continue }
                comparisons.append(Comparison(
                    recorded: shown,
                    replayedDisplayed: viewModel.displayedSpeed,
                    replayedState: viewModel.state.recordedName,
                    replayedGPSOnly: viewModel.estimator.gpsOnly
                ))
            }
        }
        return comparisons
    }

    private static func makeViewModel(clock: Clock, configuration: SpeedEstimator.Configuration) -> SpeedometerViewModel {
        let suiteName = "DriveReplay-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let viewModel = SpeedometerViewModel(
            provider: FakeSpeedProvider(),
            motionProvider: FakeMotionProvider(),
            defaults: defaults,
            locale: Locale(identifier: "fr_FR"),
            now: { clock.now },
            setIdleTimerDisabled: { _ in },
            engineSound: EngineSoundViewModel(detector: FakeSoundTriggerDetector(), player: FakeSoundPlayer(), now: { clock.now }),
            estimatorConfiguration: configuration,
            makeRecorder: { nil },
            routeStore: RouteStore(folder: FileManager.default.temporaryDirectory.appending(path: "Routes-\(UUID().uuidString)")),
            tileFetcher: FakeTileFetcher()
        )
        viewModel.handle(authorization: .authorized)
        return viewModel
    }
}
