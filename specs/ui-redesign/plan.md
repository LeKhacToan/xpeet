# Plan: UI redesign from the Stitch "Xpeet Anime Speedometer" project

**Spec:** specs/ui-redesign/spec.md
**Branch:** `feat/ui-redesign` (from `main` at `4b2809f`, after PR #8).

No new types parallel to existing ones: the mascot stays `Mood` + `MoodResolver` (owned by `SpeedometerViewModel`) + `MascotView`. Faces stay `GaugeFace` + `Theme` + `GaugeGeometry` + `GaugeDisplay`. No new feature folder, no new ViewModel, no third-party dependency, and no CLAUDE.md change, so no eval run is needed.

## Files that change

**Mascot**
- `Xpeet/Features/Speedometer/Mascot/Mood.swift` (modified): add `case sad`.
- `Xpeet/Features/Speedometer/Mascot/MoodResolver.swift` (modified): add `mutating func unavailable() -> Mood`, which resets like `lost()` and returns `.sad`.
- `Xpeet/Features/Speedometer/Mascot/MascotView.swift` (rewritten):
  - `enum MascotArtwork` with `static func assetName(for: Mood) -> String` (`"Mascot/<mood>"`) and `static let blink = "Mascot/blink"`.
  - The view shows `Image(assetName)`, resizable, clipped to a `Circle`, with a static accent glow ring.
  - It keeps the existing blink `.task`, now gated on `mood == .calm`, and the crossfade and Reduce Motion rules.
- `Xpeet/Features/Speedometer/Mascot/MascotPlacement.swift` (modified): `sizeFraction` 0.22, `sizeRange` 44...96.
- `Xpeet/Features/Speedometer/SpeedometerViewModel.swift` (modified): `becomeUnavailable` calls `moodResolver.unavailable()`.
- `Xpeet/Resources/Assets.xcassets/Mascot/` (new):
  - `Contents.json` with `provides-namespace`;
  - eight image sets (`calm`, `happy`, `worried`, `startled`, `sleepy`, `searching`, `sad`, `blink`), each holding one universal JPEG and a `Contents.json`.
- `Xpeet/Resources/MASCOT-SOURCE.txt` (new): the Stitch project, the screen id per asset, the date, the processing command and the licence note.
- `scripts/mascot-assets.swift` (new): a CoreGraphics script that takes a folder of the 1024 px Stitch renders named `<asset>.png`. For each it crops the badge's bounding square (centre, radius 0.42 of the side, tuned once by eye), resizes it to 288×288 and writes JPEG quality 0.8 into the image sets. Run by hand only; it is not part of the build.

**Fonts**
- `Xpeet/Resources/Fonts/SpaceGrotesk/SpaceGrotesk[wght].ttf` + `OFL.txt` (new), unmodified from google/fonts `ofl/spacegrotesk`.
- `project.yml` (modified): `UIAppFonts` adds `"SpaceGrotesk[wght].ttf"`.

**Theme and geometry**
- `Xpeet/Features/Speedometer/Faces/Theme.swift` (modified):
  - remove `MascotPalette` and `mascot`;
  - add `redZone: UInt32?`, `dialProgress: Bool` (true only for Analog sport) and `secondaryText: UInt32` (the Open Settings hint);
  - add `static let captionTypeface = "SpaceGrotesk-SemiBold"` and `func captionFont(textStyle:size:)`;
  - add a `glass(_:)` helper for the shared material, tint and hairline background.
- `Xpeet/Features/Speedometer/Faces/GaugeFace.swift` (modified):
  - the Minimal ring palette per spec R9;
  - `redZone` `0xFF5A4F` for Analog sport and the accent `0x7A281B` for Retro;
  - `secondaryText` per face.
- `Xpeet/Features/Speedometer/Faces/GaugeGeometry.swift` (modified): `redZoneStart(for: SpeedUnit) -> Int` (160 / 100) and `redZoneStartFraction(for:)`.

**Faces**
- `Faces/MinimalRingFace.swift` (modified): faint major-tick marks outside the track; the tip dot stays.
- `Faces/GaugeDisplay.swift` (modified):
  - a "SPEED" caption with an `arrow.up.right` glyph above the number on Minimal ring and Analog sport;
  - the Digital HUD layout inside a `HUDFrame`;
  - `UnitPill` restyled to glass, uppercase text and a swap glyph, in the caption font.
- `Faces/DialFace.swift` (modified):
  - a progress arc when `theme.dialProgress`;
  - red-zone ticks and labels (Analog sport) or a red-zone arc (Retro) from `redZoneStartFraction`, in the static `DialScale`;
  - a thicker chrome bezel for light faces.
- `Faces/FaceDecor.swift` (modified): add `HUDFrame` (dashed circle, corner brackets, cardinal ticks; `Equatable`) and `GlassBackground`.
- `Faces/FacePickerSheet.swift` (modified):
  - the subtitle;
  - glass cards with a 2 pt accent border, a check badge and an "Active" tag (hidden from VoiceOver);
  - `.presentationBackground(.ultraThinMaterial)`.

**Screen**
- `Xpeet/Features/Speedometer/SpeedometerView.swift` (modified):
  - Portrait: a `VStack` with a reserved top row (`StatusChip` centred and the face button trailing, 52 pt high), then the gauge area with the mascot overlay, then the bottom inset for Open Settings and its hint only.
  - Landscape (width > height): the current layout, with the chip and Open Settings at the bottom.
  - `StatusChip`: a private view with the glass capsule, accent dot, icon, wrapping text and caption font.
  - Previews: existing ones kept, plus "Weak signal", "Searching, retro", "Mic off, HUD" and "Denied, landscape".

**Tests**
- `XpeetTests/MoodResolverTests.swift` (modified):
  - `testMoodCases` covers seven cases;
  - new `testUnavailableIsSad`, `testUnavailableOverridesStartled`, `testFirstMoodAfterUnavailableIsImmediate`.
- `XpeetTests/SpeedometerViewModelTests.swift` (modified): new `testDeniedShowsSadMascot`, `testServicesOffShowsSadMascot`, `testAuthorizedAfterDeniedShowsSearching`.
- `XpeetTests/MascotPlacementTests.swift` (modified): `testSizeIsTwentyTwoPercentClamped`. The other placement tests are re-checked against the new constants (iPhone SE portrait still fits).
- `XpeetTests/MascotArtworkTests.swift` (new):
  - `testEveryMoodHasArtwork` (`UIImage(named:in:)` is non-nil and 288×288);
  - `testBlinkArtworkExists`;
  - `testArtworkPayloadUnderCap` (the sum of the image set files is under 600 KB).
- `XpeetTests/GaugeFaceTests.swift` (modified):
  - `testMinimalRingKeepsOriginalPalette` becomes `testMinimalRingUsesNocturnePalette`;
  - `testMascotFeatureContrastPerFace` is removed (no palette);
  - `testContrastMeetsMinimumsForEveryFace` adds the hint text (4.5:1) and red-zone (3:1) checks.
- `XpeetTests/GaugeGeometryTests.swift` (modified): `testRedZoneStartPerUnit`.
- `XpeetTests/FontTests.swift` (modified): the Space Grotesk file, licence and PostScript name are added to the existing tables; the payload cap is raised by the font's size.

**Docs**
- `specs/speed-mascot/spec.md`, `specs/visual-polish/spec.md`, `specs/gauge-themes/spec.md`: one "Superseded by `specs/ui-redesign`" note per affected requirement.
- `specs/ui-redesign/spec.md`: the R1 storage change (see Deviations).

## Order of work
Each step ends with `xcodegen generate` (when files were added) and a green `scripts/test.sh`.

1. **Sad mood:**
   - Write the `Mood.sad` and `MoodResolver.unavailable()` tests first, then implement.
   - Do the same for the ViewModel tests and wiring.
   - `MascotView` temporarily maps `.sad` to the existing searching drawing.
2. **Artwork:**
   - Download the eight Stitch renders.
   - Write and run `scripts/mascot-assets.swift`, then check the crops by eye.
   - Add the image sets, `MASCOT-SOURCE.txt` and the `MascotArtworkTests`.
3. **Mascot view:**
   - Rewrite `MascotView` around the artwork.
   - Update the `MascotPlacement` constants and their test.
   - Remove `Theme.mascot` and its contrast test.
4. **Space Grotesk:** add the font, `project.yml` and `FontTests`, then `Theme.captionFont`.
5. **Theme and geometry:**
   - Add the Minimal ring palette, `redZone`, `dialProgress` and `secondaryText`.
   - Add `GaugeGeometry.redZoneStart`.
   - Update `GaugeFaceTests` and `GaugeGeometryTests`.
6. **Faces:**
   - Minimal ring ticks and caption.
   - Dial progress arc, red zone and bezel.
   - `HUDFrame` and the HUD layout.
   - Check previews per face against `design/`.
7. **Chrome:** the glass `UnitPill`, `StatusChip`, the portrait top row and face button, Open Settings with its hint, and the previews.
8. **Picker:** restyle the sheet.
9. **Wrap up:**
   - Add the superseded notes to the earlier specs.
   - Run `scripts/verify.sh`, then `scripts/install-device.sh`.
   - Run the verifier and reviewer agents, then open the PR.

## Risks
- **Image budget (resolved in planning):** a 288 px PNG of the renders is about 118 KB (8 × 118 KB ≈ 0.95 MB, over the 600 KB cap). A JPEG at quality 0.8 is about 25 KB. The images are stored as square JPEG crops and clipped to a circle in `MascotView`, instead of PNGs with an alpha mask. The look on screen is identical and the total is about 0.2 MB.
- **Badge crop:** the renders' circular badge isn't perfectly centred or the same size in every render, so one fixed crop radius may leave a sliver of the outer background or cut the rim. Check all eight by eye in step 2, and allow a per-asset radius override in the script.
- **Blink alignment:** the blink frame is a separate generation. The hair and goggles match calm closely, but not pixel-exactly. A 0.15 s swap hides small differences. If it reads as a jump on device, cross-dissolve over 0.06 s instead.
- **Asset catalog namespace:** XcodeGen copies `.xcassets` as-is. The `Mascot` folder needs `"properties": {"provides-namespace": true}` in its `Contents.json`, or `Image("Mascot/calm")` will not resolve. `MascotArtworkTests` is the gate.
- **Space Grotesk PostScript name:** expected `SpaceGrotesk-SemiBold` for the variable font's named instance. If `UIFont(name:)` returns nil, use the name `FontTests` prints from `UIFont.fontNames(forFamilyName:)` (same approach as Bodoni in visual-polish).
- **Glass contrast:** system materials have no fixed colour, so the contrast tests use the theme's `chipFill` overlay over `backgroundCenter` as a stand-in, as gauge-themes does. The real material is a little more opaque, so actual contrast is equal or higher. Retro (light) gets a manual check.
- **Portrait top row:** reserving 52 pt reduces the space above the gauge. On iPhone SE portrait (about 343×547 pt of container) the space above is about 102 pt, which fits a 75 pt badge plus its gap. `testSmallPortraitStillFits` is updated to that container.
- **Licensing:** Stitch-generated artwork is used for a personal build only (spec Flagged concerns). Space Grotesk is OFL; `OFL.txt` ships unmodified.
- **Performance:** materials blur once per layout. `HUDFrame`, the bezel and the red zone are static `Equatable` views or `Canvas`. Per sample, only the existing arc, needle, segments and number change, plus the new progress arc on Analog sport, which is the same trimmed-arc animation the Minimal ring already uses.

## Deviations from the spec (recorded with the spec in this commit)
- **R1:** each mascot image is a 288×288 single-scale JPEG of the badge's bounding square, clipped to a circle in code, rather than a PNG with transparency outside the circle. Reason: the size budget (see Risks). The spec's R1 text is updated.

## Proof
| Req | Proof |
|---|---|
| R1 | `MascotArtworkTests.testEveryMoodHasArtwork`, `.testBlinkArtworkExists`, `.testArtworkPayloadUnderCap`; `MASCOT-SOURCE.txt` in review |
| R2 | review; previews "Moods × faces" |
| R3 | manual: on device, calm blinks every 3–6 s; other moods and Reduce Motion do not blink |
| R4 | `MoodResolverTests.testUnavailableIsSad`, `.testUnavailableOverridesStartled`, `.testFirstMoodAfterUnavailableIsImmediate`; `SpeedometerViewModelTests.testDeniedShowsSadMascot`, `.testServicesOffShowsSadMascot`, `.testAuthorizedAfterDeniedShowsSearching` |
| R5 | `MascotPlacementTests.testSizeIsTwentyTwoPercentClamped`, `.testSmallPortraitStillFits`, `.testMascotNeverOverlapsGauge`; manual crossfade |
| R6 | manual: Accessibility Inspector, badge not focusable |
| R7 | manual: previews "Acquiring", "Weak signal", "Mic off, HUD", "Denied"; gauge size equal with and without a chip (portrait) |
| R8 | manual: previews; 44 pt hit target |
| R9 | `GaugeFaceTests.testMinimalRingUsesNocturnePalette`, `.testContrastMeetsMinimumsForEveryFace` |
| R10 | manual: preview "Live" vs `design/minimal-ring.jpg` |
| R11 | `GaugeGeometryTests.testRedZoneStartPerUnit`; manual: previews "Analog sport", "Analog sport, landscape" vs `design/` |
| R12 | manual: "Digital HUD", "Mic off, HUD" vs `design/` |
| R13 | manual: "Retro", "Retro, denied", and "199" previews: the number is clear of the hub |
| R14 | `FontTests.testBundledFontsAndLicencesExist`, `.testEveryPostScriptNameResolves`, `.testFontPayloadUnderCap` |
| R15 | `SpeedometerViewModelTests` unit tests (unchanged accessibility values); manual: preview "Unit pill" |
| R16 | `GaugeFaceTests.testContrastMeetsMinimumsForEveryFace` (hint 4.5:1, red zone 3:1 added) |
| R17 | manual: preview "Denied" vs `design/retro-location-off.jpg` |
| R18 | manual: preview "Picker" vs `design/picker.jpg`; VoiceOver selected trait |
| R19 | full suite green via `scripts/verify.sh`; Release build |
