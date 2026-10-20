# Plan: Speed-reactive mascot

**Spec:** specs/speed-mascot/spec.md
<!-- Produced in Claude Code plan mode. Update in the same commit when implementation diverges. -->

This is PR 2 of 3. Branch `feat/speed-mascot` from the gauge-themes branch, because the mascot needs `Theme`.

The files go under `Features/Speedometer/Mascot/`, not a separate `Features/Mascot/`. The mascot has no ViewModel of its own; `SpeedometerViewModel` owns its state, so it stays inside the Speedometer feature.

## Files that change
- `Xpeet/Features/Speedometer/Mascot/Mood.swift` (new): `enum Mood { searching, sleepy, calm, happy, worried, startled }`.
- `Xpeet/Features/Speedometer/Mascot/MoodResolver.swift` (new): a pure struct.
  - Named constants:

    | Constant | Value |
    |---|---|
    | happy, enter | 30 km/h |
    | happy, exit | 25 km/h |
    | worried, enter | 110 km/h |
    | worried, exit | 100 km/h |
    | sleepy after | 10 s |
    | debounce | 2 samples |
    | brake threshold | 3 m/s² |
    | brake max Δt | 5 s |
    | startled duration | 2 s |

  - API:
    - `sample(metersPerSecond:at:)`
    - `tick(at:)`
    - `lost()`
- `Xpeet/Features/Speedometer/Mascot/MascotView.swift` (new): a kawaii face drawn with SwiftUI shapes.
  - Colours come from `Theme`.
  - The blink runs in a `.task(id:)` loop.
  - Mood changes crossfade over 0.3 s.
  - Reduce Motion turns both of those off.
  - The view is `accessibilityHidden`.
  - It has previews.
- `Xpeet/Features/Speedometer/SpeedometerViewModel.swift` (modified):
  - Adds a `MoodResolver` and a `mood` property.
  - Feeds the resolver from `handle(sample:)`, after smoothing.
  - Calls `tick()` before the stationary guard.
  - Calls `lost()` from the unavailable, stale and `run()` reset paths.
- `Xpeet/Features/Speedometer/SpeedometerView.swift` (modified): places the mascot.
  - Portrait: above the gauge. Landscape: on the leading side.
  - Size: `clamp(0.18 × diameter, 44, 72)`.
  - Hidden if there is no room for it.
- `XpeetTests/MoodResolverTests.swift` (new).
- `XpeetTests/SpeedometerViewModelTests.swift`, `XpeetTests/GaugeFaceTests.swift` (modified).
- `specs/speedometer/spec.md`, `specs/speedometer-gauge/spec.md`, `specs/gauge-themes/spec.md`: add notes for the two scoped exceptions.
  - Speed-based visuals are allowed only for the mascot.
  - The blink is the only exception to "no per-frame animation".
- `CLAUDE.md` Architecture: one line about the `Mascot/` subfolder. The owner approved this. Run the evals after editing.

## Order of work
1. Add `Mood` and `MoodResolver`, with `MoodResolverTests`.
2. Wire the resolver into `SpeedometerViewModel`, with integration tests.
3. Add `MascotView`, with a preview for each mood × face.
4. Place the mascot in `SpeedometerView`.
5. Add the spec notes and the CLAUDE.md line. Run `scripts/verify.sh`, the evals, and the manual checks.

## Risks
- **GPS braking detection is late.** Updates arrive at about 1 Hz, so braking is detected 1–3 s late. With α = 0.6, an 8 m/s² stop still shows a drop of about 4.8 m/s per second, so the 3 m/s² threshold triggers.
- **No room on small screens.** On iPhone SE in portrait there may be no room, so the mascot is hidden by design (R12).
- **Tick timing.** `tick()` currently returns early while stationary. The mood update has to run before that guard.

## Proof
| Req | Proof |
|---|---|
| R1 | `MoodResolverTests.testMoodCases`; previews |
| R2 | `MoodResolverTests.testNotLiveIsSearching`, `testStoppedUnderTenSecondsIsCalm`, `testStoppedTenSecondsIsSleepy`, `testSlowIsCalm`; `SpeedometerViewModelTests.testMoodFollowsState`, `testStationaryTickBecomesSleepy` |
| R3 | `MoodResolverTests.testHappyBandEdges`, `testWorriedBandEdges`, `testOscillationAroundHappyDoesNotFlicker`, `testOscillationAroundWorriedDoesNotFlicker`, `testMoodIndependentOfUnit` |
| R4 | `MoodResolverTests.testNewMoodNeedsTwoSamples`, `testSearchingIsImmediate`, `testFirstMoodAfterSearchingIsImmediate` |
| R5 | `MoodResolverTests.testHardBrakingIsStartled`, `testGentleBrakingIsNotStartled`, `testLongGapIsIgnored` |
| R6 | `MoodResolverTests.testStartledExpiresAfterTwoSeconds`, `testRepeatedBrakingRestartsStartled`, `testLostOverridesStartled`, `testHardAccelerationNoReaction` |
| R7 | review: no CoreMotion |
| R8 | `GaugeFaceTests.testMascotFeatureContrastPerFace`; previews |
| R9, R10, R11 | manual: blink, crossfade, Reduce Motion |
| R12 | manual: previews for iPhone SE and Pro Max, both orientations |
| R13 | review |
| R14 | manual: Accessibility Inspector |

Run `scripts/verify.sh` after every step.
