import XCTest
@testable import Xpeet

final class MoodResolverTests: XCTestCase {
    private var resolver = MoodResolver()
    private var time = Date(timeIntervalSince1970: 1_000)

    /// Feeds one sample per second at the given km/h values and returns the mood after each.
    @discardableResult
    private func drive(_ kmh: [Double], every seconds: TimeInterval = 1) -> [Mood] {
        kmh.map { speed in
            time += seconds
            return resolver.sample(metersPerSecond: speed / 3.6, at: time)
        }
    }

    // MARK: - R1

    func testMoodCases() {
        XCTAssertEqual(Mood.allCases, [.searching, .sleepy, .calm, .happy, .worried, .startled])
    }

    // MARK: - R2

    func testNotLiveIsSearching() {
        XCTAssertEqual(resolver.mood, .searching)
        drive([50, 50])
        XCTAssertEqual(resolver.lost(), .searching)
        XCTAssertEqual(resolver.mood, .searching)
    }

    func testStoppedUnderTenSecondsIsCalm() {
        XCTAssertEqual(drive([0, 0, 0, 0, 0, 0, 0, 0, 0]).last, .calm)
    }

    func testStoppedTenSecondsIsSleepy() {
        drive([0])
        XCTAssertEqual(resolver.tick(at: time.addingTimeInterval(9.9)), .calm)
        XCTAssertEqual(resolver.tick(at: time.addingTimeInterval(10)), .sleepy)
    }

    func testSleepyOnSampleAfterTenSeconds() {
        drive([0])
        XCTAssertEqual(drive([0], every: 10).last, .sleepy)
    }

    func testMovingAgainWakesUp() {
        drive([0])
        _ = resolver.tick(at: time.addingTimeInterval(10))
        XCTAssertEqual(drive([5]).last, .calm)
    }

    func testSlowIsCalm() {
        XCTAssertEqual(drive([20, 20]).last, .calm)
    }

    // MARK: - R3

    func testHappyBandEdges() {
        XCTAssertEqual(drive([29.9, 29.9]).last, .calm)
        XCTAssertEqual(drive([30, 30]).last, .happy)
        XCTAssertEqual(drive([25, 25]).last, .happy, "stays happy until below 25")
        XCTAssertEqual(drive([24.9, 24.9]).last, .calm)
    }

    func testWorriedBandEdges() {
        XCTAssertEqual(drive([109.9, 109.9]).last, .happy)
        XCTAssertEqual(drive([110, 110]).last, .worried)
        XCTAssertEqual(drive([100, 100]).last, .worried, "stays worried until below 100")
        XCTAssertEqual(drive([99.9, 99.9]).last, .happy)
    }

    func testCalmJumpsStraightToWorried() {
        XCTAssertEqual(drive([10, 120, 120]).last, .worried)
    }

    func testOscillationAroundHappyDoesNotFlicker() {
        drive([32, 32])
        let moods = drive([28, 32, 28, 32, 28, 32, 28, 32])
        XCTAssertEqual(Set(moods), [.happy])
    }

    func testOscillationAroundWorriedDoesNotFlicker() {
        drive([112, 112])
        let moods = drive([105, 112, 105, 112, 105, 112])
        XCTAssertEqual(Set(moods), [.worried])
    }

    func testMoodIndependentOfUnit() {
        // 68 mph ≈ 109.4 km/h stays happy; 69 mph ≈ 111 km/h is worried. The resolver never sees a unit.
        XCTAssertEqual(drive([68 * 1.609_344, 68 * 1.609_344]).last, .happy)
        XCTAssertEqual(drive([69 * 1.609_344, 69 * 1.609_344]).last, .worried)
    }

    // MARK: - R4

    func testNewMoodNeedsTwoSamples() {
        drive([10, 10])
        XCTAssertEqual(drive([50]).last, .calm, "one sample is not enough")
        XCTAssertEqual(drive([50]).last, .happy)
    }

    func testInterruptedCandidateStartsOver() {
        drive([10, 10])
        // 35 -> 25 km/h in 1 s is 2.8 m/s², below the braking threshold.
        XCTAssertEqual(drive([35, 25, 35]).last, .calm)
        XCTAssertEqual(drive([35]).last, .happy)
    }

    func testSearchingIsImmediate() {
        drive([50, 50])
        XCTAssertEqual(resolver.lost(), .searching)
    }

    func testFirstMoodAfterSearchingIsImmediate() {
        XCTAssertEqual(drive([50]).last, .happy)
        _ = resolver.lost()
        XCTAssertEqual(drive([120]).last, .worried)
    }

    // MARK: - R5

    func testHardBrakingIsStartled() {
        drive([60, 60])
        // 60 -> 48 km/h in 1 s is 3.33 m/s².
        XCTAssertEqual(drive([48]).last, .startled)
    }

    func testGentleBrakingIsNotStartled() {
        drive([60, 60])
        // 60 -> 50 km/h in 1 s is 2.8 m/s².
        XCTAssertEqual(drive([50]).last, .happy)
    }

    func testBrakingUsesSampleInterval() {
        drive([60, 60])
        // Same drop over 2 s is only 1.7 m/s².
        XCTAssertEqual(drive([48], every: 2).last, .happy)
    }

    func testLongGapIsIgnored() {
        drive([100, 100])
        XCTAssertEqual(drive([0], every: 6).last, .happy, "a 6 s gap is never compared")
    }

    // MARK: - R6

    func testStartledExpiresAfterTwoSeconds() {
        drive([60, 60, 48])
        XCTAssertEqual(resolver.tick(at: time.addingTimeInterval(1.9)), .startled)
        XCTAssertEqual(resolver.tick(at: time.addingTimeInterval(2)), .happy)
    }

    func testAfterStartledNoExtraDebounce() {
        drive([60, 60])
        // Hard stop: 60 -> 20 -> 0. The band candidate (calm) is pending when startled ends.
        drive([20, 0])
        XCTAssertEqual(resolver.mood, .startled)
        XCTAssertEqual(resolver.tick(at: time.addingTimeInterval(2)), .calm)
    }

    func testRepeatedBrakingRestartsStartled() {
        drive([100, 100, 85])
        XCTAssertEqual(resolver.mood, .startled)
        drive([70])
        XCTAssertEqual(resolver.tick(at: time.addingTimeInterval(1.9)), .startled, "restarted from the second braking sample")
    }

    func testLostOverridesStartled() {
        drive([60, 60, 48])
        XCTAssertEqual(resolver.lost(), .searching)
        XCTAssertEqual(resolver.tick(at: time.addingTimeInterval(0.5)), .searching)
    }

    func testHardAccelerationNoReaction() {
        drive([10, 10])
        // 10 -> 40 km/h in 1 s is +8.3 m/s².
        XCTAssertEqual(drive([40]).last, .calm)
    }

    func testStartledOverridesSleepy() {
        drive([0])
        _ = resolver.tick(at: time.addingTimeInterval(10))
        XCTAssertEqual(resolver.mood, .sleepy)
        drive([40, 40])
        XCTAssertEqual(drive([25]).last, .startled)
    }

    // MARK: - Constants

    func testConstants() {
        XCTAssertEqual(MoodResolver.happyEnterMetersPerSecond, 30 / 3.6)
        XCTAssertEqual(MoodResolver.happyExitMetersPerSecond, 25 / 3.6)
        XCTAssertEqual(MoodResolver.worriedEnterMetersPerSecond, 110 / 3.6)
        XCTAssertEqual(MoodResolver.worriedExitMetersPerSecond, 100 / 3.6)
        XCTAssertEqual(MoodResolver.sleepyAfter, 10)
        XCTAssertEqual(MoodResolver.debounceSamples, 2)
        XCTAssertEqual(MoodResolver.brakeThreshold, 3)
        XCTAssertEqual(MoodResolver.brakeMaxInterval, 5)
        XCTAssertEqual(MoodResolver.startledDuration, 2)
    }
}
