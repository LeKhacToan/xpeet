import XCTest
@testable import Xpeet

final class HomeViewModelTests: XCTestCase {
    func testIncrementUpdatesMessage() {
        let viewModel = HomeViewModel()
        XCTAssertEqual(viewModel.message, "Welcome to Xpeet")

        viewModel.increment()
        XCTAssertEqual(viewModel.message, "Tapped 1 time")
    }
}
