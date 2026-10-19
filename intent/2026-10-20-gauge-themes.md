# Intent: Selectable gauge faces and themes

**Owner:** toanlk  **Status:** accepted

## Problem
The speed screen has one fixed look: a pastel-green 270° arc on a dark background.
I want to switch between a few distinct, modern styles depending on mood, and the single style gets boring.

## Proposed outcome
- A small button on the speed screen opens a sheet with a thumbnail of each gauge face. Tapping one switches immediately.
- Each face has its own fixed colour palette and type style (face and palette are one choice):
  - **Minimal ring**: today's look, unchanged. This is the default.
  - **Analog sport**: a round dial with tick marks, scale labels and a needle. Dark.
  - **Digital HUD**: a large monospaced number and a segmented bar. Dark.
  - **Retro**: a cream-coloured dial with a classic needle and a serif number. This is the first **light** theme.
- The chosen face is remembered across launches.
- Switching face does not change the speed shown, the unit, or the status chips.
- Changing face is allowed at any time, including while moving.

## Affected users & systems
- Users: me (personal use, sideloaded).
- Screens: the speed screen (`SpeedometerView`), plus one new modal sheet (the face picker). There is still no navigation and no tabs.
- Spec: this intent replaces these parts of `specs/speedometer/spec.md`:
  - R1 "no other screen". A modal picker sheet is allowed.
  - The Out of scope bans on "needle gauge" and "settings screen". The face picker sheet is the only settings surface.
- Spec: this intent replaces these parts of `specs/speedometer-gauge/spec.md`:
  - R1: the 270° arc layout is now one face among several.
  - R4 "dark only": Retro is light. The other faces stay dark.
  - R5: brand colour use is now per face.
  - R13: contrast is checked per face against that face's background.
  - The Out of scope bans on tick marks, scale labels, needle and light mode.
- Later features (the mascot, the engine-sound trigger) take their colours from the active face, and may add their settings to the same sheet.

## Constraints
- iOS 17+, native SwiftUI only, no third-party dependencies, no new permissions. No `MeshGradient` (iOS 18) and no Metal shaders.
- Must still not encourage speeding:
  - No colour changes with speed on any face: no red or amber zones, and no redline.
  - No sounds or haptics tied to speed.
- Every face meets the existing rules:
  - Contrast at least 7:1 for the number and 4.5:1 for secondary text, against that face's own background.
  - "199" is never clipped in portrait or landscape.
  - Dynamic Type behaviour as today.
  - Reduce Motion: the needle, arc and number update without animating.
  - VoiceOver: the gauge drawing is decorative, and the number stays the only spoken element.
  - The picker is accessible: each face has a name, and the selected one is marked.
- Performance: redraw only on a new sample. No continuous per-frame animation. Static parts (ticks, labels) are not redrawn on every sample.
- The gauge maximum stays fixed at 200 km/h / 130 mph for every face.

## Open questions
- Neon/cyberpunk and car-dashboard faces: wanted later, not in this first set.
- Does the light Retro face follow the system appearance, or is it always light? Proposed: always light, since it is chosen deliberately.
- Separate palette choice per face, alternate app icons per theme, a custom 7-segment font: out of scope for now.
