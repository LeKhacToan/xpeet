#if DEBUG
import Foundation

/// In-memory `MotionProvider` for previews and unit tests. Sends nothing unless told to.
@MainActor
final class FakeMotionProvider: MotionProvider {
    private var continuations: [UUID: AsyncStream<[MotionSample]>.Continuation] = [:]
    private let isAvailable: Bool

    var subscriberCount: Int { continuations.count }

    /// `isAvailable: false` behaves like a device without motion sensors: every stream finishes at once.
    init(isAvailable: Bool = true) {
        self.isAvailable = isAvailable
    }

    func motionUpdates() -> AsyncStream<[MotionSample]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [MotionSample].self)
        guard isAvailable else {
            continuation.finish()
            return stream
        }
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations[id] = nil }
        }
        return stream
    }

    func send(_ batch: [MotionSample]) {
        continuations.values.forEach { $0.yield(batch) }
    }

    func finish() {
        continuations.values.forEach { $0.finish() }
    }
}
#endif
