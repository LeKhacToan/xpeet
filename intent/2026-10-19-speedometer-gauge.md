# Intent: Arc gauge redesign for the speed screen

**Owner:** toanlk  **Status:** accepted

## Problem
The speed screen works, but it looks plain: white digits and grey text on pure black, with no colour, no shape and no icon.
Every state (searching, weak signal, location off) looks the same apart from its wording, so the screen is harder to read at a glance.
The app also has no icon on the home screen.

## Proposed outcome
- The speed sits inside a modern arc gauge (about a 270° sweep). The arc fills from 0 to a fixed maximum: 200 km/h, or 130 mph. Above the maximum the arc stays full and the number still shows the real speed.
- The brand colour is a pastel green. It is used for the arc, the unit control and the status icons. The background stays dark (a near-black with a subtle green tint), so contrast stays high at night.
- Each status (searching, weak signal, location off) shows as a small chip with an icon and its text, so the state is clear at a glance.
- The unit control looks like a tappable pill and gives a light haptic when tapped.
- With Reduce Motion on, the number and the arc update without animating.
- The app has a real icon in the same style: a dark tile with a pastel green arc.

## Affected users & systems
- Users: me (personal use, sideloaded).
- Screens: the single speed screen (`SpeedometerView`). No new screens.
- Assets: `AccentColor` and `AppIcon` in the asset catalog.
- Spec: `specs/speedometer/spec.md` R2, its layout section and its Out of scope list forbid gauges and extra colours today; this intent replaces those parts.

## Constraints
- iOS 17+, native SwiftUI only, no third-party dependencies, one code path (no `#available` branches for the look).
- Dark appearance only. No light mode.
- Must still not encourage speeding: the arc colour never changes with speed (no red/amber zones, no alerts), and no haptics or sounds are tied to speed.
- All existing behaviour stays: "199" never clipped in any orientation, contrast at least 7:1 for the number and 4.5:1 for secondary text, Dynamic Type, VoiceOver strings, and redrawing only on a new sample.

## Open questions
- Light mode, Liquid Glass (iOS 26) styling and a speed-limit marker: out of scope for now, maybe later.
