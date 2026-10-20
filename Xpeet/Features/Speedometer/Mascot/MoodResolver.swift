import Foundation

/// Maps the filtered speed to a `Mood`. Pure value type: no SwiftUI, no CoreLocation.
/// Speeds are m/s so the result is unit-independent. Hysteresis and a two-sample debounce stop flicker.
struct MoodResolver: Equatable {
    // MARK: Thresholds (specs/speed-mascot R3, R5, R6)

    /// calm -> happy at 30 km/h; happy -> calm below 25 km/h.
    static let happyEnterMetersPerSecond = 30 / 3.6
    static let happyExitMetersPerSecond = 25 / 3.6
    /// happy -> worried at 110 km/h; worried -> happy below 100 km/h.
    static let worriedEnterMetersPerSecond = 110 / 3.6
    static let worriedExitMetersPerSecond = 100 / 3.6
    /// Same "stopped" clamp as the number (speedometer R7).
    static let stoppedBelowMetersPerSecond = 1 / 3.6
    static let sleepyAfter: TimeInterval = 10
    /// A speed-based mood takes effect once this many consecutive samples agree.
    static let debounceSamples = 2
    /// Deceleration that counts as hard braking, m/s² (about 0.3 g).
    static let brakeThreshold = 3.0
    /// Samples further apart than this are not compared for braking.
    static let brakeMaxInterval: TimeInterval = 5
    static let startledDuration: TimeInterval = 2

    private enum Band: Equatable {
        case calm, happy, worried

        var mood: Mood {
            switch self {
            case .calm: .calm
            case .happy: .happy
            case .worried: .worried
            }
        }
    }

    private(set) var mood: Mood = .searching
    private var band: Band = .calm
    private var candidate: Band?
    private var candidateCount = 0
    private var stoppedSince: Date?
    private var startledUntil: Date?
    private var last: (speed: Double, at: Date)?

    // MARK: Input

    /// A new filtered speed. `at` is the sample's timestamp, which braking detection compares.
    mutating func sample(metersPerSecond speed: Double, at time: Date) -> Mood {
        if let last, case let interval = time.timeIntervalSince(last.at), interval > 0, interval <= Self.brakeMaxInterval,
           (last.speed - speed) / interval >= Self.brakeThreshold {
            startledUntil = time.addingTimeInterval(Self.startledDuration)
        }
        let wasSearching = last == nil
        last = (speed, time)

        if speed < Self.stoppedBelowMetersPerSecond {
            stoppedSince = stoppedSince ?? time
        } else {
            stoppedSince = nil
        }

        let target = Self.target(from: band, speed: speed)
        if wasSearching {
            band = target
            candidate = nil
        } else if target == band {
            candidate = nil
        } else {
            candidateCount = candidate == target ? candidateCount + 1 : 1
            candidate = target
            if candidateCount >= Self.debounceSamples {
                band = target
                candidate = nil
            }
        }
        return resolve(at: time)
    }

    /// Time passes without a sample: sleepy may start and startled may end.
    mutating func tick(at time: Date) -> Mood {
        resolve(at: time)
    }

    /// The live reading is gone. Immediate, and it clears everything.
    mutating func lost() -> Mood {
        self = MoodResolver()
        return mood
    }

    // MARK: Private

    private static func target(from band: Band, speed: Double) -> Band {
        switch band {
        case .calm:
            speed >= worriedEnterMetersPerSecond ? .worried : speed >= happyEnterMetersPerSecond ? .happy : .calm
        case .happy:
            speed >= worriedEnterMetersPerSecond ? .worried : speed < happyExitMetersPerSecond ? .calm : .happy
        case .worried:
            speed < happyExitMetersPerSecond ? .calm : speed < worriedExitMetersPerSecond ? .happy : .worried
        }
    }

    private mutating func resolve(at time: Date) -> Mood {
        // Nothing live since `lost()`: time passing changes nothing.
        guard last != nil else { return mood }
        if let until = startledUntil {
            if time < until {
                mood = .startled
                return mood
            }
            // Startled is over: show the current speed's mood right away, with no further debounce.
            startledUntil = nil
            if let candidate {
                band = candidate
                self.candidate = nil
            }
        }
        if let since = stoppedSince, time.timeIntervalSince(since) >= Self.sleepyAfter {
            mood = .sleepy
        } else {
            mood = band.mood
        }
        return mood
    }

    static func == (lhs: MoodResolver, rhs: MoodResolver) -> Bool {
        lhs.mood == rhs.mood && lhs.band == rhs.band && lhs.stoppedSince == rhs.stoppedSince && lhs.startledUntil == rhs.startledUntil
    }
}
