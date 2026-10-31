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

    func testMinimalRingUsesNocturnePalette() {
        // specs/ui-redesign R9.
        let theme = GaugeFace.minimalRing.theme
        XCTAssertEqual(theme.backgroundCenter, 0x0D121D)
        XCTAssertEqual(theme.backgroundEdge, 0x080B11)
        XCTAssertEqual(theme.number, 0xF5F8FC)
        XCTAssertEqual(theme.accent, 0x00F2FE)
        XCTAssertEqual(theme.accentDeep, 0x4FACFE)
    }

    func testRedZoneAndProgressPerFace() {
        // specs/ui-redesign R11, R13: dial faces only; the progress arc on Analog sport only.
        XCTAssertNil(GaugeFace.minimalRing.theme.redZone)
        XCTAssertNil(GaugeFace.digitalHUD.theme.redZone)
        XCTAssertEqual(GaugeFace.analogSport.theme.redZone, 0xFF5A4F)
        XCTAssertEqual(GaugeFace.retro.theme.redZone, GaugeFace.retro.theme.accent)
        XCTAssertEqual(GaugeFace.allCases.filter { $0.theme.dialProgress }, [.analogSport])
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

    // MARK: - specs/osm-map R4, R18

    /// Map-mode cards are opaque: the theme background with the chip tint, never the map.
    func testMapCardContrastForEveryFace() {
        for face in GaugeFace.allCases {
            let theme = face.theme
            let card = MapStyle.cardColor(for: theme)

            XCTAssertGreaterThanOrEqual(Theme.contrastRatio(theme.number, card), 7, "\(face) speed digits")
            XCTAssertGreaterThanOrEqual(Theme.contrastRatio(theme.placeholder, card), 7, "\(face) --")
            XCTAssertGreaterThanOrEqual(Theme.contrastRatio(theme.secondaryText, card), 4.5, "\(face) trip line")
            XCTAssertGreaterThanOrEqual(Theme.contrastRatio(theme.chipText, card), 4.5, "\(face) notice text")
            XCTAssertGreaterThanOrEqual(Theme.contrastRatio(theme.accent, card), 4.5, "\(face) OK and re-centre")
            XCTAssertGreaterThanOrEqual(Theme.contrastRatio(theme.chipText, theme.backgroundCenter), 4.5, "\(face) credit")
        }
    }

    /// The trail shows on the light tiles (R18, R33): each face's line stands apart from its edge, and the line or its
    /// edge stands out from the land and from white roads (3:1, non-text contrast).
    func testTrailShowsOnTheLightMapForEveryFace() {
        let land = TilePalette.land * 255
        let landHex = UInt32(land.x.rounded()) << 16 | UInt32(land.y.rounded()) << 8 | UInt32(land.z.rounded())

        for face in GaugeFace.allCases {
            let accent = face.theme.accent
            let edge = MapStyle.trailEdge(for: face.theme)
            XCTAssertGreaterThanOrEqual(Theme.contrastRatio(accent, edge), 3, "\(face) line on its edge")
            for (name, ground) in [("land", landHex), ("white roads", 0xFFFFFF)] as [(String, UInt32)] {
                XCTAssertGreaterThanOrEqual(
                    max(Theme.contrastRatio(accent, ground), Theme.contrastRatio(edge, ground)), 3, "\(face) on \(name)"
                )
            }
        }
        XCTAssertEqual(MapStyle.trailEdge(for: GaugeFace.minimalRing.theme), MapStyle.darkTrailEdge)
        XCTAssertEqual(MapStyle.trailEdge(for: GaugeFace.retro.theme), 0xFFFFFF, "a dark accent gets a light edge")
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
            // specs/ui-redesign R16.
            XCTAssertGreaterThanOrEqual(worst(theme.secondaryText), 4.5, "\(face) hint text")
            if let redZone = theme.redZone {
                XCTAssertGreaterThanOrEqual(worst(redZone), 3, "\(face) red zone")
            }
        }
    }

    // MARK: - R16

    func testAccessibilityStrings() {
        XCTAssertEqual(SpeedometerView.faceButtonLabel, "Gauge style")
        XCTAssertEqual(SpeedometerView.faceButtonHint, "Double-tap for gauge faces and engine sounds")
    }

    // MARK: - specs/engine-clip-toggle R1, R12

    func testSoundSectionStrings() {
        XCTAssertEqual(FacePickerSheet.soundHeading, "Sound")
        XCTAssertEqual(FacePickerSheet.engineSoundsLabel, "Engine sounds")
        XCTAssertEqual(FacePickerSheet.engineSoundsHint, "Plays a short clip when the engine starts. Off stops the microphone.")
    }
}
