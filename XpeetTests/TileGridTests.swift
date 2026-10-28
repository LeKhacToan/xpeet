import MapKit
import XCTest
@testable import Xpeet

final class TileGridTests: XCTestCase {
    // MARK: - specs/osm-map R34

    func testZoomIsTheLevelWhoseTilesShowAtTheirOwnSize() {
        XCTAssertEqual(TileGrid.zoom(forScale: pow(2, -3)), 17)
        XCTAssertEqual(TileGrid.zoom(forScale: pow(2, -3) * 1.3), 17, "a little closer stays at 17")
        XCTAssertEqual(TileGrid.zoom(forScale: pow(2, -3) * 1.5), 18)
        XCTAssertEqual(TileGrid.zoom(forScale: pow(2, -3) * 0.8), 17, "a little farther stays at 17")
        XCTAssertEqual(TileGrid.zoom(forScale: 1e-9), 0)
        XCTAssertEqual(TileGrid.zoom(forScale: 100), 19)
    }

    func testATileRectCoversOnlyThatTile() {
        let key = TileKey(z: 17, x: 104_905, y: 59_597)

        XCTAssertEqual(TileGrid.keys(covering: TileGrid.mapRect(for: key), zoom: 17), [key])
    }

    func testKeysCoverEveryTouchedTile() {
        let first = TileGrid.mapRect(for: TileKey(z: 5, x: 10, y: 20))
        let last = TileGrid.mapRect(for: TileKey(z: 5, x: 11, y: 21))
        let rect = MKMapRect(x: first.midX, y: first.midY, width: last.midX - first.midX, height: last.midY - first.midY)

        let keys = TileGrid.keys(covering: rect, zoom: 5)

        XCTAssertEqual(Set(keys), [TileKey(z: 5, x: 10, y: 20), TileKey(z: 5, x: 11, y: 20),
                                   TileKey(z: 5, x: 10, y: 21), TileKey(z: 5, x: 11, y: 21)])
    }

    func testKeysStayInsideTheWorld() {
        let beyond = MKMapRect.world.insetBy(dx: -1_000, dy: -1_000)

        XCTAssertEqual(TileGrid.keys(covering: beyond, zoom: 1).count, 4)
    }

    func testAncestorsNearestFirstWithTheCoveredPart() {
        let ancestors = TileGrid.ancestors(of: TileKey(z: 17, x: 5, y: 6))

        XCTAssertEqual(ancestors.count, TileGrid.fallbackLevels)
        XCTAssertEqual(ancestors[0].key, TileKey(z: 16, x: 2, y: 3))
        XCTAssertEqual(ancestors[0].part, CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        XCTAssertEqual(ancestors[1].key, TileKey(z: 15, x: 1, y: 1))
        XCTAssertEqual(ancestors[1].part, CGRect(x: 0.25, y: 0.5, width: 0.25, height: 0.25))
        XCTAssertEqual(TileGrid.ancestors(of: TileKey(z: 2, x: 3, y: 1)).map(\.key), [TileKey(z: 1, x: 1, y: 0), TileKey(z: 0, x: 0, y: 0)])
    }

    func testChildrenAreTheFourTilesOneLevelDown() {
        XCTAssertEqual(Set(TileGrid.children(of: TileKey(z: 3, x: 1, y: 2))), [
            TileKey(z: 4, x: 2, y: 4), TileKey(z: 4, x: 3, y: 4), TileKey(z: 4, x: 2, y: 5), TileKey(z: 4, x: 3, y: 5),
        ])
        XCTAssertEqual(TileGrid.children(of: TileKey(z: 19, x: 0, y: 0)), [])
    }
}
