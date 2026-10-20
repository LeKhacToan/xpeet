import SwiftUI
import XCTest
@testable import Xpeet

final class GaugeFaceTests: XCTestCase {
    // MARK: - R1

    func testAllCasesOrderAndRawValues() {
        XCTAssertEqual(GaugeFace.allCases.map(\.rawValue), ["minimalRing", "analogSport", "digitalHUD", "retro"])
        XCTAssertEqual(GaugeFace.defaultFace, .minimalRing)
    }

    func testDisplayNamesNonEmptyAndUnique() {
        let names = GaugeFace.allCases.map(\.displayName)
        XCTAssertFalse(names.contains(where: \.isEmpty))
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(Set(GaugeFace.allCases.map(\.id)).count, GaugeFace.allCases.count)
    }

    // MARK: - R2, R5

    func testMinimalRingKeepsOriginalPalette() {
        let theme = GaugeFace.minimalRing.theme
        XCTAssertEqual(theme.accent, 0x9FE3B5)
        XCTAssertEqual(theme.backgroundCenter, 0x16231B)
        XCTAssertEqual(theme.backgroundEdge, 0x0A0F0C)
    }

    func testRetroIsLightOthersDark() {
        for face in GaugeFace.allCases {
            XCTAssertEqual(face.theme.colorScheme, face == .retro ? .light : .dark, face.rawValue)
        }
    }

    // MARK: - R8

    func testContrastHelperMatchesKnownValues() {
        XCTAssertEqual(Theme.contrastRatio(0xFFFFFF, 0x000000), 21, accuracy: 0.01)
        XCTAssertEqual(Theme.contrastRatio(0x777777, 0x777777), 1, accuracy: 0.001)
        XCTAssertEqual(Theme.blend(0xFFFFFF, over: 0x000000, opacity: 0.5), 0x808080)
    }

    func testContrastMeetsMinimumsForEveryFace() {
        for face in GaugeFace.allCases {
            let theme = face.theme
            let backgrounds = [theme.backgroundCenter, theme.backgroundEdge]
            func worst(_ foreground: UInt32, on overlay: Theme.Overlay? = nil) -> Double {
                backgrounds.map { background in
                    let surface = overlay.map { Theme.blend($0.hex, over: background, opacity: $0.opacity) } ?? background
                    return Theme.contrastRatio(foreground, surface)
                }.min() ?? 0
            }
            let pillTint = Theme.Overlay(hex: theme.accent, opacity: Theme.pillTintOpacity)

            XCTAssertGreaterThanOrEqual(worst(theme.number), 7, "\(face) number")
            XCTAssertGreaterThanOrEqual(worst(theme.placeholder), 7, "\(face) placeholder")
            XCTAssertGreaterThanOrEqual(worst(theme.chipText, on: theme.chipFill), 4.5, "\(face) chip text")
            XCTAssertGreaterThanOrEqual(worst(theme.accent, on: pillTint), 4.5, "\(face) unit pill")
            XCTAssertGreaterThanOrEqual(Theme.contrastRatio(theme.buttonLabel, theme.accent), 4.5, "\(face) Open Settings")
            XCTAssertGreaterThanOrEqual(worst(theme.scaleLabel), 4.5, "\(face) scale labels")
        }
    }

    // MARK: - R16

    func testAccessibilityStrings() {
        XCTAssertEqual(SpeedometerView.faceButtonLabel, "Gauge style")
        XCTAssertEqual(SpeedometerView.faceButtonHint, "Double-tap to choose a gauge face")
    }
}
