import XCTest
@testable import Xpeet

/// The mapping from a read of the Focus filter's `current` value to the override (specs/engine-clip-toggle R17).
final class FocusFilterOverrideTests: XCTestCase {
    private struct NotFound: Error {}

    func testAValueIsTheOverride() {
        XCTAssertTrue(FocusFilterOverride.from(.success(true)))
        XCTAssertFalse(FocusFilterOverride.from(.success(false)))
    }

    func testAThrownReadIsNoOverride() {
        XCTAssertFalse(FocusFilterOverride.from(.failure(NotFound())))
    }

    func testATimedOutReadIsNoOverride() {
        XCTAssertFalse(FocusFilterOverride.from(nil))
    }
}
