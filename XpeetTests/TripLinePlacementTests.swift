import XCTest
@testable import Xpeet

final class TripLinePlacementTests: XCTestCase {
    // Real landscape gauge containers: the screen minus safe areas, 16 pt side padding and 8 pt top padding.
    private let iPhone15Pro = CGSize(width: 702, height: 364)
    private let iPhoneSE = CGSize(width: 635, height: 367)

    // MARK: - specs/trip-stats R12

    func testLandscapeTrailingFrame() throws {
        let frame = try XCTUnwrap(TripLinePlacement.frame(in: iPhone15Pro))

        // The gauge is the 364 pt square in the middle; 169 pt are free on each side.
        XCTAssertEqual(frame.minX, 702 - 169 + 8)
        XCTAssertEqual(frame.width, 169 - 16)
        XCTAssertEqual(frame.midY, 182, "vertically centred on the gauge")
        XCTAssertGreaterThanOrEqual(frame.minX, (702 + 364) / 2, "never over the gauge")
    }

    func testSmallestPhoneStillHasRoom() throws {
        let frame = try XCTUnwrap(TripLinePlacement.frame(in: iPhoneSE))

        XCTAssertEqual(frame.width, 118, "TripLine's last layout shrinks to fit this")
    }

    func testPortraitReturnsNil() {
        XCTAssertNil(TripLinePlacement.frame(in: CGSize(width: 361, height: 700)))
    }

    func testNoRoomReturnsNil() {
        XCTAssertNil(TripLinePlacement.frame(in: CGSize(width: 500, height: 340)), "80 pt beside the gauge is too narrow")
    }
}
