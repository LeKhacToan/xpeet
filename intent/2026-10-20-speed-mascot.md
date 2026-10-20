# Intent: Speed-reactive mascot on the speed screen

**Owner:** toanlk  **Status:** accepted

## Problem
The speed screen is now readable, but it has no personality: nothing on it feels alive or fun to glance at.
A small character that reacts to how I'm driving would make the app feel friendlier without adding anything to read.

## Proposed outcome
- A small, original kawaii-style face (simple shapes: round face, dot eyes, small mouth, blush) sits on the speed screen, smaller than the speed number and not covering it.
- Its expression follows the current speed, using the same smoothed speed the number shows:
  - searching for GPS / location unavailable: a neutral "looking around" face
  - stopped for a while: sleepy (closed eyes, "z")
  - slow: calm
  - moderate cruise: happy (this is the happiest it ever gets)
  - very fast: worried (wide eyes, sweat drop). It never looks excited or rewarded by high speed.
  - hard braking: a short "startled" face (wide eyes, small "!") for about 2 s, then back to the speed-based mood. It is a surprised reaction, never mocking or "you failed".
- Expressions don't flicker when the speed hovers around a threshold.
- The face blinks every few seconds while awake.
- The mascot is always on. There is no toggle.
- With Reduce Motion on, there is no blinking and expressions swap instantly.

## Affected users & systems
- Users: me (personal use, sideloaded).
- Screens: the single speed screen (`SpeedometerView`). No new screens.
- Spec: this intent replaces these parts of the existing specs:
  - In `specs/speedometer/spec.md`, the Out of scope ban on speed-based visuals, but only for this face.
  - In `specs/speedometer/spec.md`, the "nothing animates per frame" rule, but only for the periodic blink.
- Unchanged: the arc colour stays independent of speed (gauge spec R3).

## Constraints
- iOS 17+, native SwiftUI only, drawn in code. No image art, no third-party animation libraries, no new permissions.
- Original character only, not based on any existing anime or brand character.
- Must not encourage speeding (App Review 1.4.4 spirit): the face is happiest at moderate speed and turns worried when very fast. There are no sounds, haptics, scores or rewards tied to speed.
- Not interactive while driving: there is nothing to tap.
- The blink is a cheap, periodic event (every few seconds), not a continuous per-frame animation.
- VoiceOver: the face is decorative. The speed number stays the only spoken element.
- All existing behaviour stays: "199" is never clipped, contrast targets are met, layout works in portrait and landscape, and Dynamic Type works.

## Open questions
- Exact speed thresholds for each mood, and their mph equivalents. The spec proposes defaults.
- Placement: inside the ring above the number, or below the gauge. It must not shrink the number further.
- Hard-braking detection source. Proposed: derive deceleration from successive GPS speed samples, which needs no new permission. The cost is that it reacts 1–3 s late and may miss short stops. CoreMotion would be faster, but it needs `NSMotionUsageDescription` and the phone's mount orientation is unknown. Hard acceleration: no reaction.
- Braking threshold. Proposed: about −3 m/s² (≈0.3 g), tuned on a real drive.
- When multiple gauge faces/themes land (separate intent), the mascot should take its colours from the active theme.
