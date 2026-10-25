# Spec: Accurate, responsive speed reading

**Intent:** intent/2026-10-25-speed-accuracy.md  **Status:** approved

This spec replaces the speed filter with an estimator that weighs each GPS fix by its accuracy and, when it can, blends in the phone's motion sensors. It also adds a debug-only drive recorder and a replay harness, so accuracy is measured instead of guessed.

Research: the researcher agent's findings, from 2026-10-25. They are cited here as *(research)*, with the sources in Flagged concerns and Data & API.

Changes to earlier specs (each gets a "Superseded/Amended by" note when this ships):
- `specs/speedometer/spec.md`:
  - **R4** amended: speed also uses motion sensors (R2 here).
  - **R5** amended: a fix with negative speed is ignored unless R13 applies.
  - **R6** amended: the gap rules in R17-R18 replace the 5 s rule. The rule that a cached moving fix more than 5 s old is ignored stays.
  - **R7** kept, with an extra way to detect a stop (R12 here).
  - **R8** amended: the rounding has hysteresis (R15).
  - **R9-R11** superseded by R5-R12 and R19.
  - **R12** amended by R16.
  - The weak-signal row of the states table is superseded by R18.
  - Non-functional "redraws only on a new sample" and "never stored" get scoped exceptions (R14, R22).
- `specs/speedometer-gauge/spec.md` **R10** and `specs/gauge-themes/spec.md` **R15**: the animation duration changes (R16).
- `specs/speed-mascot/spec.md`: unchanged. R20 keeps its inputs GPS-only.
- `specs/engine-sound-clip/spec.md` R6: unchanged. It reads the displayed speed, which is now more responsive.

## Requirements

### Sources
- **R1** **Location fixes carry more data.** The location provider passes on, for each fix:
  - speed and speed accuracy;
  - coordinate and horizontal accuracy;
  - course and course accuracy;
  - the stationary flag and the timestamp.

  On iOS 18+, an update that reports location unavailable is passed on as a gap signal instead of being dropped. A fix whose timestamp is not later than the previous fix's is dropped as a duplicate. The ViewModel still sees no Core Location types (speedometer R4). *(unit: fake provider; review)*

- **R2** **Motion source.**
  - A new `Xpeet/Core/Motion/` is the only code that imports Core Motion. It owns a single motion manager.
  - It reads device motion at 50 Hz, in the reference frame that keeps Z vertical and does not use the compass (`.xArbitraryZVertical`).
  - Samples are delivered in batches of 5, about 10 batches per second. Each sample has a timestamp, user acceleration in m/s², the gravity direction and the rotation rate, all in device coordinates.
  - It starts and stops with `run()`, in the same lifecycle as location (speedometer R20).
  - If device motion is not available (e.g. the Simulator), the stream ends at once and the app runs GPS-only.

  *(unit: fake motion provider; manual: device)*

- **R3** **Clock alignment.** Motion timestamps count seconds since boot, while fixes carry a wall-clock date. Motion time is mapped to wall-clock time with a running minimum of (arrival date − motion timestamp). `ProcessInfo.systemUptime` is not used. *(unit)*

### Estimator
- **R4** **Two estimates from one input.** `SpeedEstimator` is a pure value type that imports only Foundation. It takes fixes, motion batches, gap signals and clock ticks, and keeps two estimates side by side:
  - **GPS-only**;
  - **fused**.

  Each estimate has a speed (m/s) and a 1σ uncertainty (m/s). The same input always gives the same output. *(unit)*

- **R5** **GPS-only estimate.**
  - A Kalman filter with speed and acceleration as its state (constant-acceleration model), updated once per fix.
  - Fix noise: R = (k_R · max(speedAccuracy, 0.1 m/s))².
  - A fix is rejected if its speed differs from the prediction by more than 12 m/s² × the time since the last fix (physics bound).

  *(unit: hand-computed steps; a fix with larger speedAccuracy moves the estimate less; an impossible jump is rejected)*

- **R6** **Fused estimate.** A Kalman filter with speed along the road and the accelerometer's forward bias as its state.
  - **Predict** on every motion sample: speed += (forward acceleration − bias) × dt.
  - **Process noise** covers random speed noise, accelerometer scale error, and the forward-axis error times sideways acceleration in curves. Each term is a named constant (Data & API).
  - **Correct** on every fix, with the same R as R5.

  *(unit: synthetic drives, R25)*

- **R7** **GPS reporting delay.**
  - Each fix is applied at its timestamp − τ, and the stored motion inputs are replayed forward to now.
  - The estimator keeps 3 s of history for this.
  - τ is a named constant. It starts at 0 and is set from recordings (R30).

  *(unit: on a synthetic drive whose GPS lags by 0.5 s, τ = 0.5 s gives lower lag error than τ = 0)*

- **R8** **Outlier gating (fused).**
  - A fix whose normalised innovation squared is above 9 is rejected.
  - After 3 rejected fixes in a row that each have speedAccuracy ≤ 1.5 m/s, the fused estimate is re-initialised from the GPS speed, so it can never lock itself out.

  *(unit)*

- **R9** **Learning the forward axis.**
  - **Data:** pairs from consecutive good fixes (speedAccuracy ≤ 1 m/s, motion reliable per R10). Each pair is the GPS acceleration over the interval and the mean horizontal acceleration over the same interval, shifted by τ.
  - **Fit:** recursive least squares with forgetting 0.99 per pair. The fit gives both the axis angle and its sign.
  - **Converged** when all hold:
    - the angle's σ is < 3°;
    - the fitted gain is 0.85-1.15;
    - the summed squared GPS acceleration is ≥ 20 (m/s²)².
  - Until it converges, the fused estimate is not shown.
  - The axis is not saved across launches. It is learned again on each run.

  *(unit: synthetic drives with a random mount orientation, including upside down and facing backwards, converge to within 3° of the true axis; a drive at constant speed never converges)*

- **R10** **Motion reliability.**
  - Motion is unreliable while any of these holds:
    - rotation that is not about the vertical is above 0.5 rad/s for more than 0.1 s;
    - horizontal acceleration is above 0.8 g;
    - the gravity direction in device coordinates is more than 10° from its 10 s mean;
    - the gyro's turn rate disagrees with the GPS course rate by more than 10°/s while course accuracy is ≤ 10°.
  - Motion becomes reliable again after 3 s with none of these.
  - If the gravity direction moved by more than 10° (the phone was re-mounted), the forward axis is learned again (R9).

  *(unit: synthetic handling events)*

- **R11** **No motion, no fusion.** While motion is unreliable or the motion stream has ended, fused prediction pauses, and the displayed value comes from the GPS-only estimate (R14). *(unit)*

- **R12** **Stop detection.**
  - **Still** means: over the last 1 s, the vertical acceleration's standard deviation and the rotation rate are both below named thresholds.
  - **Stopped** means still AND any of:
    - GPS speed < 0.5 m/s;
    - the iOS stationary flag is set;
    - the estimate is < 1 m/s.
  - While stopped:
    - both estimates are exactly 0;
    - the fused bias is reset to the mean forward acceleration over that 1 s window.
  - The iOS stationary flag on its own still gives 0, as today (speedometer R7).

  *(unit)*

- **R13** **Fixes without Doppler speed** (speed < 0).
  - Ignored by default, as today.
  - With the named switch `usesPositionSpeed` on, such a fix is used only if both it and a fix 2-5 s earlier have horizontal accuracy ≤ 10 m:
    - speed = distance / Δt;
    - R = 2(σ₁² + σ₂²) / Δt².
  - The switch is turned on only if recordings show that usable fixes of this kind occur (R30).

  *(unit, both switch positions)*

### Display
- **R14** **What is shown.**
  - The fused estimate is shown when all hold:
    - the `fusionEnabled` switch is on;
    - the forward axis has converged (R9);
    - motion is reliable (R10).
  - Otherwise the GPS-only estimate is shown.
  - With fusion shown, the value refreshes on every motion batch, about 10 times a second. With GPS-only, it refreshes on each fix, about once a second.
  - `fusionEnabled` is off until the accuracy gate (R28) passes. In Debug builds it can be turned on with the launch argument `-XpeetFusion YES`.

  *(unit)*

- **R15** **Rounding.**
  - The shown whole number changes only when the estimate, in the selected unit, differs from it by at least 0.6. This stops flicker between two values.
  - An estimate below 1 km/h shows 0 (speedometer R7). The value is never negative (speedometer R8).
  - Switching units recomputes the number at once, without hysteresis.

  *(unit: an estimate wobbling 59.4 ↔ 60.4 does not change the number; 0.27 m/s shows 0)*

- **R16** **Animation.**
  - The number keeps its numeric transition. The arc, the needle or the lit segments still animate to the new value.
  - Both use a linear animation of at most 0.1 s, replacing the 0.6 s smooth animation (gauge R10, gauge-themes R15). The animation never makes the shown value trail the estimate by more than 0.1 s.
  - With Reduce Motion on, everything still changes instantly (gauge R11).

  *(manual: device drive, Reduce Motion on and off)*

### Gaps and status
- **R17** **Gap start.** A gap starts when either:
  - iOS 18+ reports location unavailable; or
  - no fix has arrived for 1.5 s while the last estimate was moving.

  It ends with the next accepted fix. *(unit)*

- **R18** **During a gap.**
  - **Fused shown:**
    - prediction continues from motion;
    - the value stays on screen, flagged as weak signal, while 2σ ≤ 3 km/h (σ ≤ 0.42 m/s) and the gap is at most 10 s;
    - after either limit the state becomes Acquiring ("--").
  - **GPS-only shown:**
    - the last estimate is held, not extrapolated, and flagged as weak signal;
    - after 5 s with no fix the state becomes Acquiring, as today (speedometer R6).
  - If the last estimate was stopped (R12), 0 stays on screen with no time limit, as today, because iOS pauses updates while stationary.

  *(unit, with an injected clock)*

- **R19** **Reset.** When fixes resume after Acquiring, both estimates start again from the first new fix. The learned forward axis is kept for the rest of the run, unless R10 says the phone was re-mounted. *(unit)*

- **R20** **Weak signal.** "Weak GPS signal" shows when either:
  - the shown estimate's σ is above 0.5 m/s (a named constant, tuned from recordings); or
  - a gap is in progress (R18).

  This replaces the 2 m/s speed-accuracy rule. *(unit)*

### Other readers of speed
- **R21** **Mascot and engine sound.**
  - The mascot's mood is fed once per accepted fix, with the GPS-only estimate. So speed-mascot R4, R5 and R7 (no Core Motion for braking) hold unchanged.
  - The engine-sound "is moving" check keeps reading the displayed speed (engine-sound R6).

  *(unit)*

### Drive recording (Debug only)
- **R22** **Recorder.**
  - **Build:** compiled only in Debug builds (`#if DEBUG`).
  - **Opt-in:** off unless the app is launched with `-XpeetRecordDrives YES`. My daily build is a Debug build, so recording is never on by default.
  - **When on:** each `run()` writes one JSON Lines file to `Documents/Drives/`. The file name starts with the start date and time, so names sort in time order. Lines:
    - a header: format version, device model, iOS version, rates and all estimator constants;
    - one line per fix: every field in R1, plus arrival time and flags;
    - one line per motion sample;
    - one line per display refresh: shown value, state, source (fused or GPS-only), and both estimates with their σ.
  - **Retention:** only the 5 newest files are kept. Older ones are deleted when a new recording starts, chosen by file name, not by file dates.

  *(unit: recorder against a temp folder; review: `#if DEBUG`)*

- **R23** **Recording never disturbs the display.** Writes are buffered and done off the main actor. A write failure stops recording silently and never changes what is shown. *(unit: a failing writer leaves the ViewModel output unchanged)*

- **R24** **Getting files off the phone.** A documented command copies the drive files from the device one by one (`devicectl device copy from` against the app's data container). Release behaviour does not change: there is no file-sharing key. *(manual)*

### Replay and evaluation
- **R25** **Synthetic drives (tests).** A seeded generator in `XpeetTests` makes drives with a known true speed:
  - **Profile:** standing start, cruise, hard braking at 0.8 g, stop-and-go, a 10 s tunnel, and curves.
  - **GPS:** 1 Hz, noise per its stated speedAccuracy, and a configurable delay.
  - **Motion:** 50 Hz, a random mount orientation, a 30 mg bias, vibration noise and handling events.

  *(unit)*

- **R26** **Replay harness.** A replay harness in `XpeetTests` feeds a recorded or synthetic drive through `SpeedEstimator`, using the same inputs as live use. It produces both estimates over time. *(unit)*

- **R27** **Targets on synthetic drives** (unit tests, run by `scripts/verify.sh`), with fusion forced on:
  - **Steady speed:** after convergence, the mean absolute error at constant speed is ≤ 0.5 km/h.
  - **Lag:** after the start of a 0.8 g braking, the shown value is within 3 km/h of the true speed within 1 s.
  - **Tunnel:** during a 10 s gap, at least 95% of shown values are within ±3 km/h of the truth, and nothing is shown once 2σ > 3 km/h.
  - **Fallback:** during a handling event, the shown source is GPS-only.

  *(unit)*

- **R28** **Accuracy gate on real drives.** Before `fusionEnabled` is turned on, all of these must hold. If they don't, it stays off and GPS-only ships.
  - **Data:** at least 3 recorded drives, at least 30 min in total. They cover city stop-and-go, highway, and at least one tunnel or underpass.
  - **τ first:** τ is measured first (R30).
  - **Lag and smoothness:** fused beats GPS-only against both offline references:
    - a fused RTS smoother;
    - a GPS-only constant-acceleration RTS smoother.

    A result counts only if both references agree.
  - **Simulated tunnels:** on open-sky stretches, GPS is hidden for 5-15 s. At least 95% of the values fused would show are within ±3 km/h of the hidden fixes.
  - **Steady speed:** fused is not worse than GPS-only by more than 0.3 km/h (mean absolute error) against distance-over-time (R29).
  - **Results:** written to `specs/speed-accuracy/results.md`.

  *(manual analysis via R26)*

- **R29** **Distance over time.**
  - The distance travelled along the road is the sum of straight lines between fixes about 10 s apart, over a stretch of at least 3 km at steady speed.
  - It is divided by the elapsed time and compared with the time-average of the shown speed over the same stretch.
  - Target: within ±1 km/h.

  *(manual analysis)*

- **R30** **Measured on the device, recorded in `results.md`:**
  - the fix rate;
  - the share of fixes with speed −1, and how many of those R13 could use;
  - what iOS reports inside a tunnel;
  - τ, from cross-correlating forward acceleration with the rate of change of GPS speed;
  - the k_R scale for speedAccuracy;
  - typical σ, to tune R20;
  - battery cost at 50 Hz, motion on vs off (Xcode energy gauge).

  Constants change only from these measurements. *(manual)*

- **R31** **Committed test clips.**
  - Real-drive clips in `XpeetTests/Fixtures/Drives/` are at most 2 min and 1 MB each, and at most 5 in total.
  - Before committing, coordinates are replaced by metres relative to the clip's first fix, and dates by seconds from the start. No real place or date is in git.
  - Full drives are never committed. Replay tests that need them read from the gitignored `build/drives/` and skip when it is empty.

  *(review; unit: the fixture loader rejects absolute coordinates)*

### Repo
- **R32** **CLAUDE.md.** The Architecture section gains:
  - a line for `Core/Motion/`, the only Core Motion importer;
  - a line for the estimator folder.

  Then `evals/run.sh` and `scripts/check-bands.sh` are re-run (docs/ai-sdlc.md). *(review)*

- **R33** **Motion usage string.** `INFOPLIST_KEY_NSMotionUsageDescription` is added to `project.yml` with: "Xpeet uses motion sensors only to make the speed reading more accurate. Motion data never leaves your device."
  - Device motion needs no authorisation today, so no prompt appears. The key is insurance in case that changes *(research)*.

  *(review; manual: fresh install shows no motion prompt)*

## User flows & UI
No new screens, controls or settings. The layout, faces, chip, unit pill and mascot are unchanged.

| State | Number | Status chip |
|---|---|---|
| **Acquiring** (loading): no fix yet, or a gap ran out (R18) | `--` | "Searching for GPS…" |
| **Live** (success) | shown estimate (R14-R15) | hidden |
| **Live, weak signal** (degraded): σ above 0.5 m/s, or a gap in progress | shown estimate | "Weak GPS signal" |
| **Unavailable** (error) | `--` | reason (speedometer R17), unchanged |

There is no empty state: "no fix yet" is Acquiring.

What I notice while driving:
- **First 1-3 min of a drive:** GPS-only, refreshing about once a second.
- **After a few accelerations or brakings:** if fusion is enabled, refreshes about 10 times a second and follows braking with less delay.
- **Phone picked up or knocked in its mount:** quietly back to about once a second, then fused again after 3 s.
- **Tunnel:** the number stays with "Weak GPS signal" while it is trustworthy, then "--".

**Accessibility.**
- The speed element keeps the "updates frequently" trait (speedometer R21). VoiceOver reads the current value on focus and never announces each refresh.
- Reduce Motion: R16.
- Dynamic Type and contrast are unchanged.

## Data & API
- **`SpeedSample`** (`Core/Location`) gains: `latitude`, `longitude` (degrees), `horizontalAccuracy` (m), `course` (degrees), `courseAccuracy` (degrees). Negative accuracy means invalid, as today.
- **`SpeedProvider.speedUpdates()`** yields either a fix or a gap signal (iOS 18+ `locationUnavailable`). The exact shape is up to the plan.
- **`MotionSample`** (`Core/Motion`, Sendable value type):
  - `timestamp` (s since boot);
  - `userAcceleration` (m/s², the g value × 9.80665);
  - `gravity` (unit vector);
  - `rotationRate` (rad/s).

  All in device coordinates.
- **`MotionProvider`** protocol (`Core/Motion`): `motionUpdates() -> AsyncStream<[MotionSample]>`, buffering newest 8 batches.
  - `CoreMotionProvider` (production): a dedicated serial `OperationQueue`. Each sample is copied into a `MotionSample` at once. Updates stop on termination. It follows the queue-confined pattern of `SoundAnalysisTriggerDetector`.
  - `FakeMotionProvider` (`#if DEBUG`).
- **`SpeedEstimator`** and its helpers (forward-axis learner, reliability, stop detector) are pure value types in `Xpeet/Features/Speedometer/Estimation/`, tested in `SpeedEstimatorTests.swift` (plus helper test files).
  - `SpeedometerViewModel` owns one `SpeedEstimator`. It gains `handle(motion:)` and `handle(gap:)`, and still feeds them only from `run()`.
  - The estimator is `@ObservationIgnored`. Only the shown value, state and mood are observed, so 50 Hz maths does not invalidate SwiftUI.
- **Starting constants** (tuned only from R30 measurements):

  | Constant | Start |
  |---|---|
  | k_R | 1.0 |
  | GPS-only acceleration noise | (2 m/s²)²/s |
  | Fused speed noise q_v | (0.05 m/s)²/s |
  | Scale error k_sf | 0.02 |
  | Axis error σ_δ (once converged) | 0.05 rad |
  | Bias drift q_b | (0.003 m/s²)²/s |
  | Initial bias σ | 0.3 m/s² |
  | τ | 0 s |
  | History buffer | 3 s |
  | NIS gate | 9 |
  | Physics bound (GPS-only) | 12 m/s² |
  | Re-init after rejections | 3 |
  | Gap start | 1.5 s without a fix |
  | Gap limits (fused) | 2σ ≤ 3 km/h, ≤ 10 s |
  | Weak-signal σ | 0.5 m/s |
  | Display hysteresis | 0.6 unit |
  | Motion rate / batch | 50 Hz / 5 samples |

- **Persistence:** only the existing `speedUnit` and `gaugeFace` keys, plus Debug-only opt-in drive files (R22). The forward axis is not stored.
- **Offline:** fully offline, as today.

## Non-functional
- **Performance:**
  - The estimator's work per motion batch must stay well under 1 ms on device. The 3 s replay on each fix is microseconds for a 2-state filter *(research)*.
  - The main actor is touched about 10 times a second, not 50.
  - The view redraws on each refresh of the shown value (at most about 10 Hz, only when the rounded number or the state changes). This is an exception to speedometer's "redraws only on a new sample".
- **Battery:**
  - Motion at 50 Hz, not 100. The only published measurement is old (iPhone 5S): device motion at 100 Hz cost about 75% as much as GPS *(research, SensingKit)*.
  - The real cost is measured on the device and written to `results.md` (R30).
  - The screen is always on, so it probably dominates.
- **Privacy:**
  - Motion and location stay on the device and in memory. The only exception is the opt-in Debug drive files (R22).
  - Usage string: R33.
  - No ATT, no analytics and no new permission prompt.
- **Localization:** no new user-facing strings.

## Out of scope
- Calibration offset to match the car's speedometer.
- OBD-II or Bluetooth car speed, CarPlay, background tracking, trip statistics.
- Map matching or any online data.
- Saving the learned mount direction across launches.
- An in-app recording toggle or viewer: recording uses the launch argument only.
- Showing fused-vs-GPS diagnostics on screen.
- A higher GPS rate. The iPhone GPS runs at 1 Hz *(research)*.

## Flagged concerns
- **Privacy, location history on disk (owner):**
  - The Debug recorder stores precise location traces: home, work, routes. The previous spec said location is "never stored". R22 makes a scoped exception: Debug builds only, opt-in per launch, the 5 newest files kept, files never sent anywhere.
  - Committed clips are anonymised (R31). Full drives must never be committed; `build/` is gitignored.
- **Privacy, Info.plist:** a new `NSMotionUsageDescription` (R33). No prompt is shown for device motion. An Apple DTS engineer recommends the key as insurance *(research: developer.apple.com/forums/thread/762886)*.
- **Required-reason APIs:**
  - The design avoids `systemUptime` (R3) and file-timestamp APIs (R22 prunes by file name).
  - `UserDefaults` is already flagged in the speedometer spec.
  - Nothing is needed for a sideloaded build. Recheck if the app is ever distributed.
- **Driving safety (App Review 1.4.4/1.4.5, not binding):**
  - No speed-based colours, sounds or alerts are added.
  - The estimator shows "--" rather than an untrustworthy number (R18).
- **CLAUDE.md and evals:** R32 changes the Architecture section. It needs owner approval and an eval re-run (docs/ai-sdlc.md).
- **Unverified, and only checkable on a device:**
  - The Simulator has no device motion *(research, unconfirmed)*, so fusion is tested only with synthetic or recorded drives and on a phone.
  - iOS does not document how much it delays or smooths the speed it reports. If τ is wrong, every comparison is biased.
  - Core Motion's gravity estimate may absorb long, sustained acceleration *(research, unconfirmed for iOS)*. That would make σ over-confident in long accelerations or curving tunnels. R27's tunnel target and R28's simulated tunnels are the check.
  - On iOS 17 there is no `locationUnavailable`, so gaps are detected only after 1.5 s without a fix.
  - Only an iOS 27.1 simulator is installed locally.
- **No independent ground truth:** without a GNSS logger, an error the phone's GPS makes everywhere cannot be detected (intent Decisions). The offline references share the GPS's errors. They are valid for lag and smoothness only *(research)*.
- **Intent wording:** the intent's claim that top apps blend GPS with motion sensors was removed. Nothing public supports it *(research)*.

## Open questions
Carried from the intent:
- *Real fix rate, share of speed −1, behaviour in tunnels, reporting delay, trustworthiness of speedAccuracy, battery cost at 50 Hz?* **Still open:** measured on the device during the build (R30), written to `results.md`.
- *Remember the learned mount direction across launches?* **Answered (this spec):** no. It is learned again on each run (R9). A wrong saved axis would be worse than 1-3 min of GPS-only. See Out of scope.
- *Where does the offline analysis code live?* **Answered (this spec):** in `XpeetTests` (R25, R26, R28). Clips are trimmed and anonymised (R31), and full drives stay in the gitignored `build/drives/`.
- *Calibration offset, OBD-II, CarPlay, background, trip stats?* **Deferred:** see Out of scope.

Raised by this spec:
- *GPS-only hold in a gap:* R18 keeps today's 5 s hold, now flagged as weak signal. The recordings may show it should be shorter. Proposed: revisit after R30.
- *Battery budget:* the intent asks for "no worse than … plus sensors at a modest rate" but sets no number. Proposed: the owner decides after R30 whether the measured cost is acceptable.
- *Fusion ships off:* `fusionEnabled` stays off until R28 passes, so the first merge improves accuracy through the GPS-only filter (R5) and adds the tools. Turning fusion on is a separate, one-line change with `results.md` as its evidence.
