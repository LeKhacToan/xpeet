import XCTest
@testable import Xpeet

final class MascotPlacementTests: XCTestCase {
    // MARK: - R12 size

    func testSizeIsEighteenPercentClamped() {
        XCTAssertEqual(MascotPlacement.size(gaugeDiameter: 200), 44, "floor")
        XCTAssertEqual(MascotPlacement.size(gaugeDiameter: 300), 54)
        XCTAssertEqual(MascotPlacement.size(gaugeDiameter: 450), 81)
        XCTAssertEqual(MascotPlacement.size(gaugeDiameter: 500), 84, "ceiling")
    }

    // MARK: - R12 placement

    func testPortraitPlacesMascotCentredAboveGauge() {
        // iPhone 15 portrait content area, roughly.
        let frame = MascotPlacement.frame(in: CGSize(width: 361, height: 690))
        XCTAssertNotNil(frame)
        guard let frame else { return }
        XCTAssertEqual(frame.width, 361 * 0.18, accuracy: 0.001)
        XCTAssertEqual(frame.midX, 361 / 2, accuracy: 0.001)
        // Bottom edge sits `gap` above the gauge's top edge: (690 - 361) / 2 = 164.5.
        XCTAssertEqual(frame.maxY, 164.5 - MascotPlacement.gap, accuracy: 0.001)
    }

    func testLandscapePlacesMascotLeadingOfGauge() {
        let frame = MascotPlacement.frame(in: CGSize(width: 770, height: 330))
        XCTAssertNotNil(frame)
        guard let frame else { return }
        XCTAssertEqual(frame.midY, 330 / 2, accuracy: 0.001)
        // Trailing edge sits `gap` before the gauge's leading edge: (770 - 330) / 2 = 220.
        XCTAssertEqual(frame.maxX, 220 - MascotPlacement.gap, accuracy: 0.001)
    }

    func testSmallPortraitStillFits() {
        // iPhone SE (1st gen) content area: 288 wide leaves 116 pt above a 288 pt gauge.
        XCTAssertNotNil(MascotPlacement.frame(in: CGSize(width: 288, height: 520)))
    }

    func testHiddenWhenNoRoom() {
        XCTAssertNil(MascotPlacement.frame(in: CGSize(width: 300, height: 320)), "10 pt above the gauge")
        XCTAssertNil(MascotPlacement.frame(in: CGSize(width: 340, height: 300)), "20 pt beside the gauge")
    }

    func testMascotNeverOverlapsGauge() {
        for size in [CGSize(width: 361, height: 690), CGSize(width: 770, height: 330), CGSize(width: 288, height: 520)] {
            guard let frame = MascotPlacement.frame(in: size) else { continue }
            let diameter = min(size.width, size.height)
            let gauge = CGRect(x: (size.width - diameter) / 2, y: (size.height - diameter) / 2, width: diameter, height: diameter)
            XCTAssertFalse(frame.intersects(gauge), "\(size)")
            XCTAssertTrue(CGRect(origin: .zero, size: size).contains(frame), "inside the container \(size)")
        }
    }
}
