import UIKit
import XCTest
@testable import Xpeet

/// specs/ui-redesign R1: one rendered image per mood plus the blink frame, all in the app bundle.
final class MascotArtworkTests: XCTestCase {
    private var bundle: Bundle { Bundle(for: SpeedometerViewModel.self) }

    private func image(_ name: String) -> UIImage? {
        UIImage(named: name, in: bundle, compatibleWith: nil)
    }

    func testEveryMoodHasArtwork() {
        for mood in Mood.allCases {
            let name = MascotArtwork.assetName(for: mood)
            let artwork = image(name)
            XCTAssertNotNil(artwork, name)
            XCTAssertEqual(artwork.map { $0.size.width * $0.scale }, 288, name)
            XCTAssertEqual(artwork.map { $0.size.height * $0.scale }, 288, name)
        }
    }

    func testBlinkArtworkExists() {
        XCTAssertNotNil(image(MascotArtwork.blink))
    }

    func testArtworkPayloadUnderCap() throws {
        // The compiled catalog is opaque, so measure the source image sets next to this file.
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../Xpeet/Resources/Assets.xcassets/Mascot")
            .standardizedFileURL
        let files = try XCTUnwrap(FileManager.default.enumerator(at: catalog, includingPropertiesForKeys: [.fileSizeKey]))
        let total = try files.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jpg" }
            .reduce(0) { $0 + (try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        XCTAssertGreaterThan(total, 0)
        XCTAssertLessThan(total, 600_000)
    }
}
