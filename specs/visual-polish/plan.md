# Plan: Visual polish for the gauge faces and the mascot

**Spec:** specs/visual-polish/spec.md
<!-- Produced in Claude Code plan mode. Update in the same commit when implementation diverges. -->

PR 3. Branch `feat/visual-polish` from `feat/speed-mascot` (or from `main` once PR 2 is merged).

## Files that change
- `Xpeet/Resources/Fonts/Nunito/Nunito[wght].ttf`, `OFL.txt` (new)
- `Xpeet/Resources/Fonts/BarlowCondensed/BarlowCondensed-{SemiBold,Bold,Black}.ttf`, `OFL.txt` (new)
- `Xpeet/Resources/Fonts/Oxanium/Oxanium[wght].ttf`, `OFL.txt` (new)
- `Xpeet/Resources/Fonts/BodoniModa/BodoniModa[opsz,wght].ttf`, `OFL.txt` (new)
  - Downloaded from `https://raw.githubusercontent.com/google/fonts/main/ofl/<family>/…` (URL-encode `[`/`]`), committed byte-for-byte.
- `project.yml` (modified): `info: { path: Xpeet/Resources/Info.plist, properties: { UIAppFonts: [...] } }` on the app target. `.gitignore` (modified): `Xpeet/Resources/Info.plist`.
- `Xpeet/Features/Speedometer/Faces/Theme.swift` (modified): `Typeface { number, secondary }` replaces `Design`; `font(role:size:)` and `font(role:textStyle:)` helpers; tabular-figures descriptor for the number role.
- `Xpeet/Features/Speedometer/Faces/GaugeFace.swift` (modified): typeface per theme.
- `Xpeet/Features/Speedometer/Faces/FaceDecor.swift` (new): `BezelRing`, `Vignette`, `Scanlines`, `PaperGrain`, `Glow` helper views.
- `Xpeet/Features/Speedometer/Faces/MinimalRingFace.swift`, `DialFace.swift`, `DigitalHUDFace.swift`, `GaugeDisplay.swift` (modified): fonts + decoration layers.
- `Xpeet/Features/Speedometer/Faces/FacePickerSheet.swift` (modified): face names in the secondary font.
- `Xpeet/Features/Speedometer/Mascot/MascotView.swift` (rewritten), `MascotPlacement.swift` (ceiling 84).
- `XpeetTests/FontTests.swift` (new): bundle files + licences, size cap, name resolution, tabular digit widths.
- `XpeetTests/MascotPlacementTests.swift` (modified): ceiling 84.
- `specs/gauge-themes/spec.md`, `specs/speed-mascot/spec.md`: superseded notes (fonts in scope; size ceiling).

## Order of work
1. Fonts + licences + `project.yml` `info:` block + `.gitignore`. `FontTests` (R1–R3). `xcodegen generate`, `verify.sh`.
2. `Theme.Typeface` and font helpers; swap every `.system(design:)` use. Visual check that nothing moved.
3. `FaceDecor` helpers and per-face decoration (R5, R6). Render check at 199 km/h / 129 mph with the macOS harness and simulator screenshots.
4. `MascotView` rewrite (R7, R8), ceiling 84 (R9), contrast test still green (R10).
5. Spec notes, `verify.sh`, device install, verifier + reviewer.

## Risks
- **Named instances of variable fonts** may not resolve on iOS 17 (forum-only evidence). Gate: `FontTests.testEveryPostScriptNameResolves`. Fallback: build the weight with `kCTFontVariationAttribute` (`wght`) on a descriptor from the family's default instance.
- **`.monospacedDigit()` on custom fonts** may be a no-op; the plan uses an explicit `kNumberSpacingType` feature on the descriptor instead and tests digit widths.
- **`Font(UIFont)` ignores Dynamic Type**: used only for the diameter-sized number and the diameter-sized scale labels; pill/picker/chip use `Font.custom(_:size:relativeTo:)`.
- **Texture cost**: `PaperGrain` and `Scanlines` are drawn in `Canvas` and marked `Equatable`, so they rasterise once per size. Verify with a quick CPU look in Instruments if the simulator feels warm.
- **Info.plist is generated**: `scripts/*.sh` all run `xcodegen generate` first, so a fresh clone is fine.

## Proof
| Req | Proof |
|---|---|
| R1 | `FontTests.testBundledFontsAndLicencesExist`, `testFontPayloadUnderCap` |
| R2 | `FontTests.testEveryPostScriptNameResolves` |
| R3 | `FontTests.testNumberFontsHaveTabularDigits`; manual: previews |
| R4 | manual: largest Dynamic Type |
| R5, R6 | manual: previews and simulator screenshots per face at 199 / 129 |
| R7, R8 | manual: "Moods × faces" preview, blink on device |
| R9 | `MascotPlacementTests.testSizeIsEighteenPercentClamped` (84 ceiling) |
| R10 | `GaugeFaceTests.testMascotFeatureContrastPerFace`, `testContrastMeetsMinimumsForEveryFace` |
| R11 | full suite via `scripts/verify.sh` |
