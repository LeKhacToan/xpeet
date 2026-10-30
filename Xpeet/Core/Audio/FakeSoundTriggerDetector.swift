#if DEBUG
import Foundation

/// In-memory `SoundTriggerDetector` for previews and unit tests.
@MainActor
final class FakeSoundTriggerDetector: SoundTriggerDetector {
    private(set) var authorization: MicAuthorization
    private(set) var requestAuthorizationCount = 0
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    /// Answer given when authorization is requested; nil leaves it undetermined.
    var grantOnRequest: MicAuthorization?
    /// Return an already-finished events stream, as a detector that could not start would.
    var failOnStart = false

    private var authorizationContinuations: [UUID: AsyncStream<MicAuthorization>.Continuation] = [:]
    private var eventContinuations: [UUID: AsyncStream<SoundTriggerEvent>.Continuation] = [:]

    var eventSubscriberCount: Int { eventContinuations.count }

    init(authorization: MicAuthorization = .authorized, grantOnRequest: MicAuthorization? = nil) {
        self.authorization = authorization
        self.grantOnRequest = grantOnRequest
    }

    func authorizationUpdates() -> AsyncStream<MicAuthorization> {
        let (stream, continuation) = AsyncStream.makeStream(of: MicAuthorization.self)
        let id = UUID()
        authorizationContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.authorizationContinuations[id] = nil }
        }
        continuation.yield(authorization)
        return stream
    }

    func requestAuthorization() {
        requestAuthorizationCount += 1
        if let grantOnRequest { send(grantOnRequest) }
    }

    func events() -> AsyncStream<SoundTriggerEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: SoundTriggerEvent.self)
        if failOnStart {
            continuation.finish()
            return stream
        }
        let id = UUID()
        eventContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.eventContinuations[id] = nil }
        }
        return stream
    }

    func pause() { pauseCount += 1 }
    func resume() { resumeCount += 1 }

    func send(_ authorization: MicAuthorization) {
        self.authorization = authorization
        authorizationContinuations.values.forEach { $0.yield(authorization) }
    }

    func send(_ event: SoundTriggerEvent) {
        eventContinuations.values.forEach { $0.yield(event) }
    }

    /// Ends the events stream as a failing detector would.
    func finishEvents() {
        eventContinuations.values.forEach { $0.finish() }
    }
}

/// In-memory `SoundPlayer`: records what was played and finishes only when the test says so.
@MainActor
final class FakeSoundPlayer: SoundPlayer {
    private(set) var played: [SoundFile] = []
    /// Plays cut off by task cancellation, as the real player stops when its task is cancelled.
    private(set) var cancelCount = 0
    private var pending: CheckedContinuation<Void, Error>?

    var isPlaying: Bool { pending != nil }

    func play(_ file: SoundFile) async throws {
        played.append(file)
        try await withTaskCancellationHandler(operation: {
            try await self.waitForPlayback()
        }, onCancel: {
            Task { @MainActor in self.stopForCancellation() }
        })
    }

    private func waitForPlayback() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            if Task.isCancelled {
                cancelCount += 1
                continuation.resume(throwing: CancellationError())
            } else {
                pending = continuation
            }
        }
    }

    private func stopForCancellation() {
        guard pending != nil else { return }
        cancelCount += 1
        cancelPlayback()
    }

    func finishPlayback() {
        pending?.resume()
        pending = nil
    }

    func failPlayback() {
        pending?.resume(throwing: SoundPlayerError.couldNotPlay)
        pending = nil
    }

    /// As the real player does when its task is cancelled mid-sound.
    func cancelPlayback() {
        pending?.resume(throwing: CancellationError())
        pending = nil
    }
}
#endif
