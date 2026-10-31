import XCTest
@testable import Xpeet

/// The production provider's first value and relay, with an injected read of `current`
/// (specs/engine-clip-toggle R17).
@MainActor
final class AppIntentsFocusFilterProviderTests: XCTestCase {
    private struct NotFound: Error {}

    private final class Flag {
        var isSet = false
    }

    /// Collects a stream's values until cancelled.
    private final class Collector {
        var values: [Bool] = []
        var task: Task<Void, Never>?

        init(_ stream: AsyncStream<Bool>) {
            task = Task { @MainActor [weak self] in
                for await value in stream { self?.values.append(value) }
            }
        }
    }

    private func waitUntil(timeout: TimeInterval = 2, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for condition", file: file, line: line)
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testTheReadIsTheFirstValue() async {
        let provider = AppIntentsFocusFilterProvider(read: { true }, relay: FocusFilterRelay())
        let collector = Collector(provider.updates())
        await waitUntil { collector.values == [true] }
        collector.task?.cancel()
    }

    func testAThrownReadIsNoOverride() async {
        let provider = AppIntentsFocusFilterProvider(read: { throw NotFound() }, relay: FocusFilterRelay())
        let collector = Collector(provider.updates())
        await waitUntil { collector.values == [false] }
        collector.task?.cancel()
    }

    func testAReadPastTheTimeoutIsNoOverrideAndIsCancelled() async {
        let cancelled = Flag()
        let provider = AppIntentsFocusFilterProvider(
            read: {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    cancelled.isSet = true
                    throw error
                }
                return true
            },
            timeout: .milliseconds(50),
            relay: FocusFilterRelay()
        )
        let collector = Collector(provider.updates())
        await waitUntil { collector.values == [false] }
        await waitUntil { cancelled.isSet }
        collector.task?.cancel()
    }

    func testAPerformBeatsASlowerRead() async {
        let relay = FocusFilterRelay()
        let provider = AppIntentsFocusFilterProvider(
            read: {
                try await Task.sleep(for: .milliseconds(200))
                return true
            },
            relay: relay
        )
        let collector = Collector(provider.updates())
        try? await Task.sleep(for: .milliseconds(20))
        relay.deliver(false)
        await waitUntil { collector.values == [false] }
        try? await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(collector.values, [false], "the older read is dropped")

        relay.deliver(true)
        await waitUntil { collector.values == [false, true] }
        collector.task?.cancel()
    }

    func testEndingTheStreamCancelsAPendingRead() async {
        let cancelled = Flag()
        let relay = FocusFilterRelay()
        let provider = AppIntentsFocusFilterProvider(
            read: {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    cancelled.isSet = true
                    throw error
                }
                return true
            },
            timeout: .seconds(60),
            relay: relay
        )
        let collector = Collector(provider.updates())
        try? await Task.sleep(for: .milliseconds(20))
        collector.task?.cancel()
        await waitUntil { cancelled.isSet }
    }
}
