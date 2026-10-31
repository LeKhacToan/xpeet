# Plan: Selectable gauge faces and themes

**Spec:** specs/gauge-themes/spec.md
<!-- Produced in Claude Code plan mode. Update in the same commit when implementation diverges. -->

Delivered as PR 1 of 3. The speed-mascot and engine-sound-clip PRs follow it.

## Files that change

### New: `Xpeet/Features/Speedometer/Faces/`
- `GaugeFace.swift`: `enum GaugeFace: String, CaseIterable, Identifiable`, with cases `minimalRing`, `analogSport`, `digitalHUD`, `retro`. Provides `displayName` and `theme`.
- `Theme.swift`
  - A value type that stores colours as hex `UInt32`: background centre and edge, number, placeholder, accent, track, chip fill and text, pill text, scale label.
  - Also holds `fontDesign` and `colorScheme`.
  - `Color(hex:)` moves here from `SpeedometerView`.
  - Pure WCAG helpers: `contrastRatio(_:_:)` and `blend(_:over:alpha:)`.
- `GaugeGeometry.swift`: pure helpers.
  - `needleAngle(fraction:)` returns `-135° + 270° × clamp(fraction)`.
  - `ticks(for: SpeedUnit)` returns the tick list.
  - `litSegments(fraction:count:)` returns how many segments are lit.
- `MinimalRingFace.swift`: today's `SpeedGauge`, moved here and driven by `Theme`.
- `DialFace.swift`: used by both Analog sport and Retro.
  - A static `Canvas` draws ticks and labels, and redraws only when the size or unit changes.
  - A `Needle` shape rotates.
  - The number sits below the hub.
- `DigitalHUDFace.swift`: the 20-segment `SegmentBar`. The HUD's monospaced number is laid out by `GaugeDisplay`.
- `GaugeDisplay.swift` *(added during build)*: `GaugeReading`, the per-face layout of the drawing, number and unit control, and `UnitPill`. The speed screen and the picker thumbnails share it, so a thumbnail always matches the real face.
- `FacePickerSheet.swift`: a grid of thumbnails, a checkmark on the selected face, and a "Done" button. Detents are medium and large.

### Modified
- `Xpeet/Features/Speedometer/SpeedometerViewModel.swift`: adds `face`, `select(_:)` and `faceDefaultsKey = "gaugeFace"`.
- `Xpeet/Features/Speedometer/SpeedometerView.swift`
  - Uses the theme instead of `Palette`.
  - Switches on the face.
  - Adds the `paintpalette` button, which opens the sheet.
  - Sets `.preferredColorScheme(theme.colorScheme)`.
  - Adds previews per face, including landscape.
- `specs/speedometer/spec.md`, `specs/speedometer-gauge/spec.md`: add "Superseded by `specs/gauge-themes/spec.md`" notes.
- `CLAUDE.md` Architecture: one line about `Features/Speedometer/Faces/`. The owner approved this on 2026-10-20. After the edit, run `evals/run.sh` + `scripts/check-bands.sh`.

### Tests
- `XpeetTests/GaugeFaceTests.swift` (new)
- `XpeetTests/GaugeGeometryTests.swift` (new)
- `XpeetTests/SpeedometerViewModelTests.swift` (modified)

### Starting palettes
These are a starting point. Tune them until the R8 test passes.

| Face | Background | Number | Accent |
|---|---|---|---|
| Minimal ring | `#16231B`→`#0A0F0C` | white | `#9FE3B5` (unchanged) |
| Analog sport | `#15181C`→`#08090B` | white | `#7FD8FF` |
| Digital HUD | `#04100E`→`#020605` | `#E6FBFF` | `#4DD9FF` |
| Retro (light) | `#F3EAD3`→`#E6D9BC` | `#2B2118` | `#7A281B` (darkened from `#8B2E1F` for 4.5:1 pill contrast; placeholder `#4A3E33` for 7:1) |

## Order of work
1. Add `GaugeFace`, `Theme` and `GaugeGeometry` with their tests. Run `xcodegen generate`.
2. Add `face` and `select(_:)` to the ViewModel, with persistence tests.
3. Move the ring into `MinimalRingFace`, driven by `Theme`. It should look the same as before.
4. Build `DialFace` (Analog sport, Retro), then `DigitalHUDFace`, with previews.
5. Add the picker button, the sheet and accessibility.
6. Add the superseded notes and the CLAUDE.md line. Run `scripts/verify.sh` and the evals, then the manual checks.

## Deviations
- **Dial layout (review finding):** with the number below the hub, a 3-digit speed overlapped the end-of-scale label and the needle. Took the plan's Risk mitigation: the number sits in a centre disc (0.5 of the diameter, font 0.2), and the needle is a pointer running only between the disc and the rim (0.25–0.46). No needle hub.
- `Theme` holds the font **design** only. Weights are fixed per role across all faces: number `.heavy`, pill and scale labels `.semibold`. The spec's "font design and weight" is narrowed to keep faces consistent.

## Risks
- **Smaller number on dial faces.** The number is about 25% of the dial diameter. If it is not readable, move it to the centre and use a smaller hub, and record that change here.
- **Canvas labels and Dynamic Type.** Canvas labels use `context.resolve(Text)` and scale with the dial, not with Dynamic Type. This matches R17.
- **Theme passing.** No `@Entry` macro, because back-deployment to iOS 17 is unverified. The theme is passed as a parameter instead.
- **iOS 17 untested.** Only the iOS 27.1 simulator is available locally.

## Proof
| Req | Proof |
|---|---|
| R1 | `GaugeFaceTests.testAllCasesOrderAndRawValues`, `testDisplayNamesNonEmptyAndUnique` |
| R2 | manual: Minimal ring preview vs `main` |
| R3 | `GaugeGeometryTests.testNeedleAngle{Zero,Half,Full}`, `testNeedleAngleAboveMaxIsClamped`, `testNeedleAngleWithoutReadingIsZero`, `testKmhTicks`, `testMphTicksEndAt130`; manual: previews |
| R4 | `GaugeGeometryTests.testLitSegments{Zero,Half,NearFull,Full,NoReading}`; manual: previews |
| R5 | manual: Retro preview under system light and dark; `GaugeFaceTests.testRetroIsLightOthersDark` |
| R6 | review; previews (chip and button in each face) |
| R7 | review |
| R8 | `GaugeFaceTests.testContrastMeetsMinimumsForEveryFace`, `test_headerText_reachesContrast_onEveryFace` (sheet header, 2026-10-31) |
| R9, R10 | manual: button, sheet, detents, Done |
| R11 | `SpeedometerViewModelTests.testSelectFaceUpdatesFace`; manual: haptic, no animation |
| R12 | `SpeedometerViewModelTests.testChangingFaceKeepsSpeedUnitStateAndLabel`, `testChangingFaceDoesNotResetFilter` |
| R13 | `SpeedometerViewModelTests.testFaceDefaultsToMinimalRing`, `testFacePersistsAcrossInstances`, `testUnknownSavedFaceFallsBackToMinimalRing` |
| R14 | manual: "199" landscape preview per face |
| R15 | manual: Freeway Drive in Xcode with Reduce Motion on and off (`simctl location` delivers no speed, so it cannot test the Live state) |
| R16 | `GaugeFaceTests.testAccessibilityStrings`; manual: Accessibility Inspector |
| R17 | manual: largest Dynamic Type, both orientations (sheet header re-checked 2026-10-31, see Checks); `test_headerScrollsWithGrid_atAccessibilitySizes` guards the layout choice only |

## Checks
- **Picker sheet header fix (2026-10-31), iPhone SE (3rd gen) simulator, iOS 17.5.** A throwaway patch opened the sheet at launch and rotated the scene, and was reverted before commit. Content size was set with `simctl ui content_size`.
  - **Before.** At the largest accessibility size, medium height, the pinned header truncated to "Gauge…" and "Choose…". On Retro, the subtitle measured 3.05:1 and "Done" about 1.0:1.
  - **After, largest accessibility size.**
    - Retro, portrait, medium height: only "Done" stays pinned. "Gauge style" and the subtitle sit at the top of the scroll view and wrap over several lines, with no ellipsis.
    - Digital HUD, landscape: the title is on one line and the subtitle wraps to two, with no ellipsis.
  - **After, default size.** Retro and Digital HUD keep the same layout. The subtitle and "Done" take the face's `secondaryText` and `accent`. On Retro, the measured screenshot gives 5.85:1 for the subtitle and 6.80:1 for "Done". The test's model of the material gives 5.74:1 and 6.79:1.
  - **Not checked.** Landscape left, and the Accessibility Inspector. The sheet's ink follows `selected.theme`, and so does the screen's `preferredColorScheme`, so picking a face with the sheet open changes both together.

Run `scripts/verify.sh` for every step.
