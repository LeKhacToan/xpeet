# Intent: Visual polish for the gauge faces and the mascot

**Owner:** toanlk  **Status:** accepted

## Problem
The four gauge faces and the mascot work, but they look plain: flat shapes, system fonts, a face made of dots and lines.
I want the screen to look like a designed product: each face with its own character and typography, and a mascot in a kawaii anime style with depth, not a flat emoji.

## Proposed outcome
- **Typography.** Each face gets its own bundled open-source font (SIL OFL), used for the speed number, scale labels and the unit pill:
  - Minimal ring: a soft rounded display font.
  - Analog sport: a sporty condensed sans.
  - Digital HUD: a technical/sci-fi display font with tabular digits.
  - Retro: a classic high-contrast serif.
  The number never shifts width as digits change (tabular figures).
- **Gauge faces, richer drawing, same geometry:**
  - Minimal ring: a soft inner glow and a subtle bezel; the arc gets a gradient with a bright leading tip.
  - Analog sport: a dark brushed dial with a bevelled rim, a glowing needle with a drop shadow, major ticks with a highlight, and a subtle vignette.
  - Digital HUD: scanline/grid texture, a glow behind the number, segment bar with lit-segment bloom.
  - Retro: cream paper texture, an embossed chrome rim, a red needle with a shadow, serif labels with slight letter-spacing.
- **Mascot, "2.5D" kawaii anime style drawn in code:**
  - Large anime eyes with iris gradient, two highlights and a lower lash line; expressive eyebrows per mood.
  - A soft round head with hair bangs and a shading gradient, cheek blush as soft radial gradients, a subtle drop shadow under the head.
  - Mood-specific details stay (sleepy "z", sweat drop, "!"), redrawn in the same style.
  - Blink keeps closing the eyes; a mood change still crossfades.
  - Colours still derive from the active face's theme (accent for hair/cheeks tint, number colour for ink), so it fits every face.
- Everything stays legible first: the number remains the largest element on screen and keeps its contrast targets.

## Affected users & systems
- Users: me (personal use, sideloaded).
- Screens: the speed screen and the face picker thumbnails. No new screens.
- Assets: new `Xpeet/Resources/Fonts/*.ttf` plus their OFL licence files. No image assets.
- Spec: this intent replaces, in `specs/gauge-themes/spec.md`, the Out of scope line "Custom fonts (e.g. 7-segment)". Fonts are assets, not dependencies. It changes nothing in gauge geometry, mood logic, placement or persistence.
- Spec: `specs/speed-mascot/spec.md` R8 keeps "drawn in code, no image assets"; this intent raises the drawing's richness only.

## Constraints
- iOS 17+, native SwiftUI only. No third-party dependencies. No image assets, no Lottie/Rive, no shaders (`.metal`).
- Fonts must be SIL OFL 1.1 (or Apache 2), bundled unmodified with their licence files, and registered at runtime (no Info.plist edits are needed, but allowed).
- Performance: no continuous animation. Textures and glows are static layers drawn once per size change; only the arc/needle/segments and the number animate on a new sample, as today.
- All existing requirements hold: contrast (7:1 number, 4.5:1 secondary, 3:1 mascot features), "199" never clipped, Dynamic Type, Reduce Motion, VoiceOver, no speed-based colours, mood curve unchanged.
- App size growth from fonts under ~1.5 MB.

## Open questions
- Which exact fonts (researcher to confirm licence, weights, tabular digits).
- Whether the mascot should get a small body/arms (more work, more charm) or stay a head only. Proposed: head only in this pass.
- Whether to tune the mascot size up slightly (R12 clamp 44–72 pt) now that it carries more detail. Proposed: raise the ceiling to 84 pt, floor unchanged.
