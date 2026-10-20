# Spec: Visual polish for the gauge faces and the mascot

**Intent:** intent/2026-10-20-visual-polish.md  **Status:** approved
**Depends on:** `specs/gauge-themes/spec.md`, `specs/speed-mascot/spec.md`. Build after the speed-mascot PR.

This spec changes only how things look. Geometry, mood logic, placement rules, persistence and accessibility behaviour stay as specified before. It replaces, in `specs/gauge-themes/spec.md`, the Out of scope line "Custom fonts (e.g. 7-segment)": bundled open-source fonts are now in scope as assets. It raises the mascot size ceiling in `specs/speed-mascot/spec.md` R12 from 72 pt to 84 pt.

Research (researcher agent, 2026-10-20): font licences, tabular digits and the registration route are summarised under Data & API and Flagged concerns.

## Requirements

### Typography
- **R1** Four font families are bundled, byte-for-byte unmodified from the google/fonts repository, each with its `OFL.txt`:

  | Face | Family | Files | PostScript names used |
  |---|---|---|---|
  | Minimal ring | Nunito | `Nunito[wght].ttf` | `Nunito-Black` (number), `Nunito-SemiBold` (secondary) |
  | Analog sport | Barlow Condensed | `BarlowCondensed-SemiBold.ttf`, `-Bold.ttf`, `-Black.ttf` | `BarlowCondensed-Black`, `BarlowCondensed-SemiBold` |
  | Digital HUD | Oxanium | `Oxanium[wght].ttf` | `OxaniumRoman-ExtraBold`, `OxaniumRoman-SemiBold` |
  | Retro | Bodoni Moda | `BodoniModa[opsz,wght].ttf` | `BodoniModa-Regular_Black`, `BodoniModa-Regular_SemiBold` (the `opsz` axis adds `Regular_` to the instance names) |

  All are SIL OFL 1.1 with no Reserved Font Name. Total font payload is under 1.5 MB. *(unit: every file and licence exists in the bundle; total size)*

- **R2** Every PostScript name in R1 resolves to a font at runtime (the variable fonts expose their named instances). *(unit: `UIFont(name:size:)` is non-nil for each name)*

- **R3** The speed number, scale labels and unit pill use the active face's family. Roles: number = the heavy name, secondary (pill, scale labels, picker name) = the semibold name. The number uses tabular figures, so "111" and "000" have the same width. *(unit: the ten digits have equal advance widths in each number font; manual: previews)*

- **R4** Dynamic Type still applies where it did: the unit pill, chip and picker text scale with the user's text size (custom fonts sized relative to their text style). The number stays sized by the gauge diameter. *(manual: largest size)*

### Faces
- **R5** Each face gains static decoration layers. They are drawn once per size/unit/theme change and never per sample:

  | Face | Decoration |
  |---|---|
  | Minimal ring | a faint bezel ring outside the track, a soft inner glow inside it, a brighter tip (highlight dot) at the leading end of the progress arc |
  | Analog sport | a radial "brushed" dial gradient, a bevelled rim (two concentric strokes, light and dark), major ticks with a lighter highlight edge, a vignette at the edge, a glowing needle with a drop shadow |
  | Digital HUD | a horizontal scanline texture at low opacity over the background, a soft glow behind the number, lit segments with a bloom |
  | Retro | a paper-grain texture (low-opacity noise dots) on the cream dial, an embossed chrome rim (light-to-dark gradient stroke), a red needle with a soft shadow, serif labels with slight tracking |

  *(manual: previews, before/after)*

- **R6** The number stays the largest element and keeps its position and frame on every face (gauge-themes R3/R4 layout). Nothing covers it: decoration is behind the number and below the pill. *(manual: "199" previews)*

### Mascot
- **R7** The mascot is redrawn in a "2.5D" kawaii anime style, still from shapes only:
  - head: a circle with a vertical shading gradient (lighter top) and a soft drop shadow beneath
  - hair: a bangs shape over the top third, tinted from the theme accent, with a lighter highlight streak
  - eyes: large ovals with an iris radial gradient, a dark pupil, a big upper highlight and a small lower highlight, and an upper lash line; eyebrows change per mood
  - cheeks: two soft radial-gradient blushes
  - mouth and accessories per mood as before (sleepy "z", worried sweat drop, startled "!"), restyled to match

  Colours derive from the theme: ink = `number`, tint = `accent`, fill = accent at low opacity over the background. *(manual: "Moods × faces" preview)*

- **R8** Mood expressions keep their meaning (speed-mascot R1–R3): `happy` is the peak, `worried` shows concern. The blink closes the eyes (lids in the head colour) for 0.15 s; the crossfade and Reduce Motion rules are unchanged. *(manual)*

- **R9** Size ceiling becomes 84 pt (floor 44 pt, 18% of the diameter). Placement rules are unchanged. *(unit: `MascotPlacementTests` updated)*

- **R10** Contrast: eyes, mouth and accessories keep ≥ 3:1 against the face fill; number/placeholder/secondary contrast tests from gauge-themes R8 still pass unchanged. *(unit: existing tests)*

### Unchanged behaviour
- **R11** Reduce Motion, VoiceOver, no speed-based colours, the mood curve and the picker flow are unchanged. All existing tests pass without modification except the two named in R9. *(unit: full suite)*

## User flows & UI
No new flows. The picker thumbnails render the new styling because they share `GaugeDisplay`. Face names in the picker use the face's secondary font.

## Data & API
- **`Theme.Typeface`** replaces `Theme.Design`: `number` and `secondary` PostScript names. `Theme.font(role:size:)` builds a `Font` from a `UIFontDescriptor` with the tabular-figures feature (`kNumberSpacingType` / `kMonospacedNumbersSelector`) for the number role, and `Font.custom(_:size:relativeTo:)` for text-style-relative roles.
- **Fonts**: `Xpeet/Resources/Fonts/<Family>/…ttf` + `OFL.txt`. Registered through `UIAppFonts` in an `info:` block in `project.yml` (XcodeGen generates `Xpeet/Resources/Info.plist`, which is derived and gitignored, like the xcodeproj).
- **Decoration views**: `Faces/FaceDecor.swift` with small reusable views (`BezelRing`, `Vignette`, `Scanlines`, `PaperGrain`), each `Equatable` on its inputs.
- **Mascot**: `MascotView` rewritten; `MascotPlacement.sizeRange` becomes `44...84`.
- No persistence or ViewModel changes.

## Non-functional
- **Performance:** textures are `Canvas` or gradient layers, drawn on size/theme change only; `.drawingGroup()` on glow stacks. No `TimelineView`, no shaders.
- **Privacy:** none. No new permissions.
- **App size:** +~0.8 MB of fonts.
- **Localization:** no new strings.

## Out of scope
- Image assets, Lottie/Rive, Metal shaders, 3D (SceneKit/RealityKit).
- A mascot body, arms or idle motion beyond the blink.
- Orbitron / Playfair Display (no tabular digits; would need per-digit layout).
- Alternate app icons, theme-specific icons.

## Flagged concerns
- **Licensing:** all four fonts are SIL OFL 1.1 without Reserved Font Names. Obligation: ship each `OFL.txt` unmodified and never subset or convert the TTFs. No on-screen credit is required.
- **Generated Info.plist:** XcodeGen rewrites it on every `xcodegen generate`, so it is gitignored. Anyone adding Info.plist keys must do it in `project.yml`.
- **Variable fonts:** that `UIAppFonts` exposes named instances (`Nunito-Black`, `OxaniumRoman-ExtraBold`, `BodoniModa-Black`) on iOS 17 is backed by forum reports, not Apple docs. R2's unit test is the gate; if it fails, the fallback is a `kCTFontVariationAttribute` descriptor with `wght` set per role (recorded in the plan).
- **Driving safety:** unchanged. Decoration is static; no new motion.
- **Taste:** Oxanium and Bodoni Moda replace the intent's Orbitron / Playfair examples for the tabular-digit requirement. The owner accepted automatic approval of this spec on 2026-10-20.

## Open questions
Carried from the intent:
- *Which fonts?* **Answered:** R1.
- *Body/arms?* **Answered:** head only (Out of scope).
- *Mascot size?* **Answered:** ceiling 84 pt (R9).

Raised by this spec:
- The mascot's "z" and "!" use the active face's number font instead of the system rounded font, so they match. Proposed and included in R7.
