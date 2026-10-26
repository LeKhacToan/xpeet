import Foundation
@testable import Xpeet

/// One recorded drive: every line of a JSON Lines file written by `DriveRecorder` (specs/speed-accuracy R22, R26).
struct DriveFile {
    enum LoadError: Error, Equatable {
        /// A committed fixture still holds a real place or date (R31).
        case notAnonymised(line: Int)
    }

    /// Anonymised fixtures put the first fix at 0°, 0°, so every coordinate stays within this many degrees.
    static let fixtureMaxDegrees = 0.5
    /// ... and count time from 0, so every date stays within this many seconds of 1970.
    static let fixtureMaxSeconds: TimeInterval = 10_000_000

    let name: String
    let events: [DriveEvent]

    var header: DriveHeader? {
        events.lazy.compactMap { if case .header(let header) = $0 { header } else { nil } }.first
    }

    var fixes: [(sample: SpeedSample, arrival: Date)] {
        events.compactMap { if case let .fix(sample, arrival) = $0 { (sample, arrival) } else { nil } }
    }

    var motion: [(sample: MotionSample, arrival: Date)] {
        events.compactMap { if case let .motion(sample, arrival) = $0 { (sample, arrival) } else { nil } }
    }

    var shown: [DriveShown] {
        events.compactMap { if case .shown(let shown) = $0 { shown } else { nil } }
    }

    var unavailableArrivals: [Date] {
        events.compactMap { if case .unavailable(let arrival) = $0 { arrival } else { nil } }
    }

    static func load(_ url: URL, requireAnonymised: Bool = false) throws -> DriveFile {
        let decoder = DriveEvent.makeDecoder()
        var events: [DriveEvent] = []
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: true)
        for (index, line) in lines.enumerated() {
            let event = try decoder.decode(DriveEvent.self, from: Data(line.utf8))
            if requireAnonymised, !isAnonymised(event) { throw LoadError.notAnonymised(line: index + 1) }
            events.append(event)
        }
        return DriveFile(name: url.deletingPathExtension().lastPathComponent, events: events)
    }

    /// True when the event holds no real coordinate and no real date (R31).
    static func isAnonymised(_ event: DriveEvent) -> Bool {
        func relative(_ date: Date) -> Bool { abs(date.timeIntervalSince1970) < fixtureMaxSeconds }
        switch event {
        case .header(let header):
            return relative(header.startedAt)
        case let .fix(sample, arrival):
            return abs(sample.latitude) < fixtureMaxDegrees && abs(sample.longitude) < fixtureMaxDegrees
                && relative(sample.timestamp) && relative(arrival)
        case .unavailable(let arrival), .motion(_, let arrival):
            return relative(arrival)
        case .shown(let shown):
            return relative(shown.time)
        }
    }

    // MARK: Locations

    /// The repository root, found from this source file, so tests on the Simulator can read the Mac's files.
    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Full drives copied off the phone by `scripts/pull-drives.sh`. Gitignored: never committed.
    static let recordedDrivesDirectory = repositoryRoot.appendingPathComponent("build/drives", isDirectory: true)

    /// Trimmed, anonymised clips made by `scripts/make-fixture.py`. Committed.
    static let fixturesDirectory = repositoryRoot.appendingPathComponent("XpeetTests/Fixtures/Drives", isDirectory: true)

    /// `.jsonl` files in `directory`, by name; empty when the directory does not exist.
    static func files(in directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents.filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
