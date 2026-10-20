import XCTest
@testable import Xpeet

final class MascotPlacementTests: XCTestCase {
    // MARK: - ui-redesign R5 size

    func testSizeIsTwentyTwoPercentClamped() {
        XCTAssertEqual(MascotPlacement.size(gaugeDiameter: 180), 44, "floor")
        XCTAssertEqual(MascotPlacement.size(gaugeDiameter: 300), 66, accuracy: 0.001)
        XCTAssertEqual(MascotPlacement.size(gaugeDiameter: 400), 88, accuracy: 0.001)
        XCTAssertEqual(MascotPlacement.size(gaugeDiameter: 500), 96, "ceiling")
    }

    // MARK: - R12 placement

    func testPortraitPlacesMascotCentredAboveGauge() {
        // iPhone 15 portrait content area, roughly.
        let frame = MascotPlacement.frame(in: CGSize(width: 361, height: 690))
        XCTAssertNotNil(frame)
        guard let frame else { return }
        XCTAssertEqual(frame.width, 361 * 0.22, accuracy: 0.001)
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
        // Gauge areas below the reserved 76 pt top row (ui-redesign R7).
        // iPhone SE (2nd/3rd gen): 343 x 563 leaves 110 pt above a 343 pt gauge for a 75 pt badge.
        let seFrame = MascotPlacement.frame(in: CGSize(width: 343, height: 563))
        XCTAssertEqual(seFrame?.width ?? 0, 343 * 0.22, accuracy: 0.001)
        // iPhone SE (1st gen): 288 x 444 leaves 78 pt above a 288 pt gauge for a 63 pt badge.
        XCTAssertNotNil(MascotPlacement.frame(in: CGSize(width: 288, height: 444)))
    }

    func testShrinksToFitBeforeHiding() {
        // iPhone SE, Denied: the Open Settings inset leaves about 58 pt above the gauge.
        let frame = MascotPlacement.frame(in: CGSize(width: 343, height: 459))
        XCTAssertEqual(frame?.width ?? 0, 58 - MascotPlacement.gap, accuracy: 0.001, "shrunk from 75 pt to the free space")
        XCTAssertEqual(frame?.minY ?? -1, 0, accuracy: 0.001)
        // Below the 44 pt floor it hides.
        XCTAssertNil(MascotPlacement.frame(in: CGSize(width: 343, height: 343 + 2 * 51)))
    }

    func testHiddenWhenNoRoom() {
        XCTAssertNil(MascotPlacement.frame(in: CGSize(width: 300, height: 320)), "10 pt above the gauge")
        XCTAssertNil(MascotPlacement.frame(in: CGSize(width: 340, height: 300)), "20 pt beside the gauge")
    }

    func testMascotNeverOverlapsGauge() {
        for size in [CGSize(width: 361, height: 690), CGSize(width: 770, height: 330), CGSize(width: 343, height: 563), CGSize(width: 288, height: 444), CGSize(width: 343, height: 459)] {
            guard let frame = MascotPlacement.frame(in: size) else { continue }
            let diameter = min(size.width, size.height)
            let gauge = CGRect(x: (size.width - diameter) / 2, y: (size.height - diameter) / 2, width: diameter, height: diameter)
            XCTAssertFalse(frame.intersects(gauge), "\(size)")
            XCTAssertTrue(CGRect(origin: .zero, size: size).contains(frame), "inside the container \(size)")
        }
    }
}
