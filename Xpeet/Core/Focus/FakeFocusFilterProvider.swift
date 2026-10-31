#if DEBUG
import Foundation

/// In-memory `FocusFilterProvider` for previews and unit tests.
@MainActor
final class FakeFocusFilterProvider: FocusFilterProvider {
    /// Each new stream's first value; nil holds it back until `send(_:)`, like a slow read of `current`.
    private let initialOverride: Bool?
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    var subscriberCount: Int { continuations.count }

    init(initialOverride: Bool? = nil) {
        self.initialOverride = initialOverride
    }

    func updates() -> AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self)
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations[id] = nil }
        }
        if let initialOverride { continuation.yield(initialOverride) }
        return stream
    }

    /// A `perform()`, or a held-back first value arriving.
    func send(_ override: Bool) {
        continuations.values.forEach { $0.yield(override) }
    }
}
#endif
