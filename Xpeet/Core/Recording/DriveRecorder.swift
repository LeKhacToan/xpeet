#if DEBUG
import Foundation

/// Debug-only drive recorder (specs/speed-accuracy R22-R23). Off unless the app is launched with
/// `-XpeetRecordDrives YES`. Each run of the speed screen writes one JSON Lines file to `Documents/Drives/`;
/// only the newest files are kept. Location traces never leave the phone unless copied off by hand (R24).
final class DriveRecorder: DriveLogging {
    static let launchArgumentKey = "XpeetRecordDrives"
    static let keptFiles = 5
    static let fileExtension = "jsonl"
    /// Lines are written in chunks, so 50 Hz motion does not mean 50 writes a second.
    static let linesPerWrite = 64

    private let continuation: AsyncStream<DriveEvent>.Continuation
    private let writer: Task<Void, Never>

    /// Records into `sink`. The writer runs off the main actor; a failing sink ends recording silently.
    init(sink: DriveSink) {
        let (events, continuation) = AsyncStream.makeStream(of: DriveEvent.self)
        self.continuation = continuation
        self.writer = Task.detached(priority: .utility) {
            let encoder = DriveEvent.makeEncoder()
            var pending = Data()
            var pendingLines = 0
            var wroteFix = false
            do {
                for await event in events {
                    if case .fix = event { wroteFix = true }
                    pending.append(try encoder.encode(event))
                    pending.append(0x0A)
                    pendingLines += 1
                    if pendingLines >= Self.linesPerWrite {
                        try sink.write(pending)
                        pending.removeAll(keepingCapacity: true)
                        pendingLines = 0
                    }
                }
                try sink.write(pending)
            } catch {
                continuation.finish()
            }
            // Opening the app without driving must not push a real drive out of the kept files.
            sink.close(keep: wroteFix)
        }
    }

    deinit {
        continuation.finish()
    }

    func record(_ event: DriveEvent) {
        continuation.yield(event)
    }

    func finish() {
        continuation.finish()
    }

    /// Waits until everything recorded so far is written and the file is closed. For tests.
    func waitUntilClosed() async {
        finish()
        await writer.value
    }

    // MARK: Starting

    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: launchArgumentKey)
    }

    /// A recorder writing a new file in `Documents/Drives/`, or nil when recording is off or the file can't be made.
    static func startIfEnabled(defaults: UserDefaults = .standard, now: Date = Date()) -> DriveRecorder? {
        guard isEnabled(in: defaults),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return start(in: documents.appendingPathComponent("Drives", isDirectory: true), now: now)
    }

    /// Makes room (keeping `keptFiles` including the new one), then opens a new file named by `now`.
    static func start(in directory: URL, now: Date) -> DriveRecorder? {
        let files = FileManager.default
        do {
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            for old in try recordings(in: directory).dropLast(keptFiles - 1) {
                try? files.removeItem(at: old)
            }
            let url = directory.appendingPathComponent(fileName(for: now))
            return DriveRecorder(sink: try FileDriveSink(url: url))
        } catch {
            return nil
        }
    }

    /// Recorded drives in `directory`, oldest first. Names start with the UTC start time, so name order is
    /// time order; file dates are not read.
    static func recordings(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == fileExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return "\(formatter.string(from: date)).\(fileExtension)"
    }
}

/// Where recorded bytes go. Used only from the recorder's writer task.
protocol DriveSink: Sendable {
    func write(_ data: Data) throws
    /// `keep: false` deletes what was written.
    func close(keep: Bool)
}

/// Appends to one file. `@unchecked Sendable`: only the recorder's single writer task touches it.
final class FileDriveSink: DriveSink, @unchecked Sendable {
    private let url: URL
    private let handle: FileHandle

    init(url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        self.url = url
        self.handle = try FileHandle(forWritingTo: url)
    }

    func write(_ data: Data) throws {
        guard !data.isEmpty else { return }
        try handle.write(contentsOf: data)
    }

    func close(keep: Bool) {
        try? handle.close()
        if !keep { try? FileManager.default.removeItem(at: url) }
    }
}
#endif
