# Intent: UI redesign from the Stitch "Xpeet Anime Speedometer" project

**Owner:** toanlk  **Status:** accepted

## Problem
After the visual polish the screen still reads as a developer build: the code-drawn mascot is far from the cute 3D anime
character I want, and the faces lack the glass, glow and depth of a premium instrument cluster.
I designed the target look in Google Stitch (project "Xpeet Anime Speedometer", id `2676886462094675705`,
design system "Nocturne Precision"): 12 UI screens and 8 mascot renders.

## Proposed outcome
- **Mascot artwork.** The code-drawn face is replaced by the Stitch renders: one consistent 3D chibi character
  (lilac-blue bob, aviator goggles, blush, racing jacket) shown as a circular portrait badge with a thin rim.
  One image per mood: calm, happy, worried, startled, sleepy (sleep bubble), searching (glancing around).
  A mood change still crossfades. The badge sits above the gauge (portrait) or on the leading side (landscape), as today.
- **Nocturne Precision look** for the screen chrome on every face:
  - Status chip: a frosted-glass capsule with a small status dot and icon.
  - Gauge-style button: a frosted-glass circle, top trailing.
  - Unit pill: a frosted-glass pill with a small swap glyph.
  - "Open Settings": a full-width rounded button under the gauge, with a one-line hint below it.
- **Faces, restyled after the Stitch screens, same geometry and scale:**
  - Minimal ring: deep space background (`#080B11`), a cyan (`#00F2FE` to `#4FACFE`) glowing progress ring,
    and a small "SPEED" caption above the number.
  - Analog sport: a large cluster with a cyan progress arc over the ticks, a red zone at the top of the scale,
    and the number in a dark centre disc.
  - Digital HUD: a circular HUD with corner brackets, glowing digits and the segment bar inside the circle.
  - Retro: the cream dial with a polished chrome bezel, a red zone and the serif number.
- **Picker sheet:** 2x2 cards with a live mini gauge and the face name. The selected card has an accent border,
  a check and an "Active" tag.
- The number stays the largest element and keeps today's contrast targets.

## Affected users & systems
- Users: me (personal use, sideloaded).
- Screens: the speed screen in every state (acquiring, live, weak signal, location off, mic off) in both
  orientations, plus the picker sheet. No new screens.
- Assets: mascot images in an asset catalog (first image assets in the app). Possibly one more OFL font,
  Space Grotesk, for captions.
- Specs this changes:
  - `specs/speed-mascot` R8 and `specs/visual-polish` R7 ("drawn in code, no image assets", hair tinted by theme).
  - `specs/visual-polish` "no image assets" constraint.
  - Blink behaviour, depending on the open question below.
  - Gauge geometry, mood logic, persistence and engine sound are unchanged.

## Constraints
- iOS 17+, SwiftUI only, no third-party dependencies, no shaders, no continuous animation (as today).
- **Not adopted from Stitch**, because the app is a single screen with no extra features (`specs/speedometer`):
  - GPS accuracy or "99.8% lock" readouts, latency, "Synced".
  - Trip distance, peak/top speed, lateral G, altitude.
  - HUD mirror mode, volume slider, "Sport tune".
  - The AI co-pilot speech bubble ("Slow down a bit, pilot!").

  Any of these can be its own intent later.
- The Stitch frames are desktop-sized (2560x2048). The iPhone layout keeps today's placement rules and is
  rebuilt natively, not copied from the HTML.
- App size growth under about 2 MB. The images are 1024 px JPEGs, so they are resized to about 3x the display size.
- The artwork comes from Google Stitch's image generation, for a personal build. Check the licence before any distribution.
- Accessibility holds: VoiceOver reads the speed, the mascot is decorative, Dynamic Type, Reduce Motion, 44 pt targets.

## Owner decisions (2026-10-20)
- **Blink stays.** A matching "calm, eyes closed" frame was generated in Stitch
  (screen `471c14750acb47259f899c419334545b`). The blink swaps calm for this frame.
- **One fixed character** (lilac-blue hair) on every face. Hair is no longer tinted by the theme.
- **Sad render for "location off".** The unavailable state shows the sad face; acquiring keeps searching.
- **iPhone frames first.** The Stitch screens are regenerated as iPhone portrait and landscape frames,
  and the owner reviews them before the spec. Done: 10 iPhone frames reviewed and accepted.
- **No mood caption** under the badge (Stitch's "CRUISING" is dropped).
- **Space Grotesk** (OFL) is bundled for small captions only ("SPEED", the unit pill, status chip).
  Each face keeps its own font for the number.

## Open questions
- None.
