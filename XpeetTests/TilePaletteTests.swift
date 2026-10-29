import XCTest
@testable import Xpeet

/// The light map style (specs/osm-map R33), checked on OpenStreetMap Carto's own colours.
final class TilePaletteTests: XCTestCase {
    private func recoloured(_ hex: UInt32) -> (hue: Double, saturation: Double, lightness: Double) {
        TilePalette.hsl(TilePalette.recolor(colour(hex)))
    }

    private func colour(_ hex: UInt32) -> SIMD3<Double> {
        SIMD3(Double(hex >> 16 & 0xFF), Double(hex >> 8 & 0xFF), Double(hex & 0xFF)) / 255
    }

    // MARK: - specs/osm-map R33

    func testLandTurnsNearWhiteAndNeutral() {
        let land = recoloured(0xF2EFE9)

        XCTAssertGreaterThan(land.lightness, 0.95)
        XCTAssertLessThan(land.saturation, 0.15)
        XCTAssertEqual(TilePalette.recolor(colour(0xF2EFE9)), TilePalette.land)
    }

    func testMinorAndSecondaryRoadsAreWhite() {
        XCTAssertGreaterThan(recoloured(0xFFFFFF).lightness, 0.99, "residential and tertiary")
        XCTAssertGreaterThan(recoloured(0xF7FABF).lightness, 0.99, "secondary")
    }

    func testMajorRoadsTurnPaleAmber() {
        for (name, hex) in [("motorway", 0xE892A2), ("trunk", 0xF9B29C), ("primary", 0xFCD6A4)] as [(String, UInt32)] {
            let road = recoloured(hex)
            XCTAssertEqual(road.hue, 42, accuracy: 6, name)
            XCTAssertGreaterThan(road.saturation, 0.4, name)
            XCTAssertGreaterThan(road.lightness, 0.8, name)
        }
    }

    func testShopsAndOfficesStayNeutral() {
        XCTAssertLessThan(recoloured(0xFFD6D1).saturation, 0.15, "retail")
        XCTAssertLessThan(recoloured(0xF2DAD9).saturation, 0.15, "commercial")
        XCTAssertLessThan(recoloured(0xD9D0C9).saturation, 0.15, "buildings")
    }

    func testWaterStaysLightBlue() {
        let water = recoloured(0xAAD3DF)

        XCTAssertEqual(water.hue, 203, accuracy: 8)
        XCTAssertGreaterThan(water.saturation, 0.3)
        XCTAssertEqual(water.lightness, 0.82, accuracy: 0.05)
    }

    func testParksStayLightGreen() {
        for hex: UInt32 in [0xC8FACC, 0xADD19E, 0xCDEBB0] {
            let park = recoloured(hex)
            XCTAssertEqual(park.hue, 115, accuracy: 15)
            XCTAssertGreaterThan(park.saturation, 0.2)
            XCTAssertGreaterThan(park.lightness, 0.75)
        }
    }

    func testLabelsAndRoadEdgesStayVisible() {
        XCTAssertLessThan(recoloured(0x333333).lightness, 0.25, "labels")
        XCTAssertLessThan(recoloured(0x000000).lightness, 0.05, "place names")
        XCTAssertLessThan(recoloured(0xBBBBBB).lightness, TilePalette.hsl(TilePalette.land).lightness - 0.08, "road edges")
    }

    func testHSLRoundTrip() {
        for hex: UInt32 in [0xF2EFE9, 0xAAD3DF, 0xE892A2, 0x333333, 0x00F2FE] {
            let (hue, saturation, lightness) = TilePalette.hsl(colour(hex))
            let back = TilePalette.rgb(hue: hue, saturation: saturation, lightness: lightness)
            XCTAssertEqual(back.x, colour(hex).x, accuracy: 1e-9)
            XCTAssertEqual(back.y, colour(hex).y, accuracy: 1e-9)
            XCTAssertEqual(back.z, colour(hex).z, accuracy: 1e-9)
        }
    }

    func testCubeHasRedChangingFastest() {
        let cube = TilePalette.cube(size: 4)
        let red = TilePalette.recolor(SIMD3(1, 0, 0))
        let blue = TilePalette.recolor(SIMD3(0, 0, 1))

        XCTAssertEqual(cube.count, 4 * 4 * 4 * 4)
        XCTAssertEqual(Array(cube[12..<16]), [Float(red.x), Float(red.y), Float(red.z), 1])
        XCTAssertEqual(Array(cube[192..<196]), [Float(blue.x), Float(blue.y), Float(blue.z), 1])
    }
}
