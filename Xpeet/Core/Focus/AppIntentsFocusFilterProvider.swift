import AppIntents

/// Production `FocusFilterProvider`: reads `EngineSoundsFocusFilter.current` once per stream, then relays each
/// `perform()` (specs/engine-clip-toggle R17).
@MainActor
final class AppIntentsFocusFilterProvider: FocusFilterProvider {
    /// A read of `current` that takes longer counts as no override. How long it takes is undocumented, and the R14
    /// spike didn't measure it.
    static let currentReadTimeout: Duration = .seconds(2)

    nonisolated init() {}

    func updates() -> AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self, bufferingPolicy: .bufferingNewest(1))
        let relay = FocusFilterRelay.shared
        let delivery = Delivery()
        let id = relay.add { turnOff in
            delivery.performed = true
            continuation.yield(turnOff)
        }
        let read = Task { @MainActor in
            let override = await Self.readCurrent()
            // A `perform()` that arrived meanwhile is newer than this read.
            if !delivery.performed { continuation.yield(override) }
        }
        continuation.onTermination = { _ in
            read.cancel()
            Task { @MainActor in relay.remove(id) }
        }
        return stream
    }

    /// The filter's value now, or no override if the read throws or takes longer than `currentReadTimeout`.
    private static func readCurrent() async -> Bool {
        let timeout = currentReadTimeout
        let read: Result<Bool, Error>? = await withCheckedContinuation { done in
            let once = ResumeOnce(done)
            Task { @MainActor in
                do {
                    once.resume(.success(try await EngineSoundsFocusFilter.current.turnOff))
                } catch {
                    once.resume(.failure(error))
                }
            }
            // Not a task group: a group would wait for a read that never returns.
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                once.resume(nil)
            }
        }
        return FocusFilterOverride.from(read)
    }
}

@MainActor
private final class Delivery {
    var performed = false
}

/// Resumes its continuation with the first value only.
@MainActor
private final class ResumeOnce {
    private var continuation: CheckedContinuation<Result<Bool, Error>?, Never>?

    init(_ continuation: CheckedContinuation<Result<Bool, Error>?, Never>) {
        self.continuation = continuation
    }

    func resume(_ read: Result<Bool, Error>?) {
        continuation?.resume(returning: read)
        continuation = nil
    }
}
