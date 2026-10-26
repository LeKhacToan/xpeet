#if DEBUG
import Foundation

/// In-memory `SpeedProvider` for previews and unit tests.
@MainActor
final class FakeSpeedProvider: SpeedProvider {
    private(set) var authorization: LocationAuthorization
    private(set) var requestAuthorizationCount = 0
    private let initialSamples: [SpeedSample]
    private var authorizationContinuations: [UUID: AsyncStream<LocationAuthorization>.Continuation] = [:]
    private var sampleContinuations: [UUID: AsyncStream<LocationUpdate>.Continuation] = [:]

    var speedSubscriberCount: Int { sampleContinuations.count }

    init(authorization: LocationAuthorization = .authorized, samples: [SpeedSample] = []) {
        self.authorization = authorization
        self.initialSamples = samples
    }

    func authorizationUpdates() -> AsyncStream<LocationAuthorization> {
        let (stream, continuation) = AsyncStream.makeStream(of: LocationAuthorization.self)
        let id = UUID()
        authorizationContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.authorizationContinuations[id] = nil }
        }
        continuation.yield(authorization)
        return stream
    }

    func speedUpdates() -> AsyncStream<LocationUpdate> {
        let (stream, continuation) = AsyncStream.makeStream(of: LocationUpdate.self)
        let id = UUID()
        sampleContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.sampleContinuations[id] = nil }
        }
        initialSamples.forEach { continuation.yield(.fix($0)) }
        return stream
    }

    func requestAuthorization() {
        requestAuthorizationCount += 1
    }

    func send(_ authorization: LocationAuthorization) {
        self.authorization = authorization
        authorizationContinuations.values.forEach { $0.yield(authorization) }
    }

    func send(_ sample: SpeedSample) {
        sampleContinuations.values.forEach { $0.yield(.fix(sample)) }
    }

    func sendUnavailable() {
        sampleContinuations.values.forEach { $0.yield(.unavailable) }
    }
}
#endif
