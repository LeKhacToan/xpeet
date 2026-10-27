import XCTest
@testable import Xpeet

final class AccuracyReportTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 100)
    /// Metres per degree of latitude on the sphere `SpeedEstimator.distance` uses.
    private let metresPerDegree = 6_371_000.0 * Double.pi / 180

    /// Fixes 1 s apart, heading north at `speeds[i]` m/s; positions follow the speeds.
    private func northbound(_ speeds: [Double], horizontalAccuracy: Double = 5) -> [DriveEvent] {
        var latitude = 0.0
        return speeds.enumerated().map { index, speed in
            if index > 0 { latitude += speeds[index - 1] / metresPerDegree }
            let time = start + TimeInterval(index)
            let fix = SpeedSample(
                metersPerSecond: speed, accuracy: 0.4, isStationary: false, timestamp: time,
                latitude: latitude, longitude: 0, horizontalAccuracy: horizontalAccuracy
            )
            return .fix(fix, arrival: time + 0.2)
        }
    }

    // MARK: - specs/speed-accuracy R29

    func testSteadyStretchDistanceMatchesSpeed() throws {
        let report = AccuracyReport(drive: DriveFile(name: "north", events: northbound(Array(repeating: 25, count: 200))))

        let stretch = try XCTUnwrap(report.steadyStretches.first)
        XCTAssertEqual(report.steadyStretches.count, 1)
        XCTAssertEqual(stretch.distance, 25 * 199, accuracy: 1)
        XCTAssertEqual(stretch.distanceSpeed, 25, accuracy: 0.01)
        XCTAssertEqual(stretch.meanDoppler, 25, accuracy: 0.01)
    }

    func testShortOrUnsteadyDrivesHaveNoStretch() {
        let short = AccuracyReport(drive: DriveFile(name: "short", events: northbound(Array(repeating: 25, count: 60))))
        let alternating = (0..<200).map { $0.isMultiple(of: 2) ? 22.0 : 28 }
        let unsteady = AccuracyReport(drive: DriveFile(name: "unsteady", events: northbound(alternating)))

        XCTAssertEqual(short.steadyStretches, [], "1.5 km is too short")
        XCTAssertEqual(unsteady.steadyStretches, [], "±12% is not steady")
    }

    // MARK: - R30

    func testGapWhileMovingIsFound() throws {
        var events = northbound(Array(repeating: 20, count: 5))
        let resumed = SpeedSample(metersPerSecond: 19, accuracy: 0.4, isStationary: false, timestamp: start + 8,
                                  latitude: 0.001, longitude: 0, horizontalAccuracy: 12)
        events.append(.unavailable(arrival: start + 6))
        events.append(.fix(resumed, arrival: start + 8.2))

        let gap = try XCTUnwrap(AccuracyReport(drive: DriveFile(name: "tunnel", events: events)).gaps.first)

        XCTAssertEqual(gap.duration, 4, accuracy: 1e-9)
        XCTAssertTrue(gap.reportedUnavailable)
        XCTAssertEqual(gap.accuracyAfter, 12)
    }

    func testMissingSpeedCountsUsableFixes() {
        var events = northbound([20, 20, 20])
        let noDoppler = SpeedSample(metersPerSecond: -1, accuracy: -1, isStationary: false, timestamp: start + 4,
                                    latitude: 0.0007, longitude: 0, horizontalAccuracy: 5)
        let noDopplerPoorPosition = SpeedSample(metersPerSecond: -1, accuracy: -1, isStationary: false, timestamp: start + 5,
                                                latitude: 0.0009, longitude: 0, horizontalAccuracy: 65)
        events.append(.fix(noDoppler, arrival: start + 4))
        events.append(.fix(noDopplerPoorPosition, arrival: start + 5))

        let missing = AccuracyReport(drive: DriveFile(name: "wifi", events: events)).missingSpeed

        XCTAssertEqual(missing.count, 2)
        XCTAssertEqual(missing.usable, 1)
        XCTAssertEqual(missing.total, 5)
    }

    func testPercentiles() throws {
        let spread = try XCTUnwrap(AccuracyReport.percentiles((1...100).map(Double.init)))

        XCTAssertEqual(spread.median, 51)
        XCTAssertEqual(spread.p95, 95)
    }

    // MARK: - trip-stats R18

    func testTripDistanceMatchesPositionsOnStraightDrive() {
        var events = northbound(Array(repeating: 25, count: 200))
        // What the app showed at each fix: Live, with the GPS-only estimate behind the number.
        events += (0..<200).map { index in
            .shown(DriveShown(
                time: start + TimeInterval(index) + 0.2, displayed: 90, unit: "kmh", state: "live", source: .gpsOnly,
                gpsOnly: .init(metersPerSecond: 25, sigma: 0.3), fused: nil, inGap: false
            ))
        }
        events.sort { lineTime($0) < lineTime($1) }
        let report = AccuracyReport(drive: DriveFile(name: "north", events: events))

        let (trip, positions) = report.tripAndPositionDistance
        XCTAssertEqual(positions, 25 * 199, accuracy: 1)
        XCTAssertEqual(trip, positions, accuracy: positions * 0.005)
    }

    func testGapIsLeftOutOnBothSides() {
        // 100 s north at 25 m/s, a 30 s tunnel (no fixes; the app holds the speed for 5 s, then "--"), 100 s more.
        let before = northbound(Array(repeating: 25, count: 100))
        let after = northbound(Array(repeating: 25, count: 231)).suffix(100)
        var events = before + after
        for second in stride(from: 0.0, through: 230.5, by: 0.5) {
            let inGap = second > 99 && second < 131
            let held = second > 99 && second <= 104
            let state = inGap && !held ? "acquiring" : "live"
            events.append(.shown(DriveShown(
                time: start + second + 0.2, displayed: state == "live" ? 90 : nil, unit: "kmh", state: state,
                source: state == "live" ? .gpsOnly : nil,
                gpsOnly: state == "live" ? .init(metersPerSecond: 25, sigma: 0.3) : nil, fused: nil, inGap: inGap
            )))
        }
        events.sort { lineTime($0) < lineTime($1) }

        let (trip, positions) = AccuracyReport(drive: DriveFile(name: "tunnel", events: events)).tripAndPositionDistance

        XCTAssertEqual(positions, 25 * 99 * 2, accuracy: 1)
        XCTAssertEqual(trip, positions, accuracy: positions * 0.005, "the held 5 s at the tunnel mouth is not counted")
    }

    private func lineTime(_ event: DriveEvent) -> Date {
        switch event {
        case .header(let header): header.startedAt
        case .fix(_, let arrival), .unavailable(let arrival), .motion(_, let arrival): arrival
        case .shown(let shown): shown.time
        }
    }

    // MARK: - On recorded drives (skipped until some are pulled into build/drives)

    func testTripDistanceAgainstPositions() throws {
        let drives = DriveFile.files(in: DriveFile.recordedDrivesDirectory)
        try XCTSkipIf(drives.isEmpty, "No recorded drives in build/drives.")

        for url in drives {
            let (trip, positions) = AccuracyReport(drive: try DriveFile.load(url)).tripAndPositionDistance
            guard positions >= 5_000 else { continue }
            // R18: within 2% on drives of at least 5 km.
            XCTAssertEqual(trip, positions, accuracy: positions * 0.02, url.lastPathComponent)
        }
    }

    func testReportOnRecordedDrives() throws {
        let drives = DriveFile.files(in: DriveFile.recordedDrivesDirectory)
        try XCTSkipIf(drives.isEmpty, "No recorded drives in build/drives (record with RECORD=1 scripts/install-device.sh).")

        let report = try drives.map { try AccuracyReport(drive: DriveFile.load($0)).text }.joined(separator: "\n\n")

        let output = DriveFile.recordedDrivesDirectory.appendingPathComponent("report.txt")
        try report.write(to: output, atomically: true, encoding: .utf8)
        print(report)
    }

    func testDistanceOverTime() throws {
        let drives = DriveFile.files(in: DriveFile.recordedDrivesDirectory)
        try XCTSkipIf(drives.isEmpty, "No recorded drives in build/drives.")

        for url in drives {
            for stretch in AccuracyReport(drive: try DriveFile.load(url)).steadyStretches {
                print(String(format: "%@: %.1f km, distance/time %.2f km/h, Doppler %.2f km/h",
                             url.lastPathComponent, stretch.distance / 1000, stretch.distanceSpeed * 3.6, stretch.meanDoppler * 3.6))
            }
        }
    }
}
