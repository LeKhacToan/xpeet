import XCTest
@testable import Xpeet

final class TileSourceTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "TileSourceTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - specs/osm-map R10

    func testDefaultTemplate() {
        let source = TileSource(defaults: defaults)

        XCTAssertEqual(source.template, "https://tile.openstreetmap.org/{z}/{x}/{y}.png")
        XCTAssertEqual(source.url(for: TileKey(z: 16, x: 52_183, y: 30_804))?.absoluteString,
                       "https://tile.openstreetmap.org/16/52183/30804.png")
    }

    func testOverrideNeedsHTTPSAndPlaceholders() {
        defaults.set("http://tiles.example.org/{z}/{x}/{y}.png", forKey: TileSource.overrideKey)
        XCTAssertEqual(TileSource(defaults: defaults).template, TileSource.defaultTemplate, "plain HTTP is ignored")

        defaults.set("https://tiles.example.org/{z}/{x}.png", forKey: TileSource.overrideKey)
        XCTAssertEqual(TileSource(defaults: defaults).template, TileSource.defaultTemplate, "a missing placeholder is ignored")

        defaults.set("https://tiles.example.org/{z}/{x}/{y}.png", forKey: TileSource.overrideKey)
        XCTAssertEqual(TileSource(defaults: defaults).url(for: TileKey(z: 1, x: 2, y: 3))?.absoluteString,
                       "https://tiles.example.org/1/2/3.png")
    }

    // MARK: - R11

    func testUserAgentNamesTheApp() {
        XCTAssertEqual(TileSource.userAgent(version: "1.2.3"), "Xpeet/1.2.3 (+https://github.com/LeKhacToan/xpeet)")
    }
}
