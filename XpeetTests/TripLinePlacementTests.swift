import XCTest
@testable import Xpeet

final class TripLinePlacementTests: XCTestCase {
    // MARK: - specs/trip-stats R12

    func testLandscapeTrailingFrame() throws {
        // iPhone 15 Pro landscape content area: the gauge is a 340 pt square in the middle.
        let frame = try XCTUnwrap(TripLinePlacement.frame(in: CGSize(width: 844, height: 340)))

        XCTAssertEqual(frame.minX, 844 - 252 + 8)
        XCTAssertEqual(frame.width, 252 - 16)
        XCTAssertEqual(frame.midY, 170, "vertically centred on the gauge")
        XCTAssertGreaterThanOrEqual(frame.minX, (844 + 340) / 2, "never over the gauge")
    }

    func testPortraitReturnsNil() {
        XCTAssertNil(TripLinePlacement.frame(in: CGSize(width: 393, height: 700)))
    }

    func testNoRoomReturnsNil() {
        XCTAssertNil(TripLinePlacement.frame(in: CGSize(width: 500, height: 340)), "80 pt beside the gauge is too narrow")
        XCTAssertNotNil(TripLinePlacement.frame(in: CGSize(width: 667, height: 340)), "iPhone SE landscape still fits")
    }
}
