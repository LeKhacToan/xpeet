# Spec: Arc gauge redesign for the speed screen

**Intent:** intent/2026-10-19-speedometer-gauge.md  **Status:** approved

This spec changes the look of the single speed screen. It replaces these parts of `specs/speedometer/spec.md`:
- R2
- the "Layout" paragraph
- "Arc or needle gauge" in Out of scope

> **Superseded in part** by `specs/gauge-themes/spec.md`: R1 (the arc is now the Minimal ring face), R4 (Retro is light), R5 and R13 (palette and contrast are per face), and the light-mode / ticks / needle exclusions in Out of scope.

Every other requirement there stays in force, and those are cited below as "speedometer R<n>".

## Requirements

### Gauge
- **R1** The speed number sits at the centre of an arc gauge with a 270° sweep and the opening at the bottom. The arc has two layers:
  - a dim full-length track
  - a progress arc in the brand colour, starting at the lower-left end

  *(manual, previews)*
- **R2** The progress arc fills in proportion to the displayed speed, up to a fixed maximum per unit: 200 km/h, or 130 mph.
  - The fraction is `displayed speed / maximum`, clamped to 0…1. Above the maximum the arc stays full and the number still shows the real speed.
  - Without a live reading the fraction is 0.
  - The fraction uses the same rounded value as the number, so the arc and the number always agree.

  *(unit)*
- **R3** The arc colour never depends on speed. It is one fixed pastel-green gradient, the same at every speed. There are no red or amber zones, no alerts, and no haptics or sounds tied to speed. *(review)*

### Look
- **R4** The screen always uses the dark appearance, whatever the system setting is. The background is a static near-black gradient with a subtle green tint: centre `#16231B`, edges `#0A0F0C`. It has no animation. *(manual, previews)*
- **R5** The brand colour is a pastel green, `#9FE3B5`, stored as the `AccentColor` asset. It is used only for:
  - the progress arc and its soft static glow
  - the unit pill
  - the status icons
  - the "Open Settings" button

  *(review)*
- **R6** The status line becomes a capsule chip with an icon and the existing status text. The icon is chosen per state:

  | State | Icon |
  |---|---|
  | Acquiring | `location.magnifyingglass` |
  | Live, weak signal | `exclamationmark.triangle` |
  | Unavailable | `location.slash` |

  When there is no status, there is no chip. The icon is decorative and hidden from VoiceOver. *(unit: icon per state; manual)*
- **R7** The unit label is a capsule pill, tinted with the brand colour, in the opening at the bottom of the arc. It is still the unit toggle (speedometer R14) with a hit area of at least 44×44 pt. Tapping it plays a light selection haptic. *(manual)*
- **R8** When there is no reading ("--"), the placeholder is shown in a light grey instead of white, so a missing value does not look like a live one. *(manual, previews)*
- **R9** "Open Settings" uses the brand colour with dark label text. *(manual)*

### Motion
- **R10** By default the number keeps its digit-by-digit numeric transition (speedometer R12), and the progress arc animates to its new length with the same short smooth animation (about 0.6 s). Nothing animates between samples. *(manual: Freeway Drive)*
- **R11** With Reduce Motion on, the number and the arc both change instantly: no numeric transition and no arc animation. *(manual: Settings > Accessibility > Motion > Reduce Motion)*

### Kept from the first spec
- **R12** "199" is never truncated or clipped in portrait, landscape left or landscape right (speedometer R3). The number scales with the gauge size and may only shrink further to fit. *(manual; landscape preview)*
- **R13** Contrast against the lightest point of the background (`#16231B`) must be at least:

  | Element | Minimum contrast |
  |---|---|
  | Number | 7:1 |
  | Placeholder | 7:1 |
  | Status text | 4.5:1 |
  | Unit pill text on its tint | 4.5:1 |
  | "Open Settings" label | 4.5:1 |

  *(manual: computed values in the plan, spot-checked with Accessibility Inspector)*
- **R14** The VoiceOver strings and traits from speedometer R21 are unchanged. Dynamic Type for the unit pill, the chip and the button follows speedometer R22. The unit pill is capped at the `accessibility2` size so it never overlaps the number inside the gauge. *(unit: existing tests; manual)*

### App icon
- **R15** The app has a 1024×1024 opaque icon in the same style: a dark green-black tile with a pastel-green 270° arc, about two-thirds filled. The icon is made by a script in the repo, so it can be regenerated. *(manual: home screen in the simulator)*

## User flows & UI

**Layout, portrait.** Top to bottom:
1. The gauge square: as large as fits, centred.
2. Inside the gauge:
   - The number at the centre.
   - The unit pill in the bottom opening.
3. The status chip and, when denied, the "Open Settings" button, at the bottom edge.

**Layout, landscape.** The gauge fits the height that is left above the status area. It stays centred.

| State | Number | Arc | Chip | Extra |
|---|---|---|---|---|
| **Acquiring** | `--` (grey) | empty | `location.magnifyingglass` "Searching for GPS…" | none |
| **Live** | speed (white) | filled to speed / max | none | none |
| **Live, weak signal** | speed (white) | filled to speed / max | `exclamationmark.triangle` "Weak GPS signal" | none |
| **Unavailable** | `--` (grey) | empty | `location.slash` + reason | "Open Settings" when denied |

**Unit switch.** Tap the pill. You feel a selection haptic, and the number, the pill and the arc switch to the other unit's scale at once, without animating.

**Accessibility.**
- VoiceOver output is unchanged (speedometer R21). The gauge arc is decorative and hidden from VoiceOver, because the number already says the speed.
- Reduce Motion: see R11.

## Data & API
- The ViewModel gains two View-ready outputs. Both are derived from existing state and are not stored or persisted:
  - `gaugeFraction: Double` (R2)
  - `statusSymbol: String?` (R6)
- `SpeedUnit` gains `gaugeMaximum` (200 / 130).

## Non-functional
- **Performance:** nothing animates per frame (speedometer Non-functional). The background and the glow are static. The arc redraws only when a sample changes the value.
- **Privacy:** no change.
- **Localization:** no new user-visible strings.

## Out of scope
- Light mode.
- Liquid Glass / `glassEffect` (iOS 26), `MeshGradient` (iOS 18).
- Tick marks or scale labels on the gauge, a needle.
- Speed-limit markers, speed-based colours, over-speed alerts.
- Dark and tinted variants of the app icon (iOS 18+).

## Flagged concerns
- **Smaller number:** the number now has to fit inside the ring, so it shrinks from about 50% of the shorter screen side to about 37%. On an iPhone 15 in portrait that is about 130 pt instead of 196 pt. It is still large, but the owner should confirm it reads well at arm's length in the car.
- **Driving safety (App Store guideline 1.4.4/1.4.5, not binding):** a filled arc does not encourage speeding as long as its colour stays fixed (R3). This is kept in the intent's constraints.

## Open questions
- *Gauge maximum?* **Answered (owner):** 200 km/h and 130 mph.
- *Brand colour?* **Answered (owner):** pastel green.
- *App icon and Reduce Motion?* **Answered (owner):** both in scope.
- *Light mode?* **Defaulted to dark only.** The owner didn't answer; the researcher recommends dark only for night driving.
- *Liquid Glass, speed-limit marker?* **Deferred**, see Out of scope.
