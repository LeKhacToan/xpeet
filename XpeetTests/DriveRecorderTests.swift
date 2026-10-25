import XCTest
@testable import Xpeet

/// Collects events in memory. Locked, because `record` may be called from any thread.
final class SpyDriveLog: DriveLogging, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [DriveEvent] = []
    private var finished = false

    var events: [DriveEvent] { lock.withLock { recorded } }
    var isFinished: Bool { lock.withLock { finished } }

    func record(_ event: DriveEvent) {
        lock.withLock { if !finished { recorded.append(event) } }
    }

    func finish() {
        lock.withLock { finished = true }
    }
}

/// A sink whose every write fails.
final class FailingDriveSink: DriveSink, @unchecked Sendable {
    private let lock = NSLock()
    private var closedWithKeep: Bool?

    var closed: Bool? { lock.withLock { closedWithKeep } }

    func write(_ data: Data) throws {
        throw CocoaError(.fileWriteOutOfSpace)
    }

    func close(keep: Bool) {
        lock.withLock { closedWithKeep = keep }
    }
}

final class DriveRecorderTests: XCTestCase {
    private var directory: URL!
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DriveRecorderTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var fix: SpeedSample {
        SpeedSample(
            metersPerSecond: 13.5, accuracy: 0.4, isStationary: false, timestamp: start,
            latitude: 10.5, longitude: 106.25, horizontalAccuracy: 4, course: 90, courseAccuracy: 5
        )
    }

    // MARK: - specs/speed-accuracy R22

    func testOffWithoutLaunchArgument() throws {
        let name = "DriveRecorderTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        XCTAssertFalse(DriveRecorder.isEnabled(in: defaults))
        XCTAssertNil(DriveRecorder.startIfEnabled(defaults: defaults))

        defaults.set(true, forKey: DriveRecorder.launchArgumentKey)
        XCTAssertTrue(DriveRecorder.isEnabled(in: defaults))
    }

    func testWritesAllLineTypes() async throws {
        let recorder = try XCTUnwrap(DriveRecorder.start(in: directory, now: start))
        let motion = MotionSample(
            timestamp: 120.25,
            userAcceleration: Vector3(x: 0.5, y: 0, z: -0.25),
            gravity: Vector3(x: 0, y: 0, z: -1),
            rotationRate: .zero
        )
        let shown = DriveShown(
            time: start + 1, displayed: 49, unit: "kmh", state: "live", source: .gpsOnly,
            gpsOnly: .init(metersPerSecond: 13.5, sigma: 0.25), fused: nil, inGap: false
        )
        let events: [DriveEvent] = [
            .header(DriveHeader(startedAt: start, device: "iPhone", system: "26", constants: ["k": 1])),
            .fix(fix, arrival: start + 0.5),
            .unavailable(arrival: start + 0.75),
            .motion(motion, arrival: start + 0.5),
            .shown(shown),
        ]

        events.forEach(recorder.record)
        await recorder.waitUntilClosed()

        let file = try XCTUnwrap(try DriveRecorder.recordings(in: directory).first)
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        let decoder = DriveEvent.makeDecoder()
        let decoded = try lines.map { try decoder.decode(DriveEvent.self, from: Data($0.utf8)) }
        XCTAssertEqual(decoded, events)
    }

    func testFileNameSortsByStartTime() {
        XCTAssertEqual(DriveRecorder.fileName(for: start), "20270115-080000-000.jsonl")
    }

    func testKeepsFiveNewestByName() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let old = (1...6).map { "20260101-00000\($0)-000.jsonl" }
        for name in old {
            FileManager.default.createFile(atPath: directory.appendingPathComponent(name).path, contents: Data("x".utf8))
        }

        let recorder = try XCTUnwrap(DriveRecorder.start(in: directory, now: start))
        recorder.record(.fix(fix, arrival: start))
        await recorder.waitUntilClosed()

        let names = try DriveRecorder.recordings(in: directory).map(\.lastPathComponent)
        XCTAssertEqual(names, Array(old.suffix(4)) + [DriveRecorder.fileName(for: start)])
    }

    func testRecordingWithoutFixIsDeleted() async throws {
        let recorder = try XCTUnwrap(DriveRecorder.start(in: directory, now: start))
        recorder.record(.header(DriveHeader(startedAt: start, device: "iPhone", system: "26", constants: [:])))

        await recorder.waitUntilClosed()

        XCTAssertEqual(try DriveRecorder.recordings(in: directory), [])
    }

    // MARK: - R23

    func testWriteFailureStopsSilently() async {
        let sink = FailingDriveSink()
        let recorder = DriveRecorder(sink: sink)

        for _ in 0..<200 { recorder.record(.fix(fix, arrival: start)) }
        await recorder.waitUntilClosed()
        recorder.record(.unavailable(arrival: start))

        XCTAssertNotNil(sink.closed, "the writer ended instead of hanging or crashing")
    }
}
