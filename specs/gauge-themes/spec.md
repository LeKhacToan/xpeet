# Spec: Selectable gauge faces and themes

**Intent:** intent/2026-10-20-gauge-themes.md  **Status:** approved

This spec lets the user choose among four gauge faces. Each face has its own fixed palette and type style.

It replaces these parts of `specs/speedometer/spec.md`:
- R1 "no other screen": one modal picker sheet is now allowed. There is still no `TabView` and no navigation stack.
- "needle gauge" and "Settings screen" in Out of scope.

It replaces these parts of `specs/speedometer-gauge/spec.md`:
- R1: the 270° arc is now the **Minimal ring** face, one of four.
- R4: dark only. Retro is light.
- R5: brand colour use is now per face.
- R13: contrast is now checked per face.
- "Light mode" and "Tick marks or scale labels on the gauge, a needle" in Out of scope.

Every other requirement in both specs stays in force. They are cited below as "speedometer R<n>" and "gauge R<n>".

## Requirements

### Faces
- **R1** There are exactly four faces, in this order:

  | Face | Raw value | Appearance | Default |
  |---|---|---|---|
  | **Minimal ring** | `minimalRing` | dark | ✓ |
  | **Analog sport** | `analogSport` | dark | |
  | **Digital HUD** | `digitalHUD` | dark | |
  | **Retro** | `retro` | light | |

  Each face has a localized display name. *(unit: `allCases` order, raw values, non-empty unique names)*

- **R2** *(Superseded by `specs/ui-redesign/spec.md` R9: Minimal ring uses the Nocturne Precision palette.)* **Minimal ring** looks exactly as it does today. It keeps gauge R1–R11 and today's palette (`#9FE3B5` brand, `#16231B`→`#0A0F0C` background). *(manual: compare with the `main` previews)*

- **R3** **Analog sport** is a round dial on a dark background. It has three layers:
  - Tick marks and scale labels along the same 270° sweep as the ring, with the opening at the bottom.
  - A needle that rotates from the lower-left end (0) to the lower-right end (maximum). The needle angle is `-135° + 270° × fraction`, where fraction is gauge R2's `gaugeFraction`: clamped, and 0 without a live reading.
  - The speed number in a centre disc (half the dial diameter), and the unit pill in the dial opening. The needle is a pointer that runs from the disc's edge to the rim, so it never crosses the number. *(Amended 2026-10-20, owner-approved, after review found a 3-digit number colliding with the needle and the end-of-scale label.)*

  The tick scale per unit:

  | Unit | Major ticks with labels | Minor ticks |
  |---|---|---|
  | km/h | every 20, from 0 to 200 | every 10 |
  | mph | every 20, from 0 to 120, plus a final major tick and label at 130 | every 10 |

  *(unit: needle angle for fraction 0 / 0.5 / 1 / >1 / no reading; tick values and labels for both units. manual: previews)*

- **R4** **Digital HUD** has no dial. It shows:
  - The speed number, large, in a monospaced font.
  - The unit pill under the number.
  - A horizontal bar of 20 segments under the unit pill. `round(fraction × 20)` segments are lit and the rest are dim. With no reading, none are lit.

  *(unit: lit-segment count for fraction 0 / 0.5 / 0.97 / 1 / no reading. manual: previews)*

- **R5** **Retro** uses the same dial geometry as Analog sport (R3: ticks, labels, needle, layout). It differs in look only:
  - A cream background.
  - Dark ink ticks and labels, a dark red-brown needle, and a serif number.

  It is always light, whatever the system appearance is. *(manual: previews in both system appearances)*

### Colour and safety
- **R6** Each face defines its own palette. The palette covers:
  - background
  - number
  - placeholder
  - accent (arc or needle, unit pill, status icons, "Open Settings")
  - track/dim
  - chip fill and chip text

  The whole screen, including the status chip and the "Open Settings" button, uses the active face's palette. *(review; previews)*

- **R7** No face changes colour with speed. There are no red or amber zones, no redline marking, no alerts, and no haptics or sounds tied to speed (gauge R3, now on every face). *(review)* **Amended** by `specs/break-reminder/spec.md` R3, R12: the break reminder is a time-based, silent status, not a speed alert.

- **R8** Contrast, checked per face against that face's own background (its lightest point for dark faces, its darkest point for Retro), must be at least:

  | Element | Minimum contrast |
  |---|---|
  | Number | 7:1 |
  | Placeholder | 7:1 |
  | Status text on chip | 4.5:1 |
  | Unit pill text on its tint | 4.5:1 |
  | "Open Settings" label | 4.5:1 |
  | Scale labels | 4.5:1 |

  *(unit: a pure WCAG contrast function run over every face's hex palette)*

### Choosing a face
- **R9** A face button (SF Symbol `paintpalette`) sits in the top-trailing corner of the speed screen in every face and every state. It has a hit area of at least 44×44 pt. Tapping it opens the picker sheet. *(manual)*

- **R10** The picker sheet: **Amended** by `specs/engine-clip-toggle/spec.md` R1: under the grid it also holds a "Sound" section with the "Engine sounds" switch and its help line.
  - It has the title "Gauge style" and a "Done" button.
  - It shows one thumbnail per face (R1 order) in a grid. Each thumbnail renders that face at a fixed sample reading: 88 in the current unit, live, no status. It also shows the face's name.
  - It opens at medium height and can be dragged to large. It can be dismissed by swiping down or by tapping Done.

  *(manual; previews of the sheet)*

- **R11** Tapping a thumbnail switches the speed screen to that face immediately, while the sheet stays open:
  - The selection is marked with a checkmark and an accent border, and a light selection haptic plays.
  - The switch itself is not animated.
  - Changing face is allowed in every state, including while moving.

  *(unit: `select(_:)` updates `face`. manual: haptic, no animation)*

- **R12** Changing face never changes:
  - the displayed speed, the unit, the state or the status text
  - the filter (no reset, so speedometer R9–R11 behave as if nothing happened)
  - the VoiceOver label

  *(unit)*

- **R13** The chosen face is saved locally and restored on the next launch. With nothing saved, or with an unknown saved value (e.g. a face removed later), the face is Minimal ring. *(unit: injected `UserDefaults` suite)*

### Kept on every face
- **R14** "199" is never truncated or clipped, on every face, in portrait, landscape left and landscape right (speedometer R3, gauge R12). The number may only shrink to fit. *(manual; a landscape preview per face)*

- **R15** Motion is the same on every face (**amended** by `specs/speed-accuracy/spec.md` R16: the animation is linear, at most 0.1 s):
  - By default, the number keeps its numeric transition, and the arc, the needle or the lit segments animate to a new sample with the same smooth animation (about 0.6 s).
  - With Reduce Motion on, everything changes instantly (gauge R10, R11).
  - Nothing animates between samples, except the mascot's periodic blink (`specs/speed-mascot/spec.md` R9).

  *(manual: Freeway Drive, with Reduce Motion on and off)*

- **R16** VoiceOver: **Amended** by `specs/engine-clip-toggle/spec.md` R12: it also covers the "Sound" heading (header trait) and the "Engine sounds" switch, read with its state and with the help line as its hint.
  - The dial, ticks, labels, needle and segments are decorative and hidden. The number stays the only speed element (speedometer R21, unchanged).
  - The face button has the label "Gauge style" and the hint "Double-tap to choose a gauge face". **Amended** by `specs/engine-clip-toggle/spec.md` R13: the hint is now "Double-tap for gauge faces and engine sounds", and the label "Gauge style" stays.
  - Each thumbnail is one button labelled with the face name, with the Selected trait on the active face. Its rendered contents are hidden.

  *(unit: label strings. manual: Accessibility Inspector)*

- **R17** Dynamic Type follows speedometer R22 and gauge R14 on every face:
  - The unit pill is capped at `accessibility2`.
  - Scale labels scale with the dial size, not Dynamic Type, so they never collide.
  - The picker sheet's names and title follow Dynamic Type up to accessibility sizes. The grid drops to one column when needed. **Amended** by `specs/engine-clip-toggle/spec.md` R12: the "Sound" heading, switch label and help line follow Dynamic Type the same way, wrapping and never truncated.

  *(manual: largest size, both orientations)*

## User flows & UI

**Layout per face.** *(Superseded by `specs/ui-redesign/spec.md` R7: in portrait the chip sits in a reserved top row; landscape keeps it at the bottom.)* The status chip and "Open Settings" stay at the bottom edge on every face (gauge layout). The face button is always top-trailing.

| Face | Centre | Bottom of gauge area |
|---|---|---|
| Minimal ring | number | unit pill in the arc opening (unchanged) |
| Analog sport / Retro | number in the centre disc; needle from disc to rim | unit pill in the dial opening |
| Digital HUD | number | unit pill, then the 20-segment bar |

**States, on every face.**

| State | Number | Gauge |
|---|---|---|
| **Acquiring** | `--` (placeholder colour) | needle at 0 / ring empty / no segments lit |
| **Live** | speed | filled to the fraction |
| **Live, weak signal** | speed | filled to the fraction, plus the weak-signal chip |
| **Unavailable** | `--` (placeholder colour) | needle at 0 / ring empty / no segments lit, plus the reason chip and "Open Settings" when denied or Precise Location is off |

The picker has no loading, empty or error state: the four faces are built in and always available.

**Flow.**
1. Tap the face button and the sheet opens.
2. Tap a thumbnail. The face behind the sheet changes at once and the checkmark moves.
3. Swipe down or tap Done.

On the next launch the same face is shown.

**Accessibility.** See R16–R17. Reduce Motion: see R15.

## Data & API
- **`GaugeFace`**: `enum GaugeFace: String, CaseIterable, Identifiable`. Raw values are listed in R1. It provides `displayName` (`String(localized:)`) and `theme`.
- **`Theme`**: a value type, with no SwiftUI state. It holds:
  - palette colours as hex `UInt32`, so contrast is unit-testable (R8)
  - font design (rounded / monospaced / serif) and weight
  - colour scheme (dark / light)
- **Pure geometry** (unit-tested):
  - needle angle for a fraction (R3)
  - tick values and labels per unit (R3)
  - lit-segment count (R4)
- **`SpeedometerViewModel`** gains:
  - `private(set) var face: GaugeFace`
  - `func select(_ face: GaugeFace)`

  Both persist via the injected `UserDefaults` under the key `gaugeFace`, using the same pattern as `toggleUnit()`/`speedUnit`.
- **Persistence:** one new `UserDefaults` key, `gaugeFace`. Nothing else.
- **Offline:** unchanged, fully offline.

## Non-functional
- **Performance:**
  - Redraw only on a new sample (speedometer Non-functional).
  - Static dial parts (ticks, labels, background) do not redraw per sample, only on a size or unit change.
  - No `TimelineView`, no shaders, no continuous animation.
- **Privacy:** no change. No new data and no new permission. The `gaugeFace` key is covered by the existing `UserDefaults` required-reason note.
- **Localization:** the new user-visible strings are written with `String(localized:)`/`Text("…")`: **Amended** by `specs/engine-clip-toggle/spec.md` R1, R13: new strings "Sound", "Engine sounds" and "Plays a short clip when the engine starts. Off stops the microphone.", and the face button hint becomes "Double-tap for gauge faces and engine sounds".
  - the four face names
  - "Gauge style", "Done"
  - the face button hint
- **Compatibility:** iOS 17 APIs only. One code path, with no `#available` branches.

## Out of scope
- Neon/cyberpunk and car-dashboard faces (later intent).
- Choosing a palette separately from a face, and user-defined colours.
- Retro following the system appearance, and light variants of the other faces.
- Per-face or user-set gauge maximum. It stays 200 km/h / 130 mph.
- ~~Custom fonts (e.g. 7-segment)~~ (bundled OFL fonts are now in scope: `specs/visual-polish/spec.md`), alternate app icons per theme, `MeshGradient`, Metal shaders, Liquid Glass.
- Swipe-to-change faces, `TabView` paging.
- Mascot and engine-sound settings in the sheet (their own specs). **Amended** by `specs/engine-clip-toggle/spec.md` R1: the "Engine sounds" switch is now in the sheet, and mascot settings stay out.

## Flagged concerns
- **Driving safety (App Review 1.4.4/1.4.5, not binding):**
  - The owner chose not to lock face changes while moving (R11). A tap target and a sheet while driving is a distraction risk. It is accepted for a personal build.
  - Faces stay safe because colour never depends on speed (R7).
- **Readability on dial faces:** on Analog sport and Retro the number sits in the centre disc at a font of 20% of the dial (Minimal ring: 40%). Resolved in build by moving it to the centre with no needle hub (owner-approved amendment to R3). The owner should still confirm it reads well at arm's length on a device.
- **Light theme at night:** Retro is bright in a dark car. It is the owner's deliberate choice (intent), and it is always light by design.
- **Supersedes approved requirements:** speedometer R1 and gauge R1/R4/R5/R13 change. Both earlier specs should get a "Superseded by `specs/gauge-themes/spec.md`" note in the same commit as the implementation.
- **CLAUDE.md Architecture:** if the plan adds a `Faces/` subfolder under `Features/Speedometer/`, CLAUDE.md's "one folder per feature" description needs a one-line update. That needs owner approval and an eval re-run (docs/ai-sdlc.md).
- **No privacy, security or payments impact.**
- **Unverified locally:** only an iOS 27.1 simulator is installed. iOS 17 rendering of the faces is not tested here (same accepted risk as the earlier specs).

## Open questions
Carried from the intent:
- *Neon/cyberpunk and car-dashboard faces?* **Deferred**, see Out of scope.
- *Does Retro follow the system appearance?* **Answered (intent, owner accepted):** always light (R5).
- *Separate palette per face, alternate app icons, custom 7-segment font?* **Deferred**, see Out of scope.
- *Lock face changes while moving?* **Answered (owner):** no (R11).
- *Face and palette as one choice?* **Answered (owner):** yes, one fixed palette per face (R6).

Raised by this spec:
- *Exact hex palettes for Analog sport, Digital HUD and Retro:* to be set in the plan. They must pass R8's contrast test.
- *Thumbnail sample reading:* 88 is the spec's default and can be changed in review.
