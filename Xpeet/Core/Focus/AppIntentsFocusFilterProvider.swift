import AppIntents

/// Production `FocusFilterProvider`: reads `EngineSoundsFocusFilter.current` once per stream, then relays each
/// `perform()` (specs/engine-clip-toggle R17).
@MainActor
final class AppIntentsFocusFilterProvider: FocusFilterProvider {
    /// A read of `current` that takes longer counts as no override. How long it takes is undocumented, and the R14
    /// spike didn't measure it.
    nonisolated static let currentReadTimeout: Duration = .seconds(2)

    private let read: @Sendable @MainActor () async throws -> Bool
    private let timeout: Duration
    private let relay: FocusFilterRelay?

    /// `read`, `timeout` and `relay` are for tests; `relay` nil means the shared one.
    nonisolated init(
        read: @escaping @Sendable @MainActor () async throws -> Bool = { try await EngineSoundsFocusFilter.current.turnOff },
        timeout: Duration = currentReadTimeout,
        relay: FocusFilterRelay? = nil
    ) {
        self.read = read
        self.timeout = timeout
        self.relay = relay
    }

    func updates() -> AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self, bufferingPolicy: .bufferingNewest(1))
        let relay = relay ?? .shared
        let delivery = Delivery()
        let id = relay.add { turnOff in
            delivery.performed = true
            continuation.yield(turnOff)
        }
        let first = Task { @MainActor in
            let override = await readCurrent()
            // A `perform()` that arrived meanwhile is newer than this read.
            if !delivery.performed { continuation.yield(override) }
        }
        continuation.onTermination = { _ in
            first.cancel()
            Task { @MainActor in relay.remove(id) }
        }
        return stream
    }

    /// The filter's value now, or no override if the read throws, takes longer than `timeout`, or is cancelled.
    private func readCurrent() async -> Bool {
        let once = ResumeOnce()
        let read = read, timeout = timeout
        let result: Result<Bool, Error>? = await withTaskCancellationHandler {
            await withCheckedContinuation { done in
                once.continuation = done
                // Not a task group: a group would wait for a read that never returns. The loser is cancelled; a
                // hung read stops only if AppIntents honours cancellation.
                once.tasks = [
                    Task { @MainActor in
                        do {
                            once.resume(.success(try await read()))
                        } catch {
                            once.resume(.failure(error))
                        }
                    },
                    Task { @MainActor in
                        try? await Task.sleep(for: timeout)
                        once.resume(nil)
                    },
                ]
            }
        } onCancel: {
            Task { @MainActor in once.resume(nil) }
        }
        return FocusFilterOverride.from(result)
    }
}

@MainActor
private final class Delivery {
    var performed = false
}

/// Resumes its continuation with the first value only, then cancels the racing tasks.
@MainActor
private final class ResumeOnce {
    var continuation: CheckedContinuation<Result<Bool, Error>?, Never>?
    var tasks: [Task<Void, Never>] = []

    func resume(_ read: Result<Bool, Error>?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: read)
        tasks.forEach { $0.cancel() }
    }
}
