# Spec: Speed-reactive mascot on the speed screen

**Intent:** intent/2026-10-20-speed-mascot.md  **Status:** draft
**Depends on:** `specs/gauge-themes/spec.md` (the mascot takes its colours from the active face's theme). Build it after that spec.

This spec adds a small, original kawaii face to the speed screen. Its expression follows the speed. It replaces these parts of the earlier specs:
- `specs/speedometer/spec.md` Out of scope "speed-based colours": now allowed **only** for the mascot's expression. The gauge colours still never depend on speed (gauge R3, gauge-themes R7).
- "Nothing animates per frame / between samples" (speedometer Non-functional, gauge R10, gauge-themes R15): the **periodic blink** (R9) is the one exception.

Every other requirement stays in force.

## Requirements

### Moods
- **R1** The mascot has exactly six moods:

  | Mood | Look |
  |---|---|
  | `searching` | neutral eyes, looking to the side |
  | `sleepy` | closed curved eyes and a small "z" |
  | `calm` | dot eyes and a small flat smile |
  | `happy` | dot eyes, a wide smile and blush |
  | `worried` | wide eyes, a wavy mouth and a sweat drop |
  | `startled` | big round eyes, an "o" mouth and a small "!" |

  *(unit: enum cases. manual: previews)*

- **R2** Mood follows the speedometer state and the same filtered speed the number uses (speedometer R9), in m/s, independent of the selected unit:

  | Condition | Mood |
  |---|---|
  | state is Acquiring or Unavailable | `searching` |
  | live, speed below 1 km/h (speedometer R7) or stationary, for 10 s or more | `sleepy` |
  | live, stopped for less than 10 s, or speed below the happy band | `calm` |
  | live, in the happy band (R3) | `happy` |
  | live, in the worried band (R3) | `worried` |

  *(unit, with the injected clock)*

- **R3** The bands use hysteresis, so the mood doesn't flicker around a threshold:

  | Change | Threshold |
  |---|---|
  | calm → happy | at 30 km/h (≈19 mph) or above |
  | happy → calm | below 25 km/h (≈16 mph) |
  | happy → worried | at 110 km/h (≈68 mph) or above |
  | worried → happy | below 100 km/h (≈62 mph) |

  Each threshold is a named constant. `happy` is the happiest mood. No mood is "excited" or shows reward at high speed. *(unit: band edges both ways; a speed oscillating 28↔32 or 105↔112 km/h does not change mood every sample)*

- **R4** Debounce:
  - A new speed-based mood (calm, happy, worried) takes effect only after 2 consecutive valid samples agree on it.
  - `searching` takes effect immediately, and so does the first mood after leaving `searching`.
  - `sleepy` takes effect as soon as its 10 s has passed, checked on samples and on the existing 1 s tick.

  *(unit)*

### Hard braking
- **R5** Hard braking is a drop in filtered speed between two consecutive live samples of at least 3 m/s² (≈0.3 g):

  `(previous − current) / Δt ≥ 3`, where Δt is the samples' timestamp difference and 0 < Δt ≤ 5 s.

  When it happens, the mood becomes `startled` immediately, with no debounce. *(unit)*

- **R6** `startled` lasts 2 s from the last detected braking sample. Then the mood returns to the R2 mood for the current speed, without debounce. A new hard-braking sample during `startled` restarts the 2 s. `searching` (signal lost) overrides `startled`. Hard acceleration has no reaction. *(unit, with the injected clock)*

- **R7** Braking detection uses only GPS samples: no CoreMotion and no new permission. The 3 m/s² threshold is a named constant, to be tuned on a real drive. *(review)*

### Look and motion
- **R8** The face is drawn in code with simple shapes: a round face, eyes, a mouth, blush and small accessories. There are no image assets and no third-party code. It is original and not based on any existing character. Its colours come from the active gauge face's theme:
  - face fill: the theme's accent at low opacity, over the background
  - eyes, mouth and accessories: the theme's number colour

  Features must reach at least 3:1 contrast against the face fill (a non-text graphic, WCAG 1.4.11). *(unit: contrast per gauge face. manual: previews per mood × face)*

- **R9** While the mood is not `sleepy`, the mascot blinks:
  - The eyes close for about 0.15 s.
  - The gap between blinks is a random 3–6 s.

  The blink is a scheduled one-off animation, not a continuous per-frame loop. Blinking stops when the app is not active. *(manual)*

- **R10** A mood change cross-fades or morphs over about 0.3 s. *(manual)*

- **R11** With Reduce Motion on, there is no blink, and mood changes are instant. *(manual)*

### Placement
- **R12** The mascot size is about 18% of the gauge diameter, clamped to 44–72 pt. Placement by orientation:
  - **Portrait:** centred above the gauge.
  - **Landscape:** to the leading side of the gauge, vertically centred.

  It never overlaps the gauge, the number, the face button, the status chip or the safe areas. Adding it must not shrink the gauge or the number. If there is no room at 44 pt, the mascot is hidden rather than shrinking the gauge. *(manual: previews on iPhone SE and Pro Max size classes, both orientations, every gauge face)*

- **R13** The mascot is always shown. There is no setting and no toggle. It is not interactive: it has no tap action. *(review)*

### Accessibility
- **R14** The mascot is decorative and hidden from VoiceOver. The number stays the only speed element (speedometer R21, unchanged). *(manual: Accessibility Inspector)*

## User flows & UI

**States.**

| Speedometer state | Mascot |
|---|---|
| **Acquiring** | `searching` |
| **Live**, stopped < 10 s / slow | `calm` |
| **Live**, stopped ≥ 10 s | `sleepy` (no blink) |
| **Live**, 30–110 km/h | `happy` |
| **Live**, ≥ 110 km/h | `worried` |
| **Live**, hard braking | `startled` for 2 s |
| **Live, weak signal** | same as Live |
| **Unavailable** | `searching` |

There is no empty or error state of its own. It mirrors the speedometer state.

**Flow.**
- Opening the app shows `searching`.
- The first fix shows the matching mood right away.
- Driving off from a stop: calm, then happy once above 30 km/h for 2 samples.
- Braking hard: startled for 2 s, then the mood for the new speed.
- Parked for 10 s: sleepy.

**Accessibility.** See R11 and R14. Dynamic Type does not apply (no text, other than the decorative "z" and "!").

## Data & API
- **`Mood`**: an enum with the cases from R1. It is a pure value type.
- **`MoodResolver`**: a pure struct with no SwiftUI or CoreLocation imports. It owns:
  - the debounce counter
  - the hysteresis band
  - the stopped-since time
  - the startled-until time

  Its API is roughly `mutating func update(metersPerSecond: Double?, isLive: Bool, at: Date) -> Mood`. All thresholds are named static constants.
- **`SpeedometerViewModel`** owns one `MoodResolver` and exposes `private(set) var mood: Mood`. The mood is updated inside the existing `handle(sample:)`, `tick()`, `handle(authorization:)` and filter-reset paths. There is no second `SpeedProvider` subscription: one GPS stream drives both the number and the face.
- **`MascotView`**: declarative and takes `mood` and `theme`. It owns only the blink timer (view-local presentation state). It has a `#Preview` per mood.
- **Persistence:** none.

## Non-functional
- **Performance:**
  - The mascot redraws only on a mood change or a blink. A blink happens about every 3–6 s.
  - There is no `TimelineView(.animation)` and no continuous animation.
- **Privacy:** no change. No new data or permission.
- **Localization:** no new user-visible strings.
- **Compatibility:** iOS 17 SwiftUI only, one code path.

## Out of scope
- Image, Lottie, Rive or SpriteKit art, and a commissioned character.
- CoreMotion-based braking or acceleration detection, and reactions to hard acceleration.
- A user-set speed limit, and speed-limit data.
- Sounds or haptics from the mascot.
- Tapping or other interaction, and a toggle or setting.
- Idle motion other than blinking (bobbing, breathing).

## Flagged concerns
- **Driving safety (App Review 1.4.4/1.4.5, not binding):**
  - The mood curve peaks at moderate speed and turns `worried` when fast (R3), so it never rewards speeding.
  - `startled` is a surprise, not a judgement.
  - An always-on face adds some visual load. It is accepted by the owner (no toggle, R13).
- **GPS braking lag:** at about 1 Hz with the EMA filter, a hard stop is detected about 1–3 s late. Short sharp stops may be missed, and noisy fixes could cause a false `startled`. This is accepted for the MVP. The threshold is tunable (R7).
- **Architecture deviation:** `Features/Mascot/` would have a View but no ViewModel. The mood logic lives in a pure `MoodResolver` used by `SpeedometerViewModel`. CLAUDE.md says "`<Name>View.swift` + `<Name>ViewModel.swift`" per feature, so the plan must state this deviation, or put the files under `Features/Speedometer/`.
- **Supersedes approved requirements:**
  - The "speed-based visuals" exclusion and the "nothing animates between samples" rule get scoped exceptions.
  - Note this in the earlier specs in the same commit as the implementation.
- **No privacy, security or payments impact.**
- **Unverified locally:** only an iOS 27.1 simulator is installed. Real braking behaviour needs a drive on a device.

## Open questions
Carried from the intent:
- *Exact thresholds and mph equivalents?* **Answered (this spec, defaults):** R3 and R5. They can be changed in review.
- *Placement?* **Answered (this spec):** above the gauge in portrait, and leading in landscape (R12). It never shrinks the number.
- *Hard braking?* **Answered (owner):** yes, the mascot reacts. Detection is GPS-only (R5–R7). Hard acceleration: no reaction.
- *Braking threshold?* **Answered (this spec, default):** 3 m/s², tuned on a real drive.
- *Colours from the active theme?* **Answered:** yes (R8). This depends on gauge-themes.
- *Blink?* **Answered (owner):** yes (R9).
- *Toggle?* **Answered (owner):** none, always on (R13).
