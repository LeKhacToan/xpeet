# Plan: Arc gauge redesign for the speed screen

**Spec:** specs/speedometer-gauge/spec.md
<!-- Produced in Claude Code plan mode. Update in the same commit when implementation diverges. -->

## Design summary
- The logic stays in the ViewModel:
  - `SpeedUnit.gaugeMaximum` (200 / 130)
  - `SpeedometerViewModel.gaugeFraction`: `displayedSpeed / gaugeMaximum`, clamped to 0…1, and 0 without a reading
  - `SpeedometerViewModel.statusSymbol`: an SF Symbol name per state, nil when `statusText` is nil

  The View only renders these values.
- The gauge is a `private struct SpeedGauge: View` inside `SpeedometerView.swift`, with its own `#Preview`. It stays in the same file, so:
  - CLAUDE.md's "one View + one ViewModel per feature folder" still holds
  - the eval greps on `SpeedometerView.swift` still apply
  - no new source file needs `xcodegen`
- The arc is two `Circle().trim(from: 0, to:)` strokes, rotated 135° so the 270° sweep opens at the bottom, with `lineCap: .round`:
  - **track:** `trim(to: 0.75)`, white at 10% opacity
  - **progress:** `trim(to: 0.75 * fraction)`, filled with a fixed `LinearGradient` from deep mint `#6CCB97` (lower left) to pastel green `#9FE3B5` (upper right), plus a static `.shadow` glow in the brand colour
  - The stroke width is 7% of the diameter.

  `AngularGradient` was rejected: the round cap at the start of the arc samples the wrapped end colour, which leaves a visible seam.
- Layout:
  - The status chip and the button live in `.safeAreaInset(edge: .bottom)`.
  - A `GeometryReader` measures the rest of the screen, and the gauge diameter is `min(width, height)`.
  - The number font is `0.4 × diameter`: SF Rounded heavy, `.monospacedDigit()`, `lineLimit(1)`, `minimumScaleFactor(0.2)`, and a frame width of `0.72 × diameter` inside the ring, so "199" always fits (R12).
  - The unit pill is an overlay aligned to the bottom of the gauge square and lifted by 5% of the diameter, so it sits in the opening between the arc's ends. *(Deviation: the lift was added after the simulator screenshot showed the pill hanging below the arc.)*
- Brand colour: `Palette.brand = Color("AccentColor")`, not `Color.accentColor`. *(Deviation: `Color.accentColor` follows the environment tint, which is system blue in `ImageRenderer` output and could differ in previews.)*
- Motion: `@Environment(\.accessibilityReduceMotion)` picks the behaviour.

  | Reduce Motion | Number transition | Arc animation |
  |---|---|---|
  | off | `.numericText(value:)` | `.smooth(duration: 0.6)` |
  | on | `.identity` | `nil` |

  The arc animation is keyed on `gaugeFraction`, so it animates only when a sample changes the value.
- Haptic: `.sensoryFeedback(.selection, trigger: viewModel.unit)` on the pill. It fires only on a user tap, never on speed.
- Background: `EllipticalGradient` from `#16231B` (centre) to `#0A0F0C`, ignoring safe areas, with `.preferredColorScheme(.dark)`.
- App icon: `scripts/generate-app-icon.swift` draws the 1024×1024 PNG with CoreGraphics (macOS AppKit, no dependencies). It renders the same arc style on the same background, and writes `Xpeet/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`. The image is opaque, with no alpha channel.

## Colours and contrast (R13)
Relative luminance: background centre `#16231B` ≈ 0.0145.

| Element | Colour | Measured against | Contrast | Needed |
|---|---|---|---|---|
| Number | white | background | 16.3:1 | 7:1 |
| Placeholder "--" | `Color(white: 0.7)` | background | 7.7:1 | 7:1 |
| Chip text | `Color(white: 0.75)` | chip fill (white 8% over background, ≈ `#2A352E`) | 6.9:1 | 4.5:1 |
| Pill text | brand `#9FE3B5` | pill tint (brand 16% over background, ≈ `#2C4234`) | 7.3:1 | 4.5:1 |
| "Open Settings" label | background `#0A0F0C` | brand fill | 12.9:1 | 4.5:1 |

## Files that change
- `Xpeet/Features/Speedometer/SpeedometerViewModel.swift` (modified): `SpeedUnit.gaugeMaximum`, `gaugeFraction`, `statusSymbol`.
- `XpeetTests/SpeedometerViewModelTests.swift` (modified): new tests for R2 and R6. Existing tests are untouched.
- `Xpeet/Features/Speedometer/SpeedometerView.swift` (modified): the new layout, the `SpeedGauge` subview, the chip, the pill, Reduce Motion, the haptic, and previews (Live, Live landscape, Above max, Acquiring, Denied, Gauge).
- `Xpeet/Resources/Assets.xcassets/AccentColor.colorset/Contents.json` (modified): `#9FE3B5`.
- `Xpeet/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` (modified) and `AppIcon.png` (new).
- `scripts/generate-app-icon.swift` (new).
- `intent/2026-10-19-speedometer-gauge.md` (new) and `specs/speedometer-gauge/spec.md` (new).
- `specs/speedometer/spec.md` (modified): R2, Layout and Out of scope are marked as superseded.

## Order of work
1. Intent, spec and this plan.
2. **ViewModel, test-first:** add the tests for `gaugeFraction` and `statusSymbol`, see them fail, implement, then run `scripts/test.sh`.
3. **View:** gauge, layout, chip, pill, motion, haptic, previews. Then `scripts/build.sh`.
4. **Assets:** set AccentColor, write and run the icon script, then `xcodegen generate`.
5. **Simulator check:**
   - Grant location, simulate a moving route with `simctl location start --speed`, and take screenshots in portrait and landscape.
   - Check the home-screen icon.
   - *(Deviation: `simctl location start --speed` does not deliver a speed to `liveUpdates`; it stays in Acquiring, as the first plan warned. Live, landscape "199" and Denied were checked by rendering `SpeedometerView` with `ImageRenderer` in a throwaway test, deleted before commit. Freeway Drive in Simulator > Features > Location stays a manual check.)*
6. `scripts/verify.sh`.

## Risks
- **Number size vs ring (R12):** the ring takes width away from the number, which is the trade-off flagged in the spec. `minimumScaleFactor` plus a fixed frame width guarantees no clipping. The landscape preview and a simulator screenshot check "199".
- **Dynamic Type inside the ring:** at accessibility sizes the pill could grow into the number. It is capped at `.accessibility2` (R14). The chip and the button sit outside the gauge, so they scale freely.
- **Reduce Motion can't be previewed:** `accessibilityReduceMotion` is read-only in the environment, so R11 is a manual check only.
- **Glow cost:** one static shadow on a single stroke, redrawn at about 1 Hz. This is negligible. There is no blur stacking and no `TimelineView`.
- **Accent as global tint:** setting `AccentColor` tints every system control. The only one is "Open Settings", which is intended (R9).
- **Untested on iOS 17:** only the iOS 27.1 simulator is installed. Every API used is iOS 17 or older:

  | API | Available since |
  |---|---|
  | `sensoryFeedback` | iOS 17 |
  | `EllipticalGradient` | iOS 15 |
  | `numericText` | iOS 17 |
  | `safeAreaInset` | iOS 15 |

## Proof
| Req | Proof |
|---|---|
| R1 | Previews "Live" and "Gauge"; simulator screenshot |
| R2 | `testGaugeFractionIsZeroWithoutReading`, `testGaugeFractionScalesWithKmhMaximum`, `testGaugeFractionUsesMphMaximum`, `testGaugeFractionClampsAboveMaximum` |
| R3 | Review: the gradient is a constant and has no speed input |
| R4 | Previews; screenshot |
| R5 | Review: `grep -n accent` shows only the arc, the pill, the chip icon and the button |
| R6 | `testStatusSymbolPerState`; screenshot of the Acquiring chip |
| R7 | Manual: tap the pill, the unit switches and the haptic plays on device; hit area ≥ 44 pt |
| R8 | "Acquiring" preview |
| R9 | "Denied" preview |
| R10 | Manual: Freeway Drive or a `simctl` route |
| R11 | Manual: Reduce Motion on, nothing animates |
| R12 | "Above max" landscape preview with 199; landscape screenshot |
| R13 | Contrast table above |
| R14 | Existing accessibility tests pass; manual at the largest text size |
| R15 | Home-screen screenshot; the icon PNG is 1024×1024 with no alpha |

`scripts/verify.sh` ends with `lint: OK` and `** TEST SUCCEEDED **`.
