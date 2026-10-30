# Spec: UI redesign from the Stitch "Xpeet Anime Speedometer" project

**Intent:** intent/2026-10-20-ui-redesign.md  **Status:** approved
**Depends on:** `specs/gauge-themes`, `specs/speed-mascot`, `specs/visual-polish`, `specs/engine-sound-clip` (all merged).

The target look is the Stitch project `2676886462094675705` (design system "Nocturne Precision").
Scaled references of the 10 reviewed iPhone frames and the mascot renders are in `specs/ui-redesign/design/`.
This spec changes how the screen looks and adds one mood. Where a Stitch frame and this spec differ, this spec wins. Known differences:
- Searching shows "--", not a dimmed number.
- The Retro number stays in its centre disc and does not overlap the hub.
- The mic chip wraps rather than truncating.
- There are no telemetry extras.

It supersedes these approved requirements (each earlier spec gets a note in the implementation commit):
- `specs/speed-mascot`:
  - R1: six moods become seven (R4).
  - R2: Unavailable maps to `sad`, not `searching` (R4).
  - R8: no longer drawn in code (R1).
  - R9: blink only while `calm` (R3).
  - R12: size range (R5).
- `specs/visual-polish`:
  - R3: unit pill font (R14).
  - R7, R8: mascot drawing and blink lids (R1, R3).
  - R9: size (R5).
  - Out of scope "Image assets" (R1).
- `specs/gauge-themes`:
  - Minimal ring palette (R9).
  - "The status chip and Open Settings stay at the bottom edge" (R6, R7).

## Requirements

### Mascot artwork
- **R1** The mascot is a bitmap portrait badge, not shapes. Eight images live in the asset catalog under a `Mascot` namespace. Each comes from one Stitch screen:

  | Asset | Used for | Stitch screen |
  |---|---|---|
  | `Mascot/calm` | `calm` | `3b0a277f3473412d943417d0fd115da8` |
  | `Mascot/happy` | `happy` | `be0d05d91a094a4d872b3ff0e8c4fdd2` |
  | `Mascot/worried` | `worried` | `47ae8d8c55f14956821e88aee85e52cc` |
  | `Mascot/startled` | `startled` | `a1df213e6dfb468da55976c94c620e33` |
  | `Mascot/sleepy` | `sleepy` | `25081c1b028d4a74baedd5b5f0194e15` |
  | `Mascot/searching` | `searching` | `d9ea4e5c5a7d491f881a8a2b04cd8d0a` |
  | `Mascot/sad` | `sad` (R4) | `faa60f3fefc44772bb0f777a7c646e5c` |
  | `Mascot/blink` | the blink frame (R3) | `471c14750acb47259f899c419334545b` |

  Each image:
  - is cropped to the bounding square of the render's circular badge;
  - is resized to 288×288 px (3× the 96 pt maximum, R5) and stored as a single-scale JPEG;
  - is clipped to a circle when drawn, so nothing outside the badge shows.

  (Amended in planning: PNG with alpha was about 0.95 MB in total.) All eight together are under 600 KB. *(unit: every `Mood` resolves to an asset that loads, plus the blink asset; total size checked in review)*

- **R2** The same character appears on every face. Hair and colours are not tinted by the theme. *(review)*

- **R3** Blink. While the mood is `calm`, the badge swaps to `Mascot/blink` for about 0.15 s every random 3–6 s. Other moods do not blink, because the blink frame is calm's face. Blinking stops when the app is not active or Reduce Motion is on. It is a scheduled one-off, not a per-frame loop. *(manual)*

- **R4** A seventh mood, `sad`, shows while the speedometer is **Unavailable** (denied, restricted or Location Services off). **Acquiring** still shows `searching`. **Amended** by `specs/precise-location/spec.md` R4, R7: `sad` also shows while Precise Location is off.
  - Leaving Unavailable for Acquiring returns to `searching` immediately.
  - The rest of the mood curve, debounce and braking are unchanged (speed-mascot R2–R6).

  *(unit: MoodResolver and ViewModel)*

- **R5** The badge is 22% of the gauge diameter, clamped to 44–96 pt. The placement rules are unchanged:
  - portrait above the gauge, landscape on the leading side;
  - if it doesn't fit, it shrinks to the free space down to 44 pt, and hides only below that (amended in build: otherwise the sad face never showed on iPhone SE when location is denied);
  - never shrinks the gauge.

  A mood change crossfades over 0.3 s, or is instant with Reduce Motion. The badge has a soft accent glow ring as in the frames, static and not animated. *(unit: `MascotPlacementTests` updated; manual)*

- **R6** The badge is decorative and hidden from VoiceOver. There is no tap action and no mood caption. *(manual: Accessibility Inspector)*

### Screen chrome (all faces)
- **R7** **Status chip**:
  - Position:
    - Portrait: top centre, in a top row it shares with the face button.
    - Landscape: at the bottom edge, as today.
    - The portrait top row is always reserved, so the gauge never changes size when the chip appears or goes away.
    - **Amended** by `specs/trip-stats/spec.md` R12: the trip line sits under the gauge in portrait and right of the gauge in landscape; the chip keeps its place.
    - **Amended** by `specs/osm-map/spec.md` R3: in map mode the chip keeps the same positions, over the map.
  - Look: a frosted-glass rounded rectangle, 18 pt radius, so wrapped text reads well (amended in build; was "capsule") (system material tinted with the theme's chip fill, with a 1 pt hairline that is brighter at the top). It holds a small accent status dot, the SF Symbol icon and the text.
  - The text wraps to as many lines as it needs and is never truncated. The chip never overlaps the face button.

  *(manual: frames "searching", "weak-signal", "mic-off", "retro-location-off")*

- **R8** **Face button**: a 44 pt frosted-glass circle with the accent palette glyph, top trailing, vertically centred in the top row in portrait. *(manual)* **Amended** by `specs/osm-map/spec.md` R1, R3: a mode button mirrors it top leading; in map mode the face button and the mascot are hidden.

- **R9** **Minimal ring palette** becomes Nocturne Precision:

  | Token | Value |
  |---|---|
  | background centre | `#0D121D` |
  | background edge | `#080B11` |
  | number | `#F5F8FC` |
  | placeholder | `#A7B2C2` (amended: 7:1 needed) |
  | secondary text (hint) | `#8E9BAE` |
  | accent | `#00F2FE` |
  | accent deep | `#4FACFE` |
  | chip text | `#C9D3E0` |
  | scale label | `#F5F8FC` |

  The other faces keep their palettes, except where R11–R13 add tokens. *(unit: contrast tests, R16)*

### Faces (geometry, scale and number layout unchanged)
- **R10** **Minimal ring**:
  - the glowing cyan progress ring with a bright tip dot;
  - a small "SPEED" caption with a trend glyph above the number;
  - faint tick marks at the scale's major positions outside the track.

  *(manual: frame "minimal-ring")*

- **R11** **Analog sport**:
  - a cyan progress arc drawn along the tick ring from 0 to the current reading, in addition to the needle;
  - a red zone, where ticks and labels are drawn in a red token (`#FF5A4F`) from 160 km/h or 100 mph to the end of the scale;
  - the chrome rim and the dark centre disc with the number stay.

  The red zone is a fixed part of the scale. It never depends on the current speed. *(unit: red-zone start fraction per unit; manual: frames "analog-sport", "landscape")*

- **R12** **Digital HUD**:
  - a circular frame: a thin dashed circle, four corner brackets and four cardinal ticks, all in the accent at reduced opacity;
  - the number with its glow at the centre, the unit pill below it, and the 20-segment bar inside the circle under the pill.

  *(manual: frames "digital-hud", "mic-off")*

- **R13** **Retro**:
  - a thicker polished chrome bezel (light-to-dark gradient ring with a highlight);
  - a red-zone arc in the accent from 160 km/h or 100 mph to the end of the scale (static, as in R11).

  The serif number stays in its centre disc, clear of the needle hub. *(manual: frames "retro", "retro-location-off")*

### Typography and controls
- **R14** **Space Grotesk** (SIL OFL 1.1) is bundled, unmodified from google/fonts, with its `OFL.txt` (shipped as `SpaceGrotesk-OFL.txt`). Its Bold instance is used, because the font has no SemiBold instance (amended in build), for:
  - the "SPEED" caption
  - the unit pill text
  - the status chip text
  - the Open Settings hint
  - the picker's "Active" tag

  Each face keeps its own font for the number, scale labels and picker names. Text scales with Dynamic Type relative to its text style, capped as today. *(unit: the PostScript name resolves; the font and licence are in the bundle)*

- **R15** **Unit pill**: a frosted-glass pill showing the unit in uppercase ("KM/H", "MPH") and a small swap glyph (`arrow.up.arrow.down`, decorative). Tapping it toggles the unit as today. Its VoiceOver label, value and hint are unchanged. *(manual)*

- **R16** **Contrast** (gauge-themes R8 targets, every face):
  - number ≥ 7:1 against the background centre;
  - placeholder, scale labels, chip text over the chip fill, Open Settings label and the hint text ≥ 4.5:1;
  - red-zone ticks and labels ≥ 3:1.

  *(unit: `GaugeFaceTests`)*

- **R17** **Open Settings** (denied only): **Amended** by `specs/precise-location/spec.md` R5: no longer denied-only, as it also shows while Precise Location is off, with a hint line that depends on the reason and may wrap to two lines.
  - a full-width (max 360 pt) rounded rectangle button (16 pt radius) under the gauge, filled with the accent and using the theme's button label colour;
  - a gear glyph beside the label;
  - one line below it: "Enable Location in Settings to see your speed", in the secondary text colour.

  The behaviour is unchanged. *(manual)*

### Picker sheet
- **R18** The sheet has:
  - the title "Gauge style", the subtitle "Choose your instrument cluster appearance" and "Done";
  - a 2×2 grid of rounded (16 pt) glass cards, each with a live mini gauge (as today) and the face name.

  The selected card has a 2 pt accent border, a check badge and an "Active" tag. VoiceOver: each card keeps its label and `isSelected` trait; the check and tag are hidden. *(manual: frame "picker")*

### Unchanged behaviour
- **R19** These are unchanged:
  - speed filtering, units, states, the mood curve and braking (apart from R4), engine sound and persistence;
  - the speed accessibility label, and "199" never clipping;
  - no speed-based gauge colours, and no continuous animation (glows and glass are static).

  All existing tests pass, except those this spec changes: mood count, the Unavailable mood, mascot palette tests and placement constants. *(unit: full suite)*

## User flows & UI
No new screens or flows. States, with references in `design/`:

| State | Chip (portrait top) | Number | Mascot | Extra |
|---|---|---|---|---|
| Acquiring | "Searching for GPS…" | `--` | `searching` | |
| Live | none | speed | per mood curve | |
| Live, weak signal | "Weak GPS signal" | speed | per mood curve | |
| Live, mic denied, no location status | mic chip, wrapped | speed | per mood curve | |
| Unavailable, denied | "Location access is off" | `--` | `sad` | Open Settings with hint |
| Unavailable, Precise Location off | "Precise Location is off" | `--` | `sad` (may hide on iPhone SE portrait) | Open Settings with "Turn on Precise Location under Location to see your speed" |
| Unavailable, restricted / services off | reason text | `--` | `sad` | |

Landscape keeps the gauge large on the trailing side, the badge on the leading side and the chip at the bottom (frame "landscape").
The picker opens from the face button (frame "picker").
Accessibility: R6, R14, R15, R16 and R18. Dynamic Type applies to chip, pill, hint and picker text, with the existing caps.

## Data & API
- **`Mood`** gains `case sad`.
- **`MoodResolver`** gains `mutating func unavailable() -> Mood`. It resets like `lost()` and returns `.sad`. `SpeedometerViewModel.becomeUnavailable` calls it; the other `lost()` paths stay.
- **`MascotView`** shows `Image("Mascot/<mood>")`, swapping to `Mascot/blink` during a calm blink. It keeps the blink task and crossfade.
- **`Theme.mascot`** and `MascotPalette` are removed.
- **`Theme`** gains:
  - `redZone: UInt32?` (Analog sport and Retro);
  - a shared caption typeface: Space Grotesk Bold (`SpaceGrotesk-Light_Bold`), whose PostScript name is confirmed by test.
- **`GaugeGeometry`** gains `redZoneStartFraction(for: SpeedUnit)`: 160/200 for km/h, 100/130 for mph.
- **Assets:**
  - `Xpeet/Resources/Assets.xcassets/Mascot/` (folder with "Provides Namespace") with eight image sets;
  - `Xpeet/Resources/MASCOT-SOURCE.txt` records the Stitch project and screen ids, the date and the processing steps;
  - the processing (crop, mask, resize) is a script in `scripts/`, so the images can be regenerated.
- **Fonts:** `Xpeet/Resources/Fonts/SpaceGrotesk/SpaceGrotesk[wght].ttf` + `OFL.txt`, registered in `project.yml` `UIAppFonts`.
- **Persistence:** none new.

## Non-functional
- **Performance:**
  - Glass uses system materials. Glows, brackets and bezels are static layers, redrawn on size, unit or theme change only.
  - The badge image is decoded once per mood.
  - No `TimelineView` and no shaders.
- **App size:** about +0.6 MB (images under 600 KB, font about 130 KB).
- **Privacy:** no new data, permissions or Info.plist usage strings.
- **Localization:** new strings "SPEED", "Active", "Choose your instrument cluster appearance" and "Enable Location in Settings to see your speed".

## Out of scope
Each of these can be a later intent:
- Stitch extras:
  - GPS accuracy, lock percentage, latency and "Synced";
  - ~~trip distance~~ (now in `specs/trip-stats/spec.md`), peak or top speed, lateral G, altitude;
  - HUD mirror mode, volume slider, "Sport tune";
  - the AI co-pilot text.
- The mood caption under the badge.
- Per-face hair tints.
- Blink frames for moods other than calm.
- 3D/RealityKit.
- Moving the landscape chip.
- iPad layouts.

## Flagged concerns
- **Artwork rights:** the mascot renders come from Google Stitch's image generation. Fine for this personal, sideloaded build. Before any distribution, the owner must confirm the usage terms for Stitch outputs and that the character doesn't closely resemble an existing one. `MASCOT-SOURCE.txt` records where each image came from.
- **Driving safety (App Review 1.4.4/1.4.5, not binding):**
  - The badge grows (up to 96 pt) and is a detailed bitmap: slightly more visual load. It is still static apart from a calm-only blink.
  - The red zone is a fixed scale marking, not a speed-dependent warning colour.
  - `sad` shows only when location is unavailable, never as a judgement of driving.
- **Supersedes approved requirements:** listed at the top; notes go into the earlier specs in the same commit.
- **Font licence:** Space Grotesk is OFL 1.1. Ship `OFL.txt` unmodified, and don't subset or convert the font. Whether it has a Reserved Font Name gets checked against the downloaded `OFL.txt` (the test from visual-polish checks the header).
- **No privacy, security or payments impact.**

## Open questions
Carried from the intent, all answered by the owner on 2026-10-20:
- *Blink?* **Answered:** kept, using a generated calm-eyes-closed frame (R3).
- *Hair tint per face?* **Answered:** one fixed character (R2).
- *Sad for location off?* **Answered:** yes (R4).
- *iPhone frames first?* **Answered:** regenerated and reviewed (`design/`).
- *Mood caption?* **Answered:** no (R6).
- *Space Grotesk?* **Answered:** yes, captions only (R14).

Raised by this spec:
- Badge size 22%, 44–96 pt (R5). **Approved** by the owner (2026-10-20); to be checked on device.
- Blink only in `calm` (R3). **Approved.** Other moods would need their own closed-eye frames.
- The portrait top row is always reserved for the chip (R7), so the gauge never jumps. The portrait gauge is width-bound, so it keeps its size. The row takes about 52 pt from the space above the gauge, which still fits a 75 pt badge on iPhone SE. **Approved.** (Built at 76 pt so the mic chip, which wraps to three lines, fits at the default text size. At large Dynamic Type a longer chip still grows the row and shifts the gauge down, which is accepted.)
