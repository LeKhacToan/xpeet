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

        var matches: Bool { recorded.displayed == replayedDisplayed && recorded.state == replayedState }
    }

    private final class Clock {
        var now = Date(timeIntervalSince1970: 0)
    }

    /// Replays `events` in order. At each recorded `shown` line the ViewModel ticks, as the live app did, and what it
    /// shows is compared with what was recorded. A tick right after a fix changes nothing, so fix-driven lines compare
    /// the same way.
    static func compare(_ events: [DriveEvent], configuration: SpeedEstimator.Configuration = .init()) -> [Comparison] {
        let clock = Clock()
        let viewModel = makeViewModel(clock: clock, configuration: configuration)
        if let unit = events.lazy.compactMap({ if case .shown(let shown) = $0 { shown.unit } else { nil } }).first,
           viewModel.unit.rawValue != unit {
            viewModel.toggleUnit()
        }

        var comparisons: [Comparison] = []
        for event in events {
            switch event {
            case .header:
                break
            case let .fix(sample, arrival):
                clock.now = arrival
                viewModel.handle(sample: sample)
            case .unavailable(let arrival):
                clock.now = arrival
                viewModel.handleLocationUnavailable()
            case let .motion(sample, arrival):
                clock.now = arrival
                viewModel.handle(motion: [sample])
            case .shown(let shown):
                clock.now = shown.time
                viewModel.tick()
                comparisons.append(Comparison(
                    recorded: shown,
                    replayedDisplayed: viewModel.displayedSpeed,
                    replayedState: viewModel.state.recordedName
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
            makeRecorder: { nil }
        )
        viewModel.handle(authorization: .authorized)
        return viewModel
    }
}
