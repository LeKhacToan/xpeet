import XCTest
@testable import Xpeet

final class CameraMathTests: XCTestCase {
    // MARK: - specs/osm-map R7

    func testMetersPerPointMatchesSlippyMapScale() {
        // 256-point tiles: about 40,075 km / 256 at zoom 0 on the equator. MapKit's own earth model is within 1% of
        // the slippy-map figure; calibration measures with the same model, so it stays consistent.
        let zoomZero = CameraMath.metersPerPoint(zoom: 0, latitude: 0)
        XCTAssertEqual(zoomZero, 156_543, accuracy: 1_566)
        XCTAssertEqual(CameraMath.metersPerPoint(zoom: 17, latitude: 0), zoomZero / 131_072, accuracy: 1e-9)
        let ratio = CameraMath.metersPerPoint(zoom: 17, latitude: 60) / CameraMath.metersPerPoint(zoom: 17, latitude: 0)
        XCTAssertEqual(ratio, 0.5, accuracy: 0.01, "Mercator about halves the ground per point at 60° (MapKit's ellipsoid)")
    }

    func testEachZoomLevelHalvesTheDistance() {
        let z16 = CameraMath.distance(zoom: 16, latitude: 45, viewHeight: 700, distancePerVisibleHeight: 1.866)
        let z17 = CameraMath.distance(zoom: 17, latitude: 45, viewHeight: 700, distancePerVisibleHeight: 1.866)

        XCTAssertEqual(z16 / z17, 2, accuracy: 1e-9)
    }
}
