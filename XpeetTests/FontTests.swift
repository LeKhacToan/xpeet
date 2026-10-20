import UIKit
import XCTest
@testable import Xpeet

/// specs/visual-polish R1–R3: bundled OFL fonts, their licences, name resolution and tabular digits.
final class FontTests: XCTestCase {
    private static let families: [(licence: String, files: [String])] = [
        ("Nunito-OFL", ["Nunito[wght]"]),
        ("BarlowCondensed-OFL", ["BarlowCondensed-SemiBold", "BarlowCondensed-Bold", "BarlowCondensed-Black"]),
        ("Oxanium-OFL", ["Oxanium[wght]"]),
        ("BodoniModa-OFL", ["BodoniModa[opsz,wght]"]),
    ]

    private var bundle: Bundle { Bundle(for: SpeedometerViewModel.self) }

    // MARK: - R1

    func testBundledFontsAndLicencesExist() throws {
        for family in Self.families {
            let licence = try XCTUnwrap(bundle.url(forResource: family.licence, withExtension: "txt"), family.licence)
            let text = try String(contentsOf: licence, encoding: .utf8)
            XCTAssertTrue(text.contains("SIL OPEN FONT LICENSE Version 1.1"), family.licence)
            // A reserved name would appear in the copyright header ("with Reserved Font Name ...").
            // The licence body always defines the term, so only the header is checked.
            let header = text.prefix(while: { $0 != "\n" })
            XCTAssertTrue(header.hasPrefix("Copyright"), family.licence)
            XCTAssertFalse(header.contains("Reserved Font Name"), "\(family.licence) must not reserve a name")
            for file in family.files {
                XCTAssertNotNil(bundle.url(forResource: file, withExtension: "ttf"), file)
            }
        }
    }

    func testFontPayloadUnderCap() throws {
        var total = 0
        for file in Self.families.flatMap(\.files) {
            let url = try XCTUnwrap(bundle.url(forResource: file, withExtension: "ttf"), file)
            total += try XCTUnwrap(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        }
        XCTAssertLessThan(total, 1_500_000, "fonts total \(total) bytes")
    }

    // MARK: - R2

    func testEveryPostScriptNameResolves() {
        for face in GaugeFace.allCases {
            for role in [Theme.Role.number, .secondary] {
                let name = face.theme.name(for: role)
                let font = UIFont(name: name, size: 20)
                XCTAssertNotNil(font, "\(face): \(name)")
                XCTAssertEqual(font?.fontName, name, "\(face): resolved a different font")
            }
        }
    }

    // MARK: - R3

    func testNumberFontsHaveTabularDigits() {
        for face in GaugeFace.allCases {
            let font = UIFont.tabular(name: face.theme.typeface.number, size: 64)
            XCTAssertEqual(font.fontName, face.theme.typeface.number, "\(face): fell back to another font")
            let widths = (0...9).map { digit in
                NSAttributedString(string: String(digit), attributes: [.font: font]).size().width
            }
            let spread = (widths.max() ?? 0) - (widths.min() ?? 0)
            XCTAssertLessThan(spread, 0.5, "\(face): digit widths \(widths)")
        }
    }
}
