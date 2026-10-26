# Intent: Speed reading as accurate and responsive as top speedometer apps

**Owner:** toanlk  **Status:** accepted

## Problem
The number on screen often disagrees with what I see in the car, and it reacts late:
- It trails real speed by about 1-3 s when I speed up or brake. GPS updates arrive about once a second (the iPhone's GPS runs at 1 Hz), and the jitter filter (R9, α = 0.6) adds more lag on top.
- It is coarse. It changes in steps of about 1 s and does nothing in between, so it feels sluggish next to apps like Speedometer 55 or Waze. How those apps work is not public; the aim here is to beat them on measured accuracy, not to copy them.
- It drops out too easily. A fix that has no Doppler speed (`speed = -1`) is thrown away. Under bridges, in tunnels and between tall buildings it goes to "--" after 5 s, when it could estimate speed for a while.
- It treats every fix the same. A fix with poor accuracy moves the number as much as a precise one. It does not trust good fixes more or cap jumps that are physically impossible.
- I have no way to measure accuracy. "It feels off" is all I have. Part of the gap may not be an app bug at all: car speedometers usually read 3-7% high, which the law allows.

## Proposed outcome
The goal is the most accurate true ground speed the phone can give. Matching the car's speedometer is not a goal.

Measured on my own drives against the references in Decisions:
- **Steady speed:** within ±1 km/h of the reference at 30-120 km/h on open sky.
- **Lag:** after a clear acceleration or hard braking, the number is within 3 km/h of the reference within 1 s (today it takes about 4 samples).
- **Smoothness:** the number updates about 10 times a second between GPS fixes and never jumps more than real acceleration allows. When stopped it shows exactly 0 and does not wander.
- **Signal gaps:** a short loss (a tunnel or underpass) keeps showing an estimated speed, flagged as weak signal, while the estimate is still trustworthy (see Decisions). After that it goes to "--" as it does today.
- **Bad fixes:** fixes with bad accuracy count for less, and impossible jumps are rejected.
- **Measurable:** a debug-only, opt-in way to record a drive (raw fixes, motion sensor data and what was shown) and replay it in unit tests. Accuracy changes are then tested against real data, not just guessed.
- **Expected limit:** each drive starts in GPS-only mode. The phone has to see a few accelerations and brakings (likely 1-3 min of driving) before it knows which way is forward and can blend in motion sensors.

## Affected users & systems
- Users: me (personal use, sideloaded).
- Code areas:
  - `Xpeet/Core/Location/`: the location source. It has to pass on more fields (position, horizontal accuracy, course, and on iOS 18+ the "location unavailable" signal).
  - A new `Xpeet/Core/Motion/`, the only code that imports Core Motion. This changes the CLAUDE.md Architecture section, so `evals/run.sh` must be re-run (per `docs/ai-sdlc.md`).
  - The filter in `SpeedometerViewModel`. The engine-sound "is moving" check reads the same displayed speed, so it improves too.
  - The mascot keeps its current inputs: GPS samples at fix rate, as `specs/speed-mascot/spec.md` R4, R5 and R7 require. Its spec does not change.
- Screens: no new screens and no new settings.
- Specs that change:
  - `specs/speedometer/spec.md`:
    - R5: invalid Doppler speed is no longer always ignored.
    - R6: the 5 s stale rule changes for short gaps.
    - R9-R10: the EMA with α = 0.6 and the "4th sample" lag rule.
    - R12: the digit animation must not add lag at the higher update rate.
    - The weak-signal threshold (2 m/s).
    - Non-functional "redraws only on a new sample" and "never stored": both get scoped exceptions (10 Hz display; opt-in debug recording).
    - R7 (exact 0 when stationary) stays.
  - `specs/speedometer-gauge/spec.md` R10 and `specs/gauge-themes/spec.md` R15: the gauge animation (today 0.6 s) becomes short or none, so it does not lag at 10 Hz.
- Tests: `SpeedometerViewModelTests` filter tests change because the behaviour changes. New tests for the estimator replay short recorded clips (hard brake, tunnel, stop-and-go), not whole drives.

## Constraints
- iOS 17+, Apple frameworks only (Core Location, Core Motion). No third-party dependencies and no networking. No map matching against online maps.
- Foreground only, as today. No `UIBackgroundModes`. Location and motion data never leave the device.
- Recording: my daily sideloaded build is a Debug build, so recording is off unless I turn it on for a test drive. It keeps only the last few drives. Files leave the phone only when I copy them myself (Xcode or `devicectl`).
- No new permission prompt. Raw device motion (accelerometer, gyro) needs none. Motion & Fitness activity data is not used.
- Battery: motion sensors at 50 Hz, not 100 Hz, delivered to the app in batches about 10 times a second. The cost is measured on the device before shipping.
- Must still not encourage speeding: no speed-based colours, sounds or alerts.
- The phone may be mounted at any angle, or move in the mount. Sensor fusion must not depend on a fixed orientation or on the compass.

## Decisions
Each one picks the option that gives the most accurate reading. They were corrected after research.
- **How to fuse: a Kalman filter that combines GPS and motion sensors.**
  - It tracks speed along the road and the accelerometer's own bias.
  - Between fixes it predicts speed from the phone's forward acceleration. The forward direction is learned while driving, from how GPS speed changes, so mount angle and compass errors don't matter.
  - Each GPS fix corrects the prediction. A fix counts in proportion to its reported speed accuracy.
  - It allows for the delay between a real speed change and the moment iOS reports it. The delay is measured from recordings, not guessed.
  - A fix that disagrees with the prediction by more than physics allows is rejected. If several good fixes in a row are rejected, the filter resets to GPS, so it can never lock itself out.
  - **Stop:** the accelerometer is still, AND either GPS speed is near 0 or iOS reports stationary. Then the speed is exactly 0 and the filter recalibrates its bias. iOS's stationary flag arrives late, so it is not required on its own.
- **Fixes without Doppler speed: measure first.** Such fixes mostly come with poor (Wi-Fi/cell) positions, and speed from the position change over 1 s is very noisy. The recordings show how often a usable one appears. Speed from position is used only with tight limits (good accuracy, 2-5 s apart), and only if the data shows it helps.
- **Accuracy gate.** On recorded drives, fusion must:
  - be better than a GPS-only filter weighted by accuracy on lag, smoothness and signal gaps;
  - not be worse on steady speed (within 0.3 km/h). Motion sensors add nothing to steady-state accuracy.

  Otherwise the GPS-only filter ships. Data decides, not the idea.
- **Display rate: about 10 updates per second from the fused estimate.** Each value is the filter's best estimate at that moment, driven by measured acceleration, not a guessed curve between two fixes. If motion data is missing or unreliable, it falls back to GPS-only updates at about 1 Hz. "Unreliable" means the phone is moving in its mount or is being handled, which shows as large rotation or a shift in which way gravity points. The number has a little hysteresis, so it does not flicker between two values.
- **Signal gaps: governed by uncertainty, with a hard cap.** During a GPS gap the estimate is shown, flagged as weak signal, for at most 10 s. It is shown only while the filter is 95% sure (2σ) the true speed is within ±3 km/h. After either limit it shows "--".
  - Accelerometer drift grows fast: a 1° error already adds about 6 km/h over 10 s. A wrong number is worse than "--".
  - Weak signal also shows whenever the filter's uncertainty is high, not only below a fixed GPS accuracy.
- **Ground truth without extra hardware.** I don't have a GNSS logger, so the targets are checked these ways:
  - **Offline reference, for lag and smoothness only.** A recorded drive is reprocessed with all of its data, before and after each moment. A smoother that can see the future has no lag.
    - It shares the GPS's own errors, so it is not used for absolute accuracy.
    - Two references are built, one fused and one GPS-only. A result counts only if both agree.
  - **Simulated tunnels.** On open-sky stretches of a recording, GPS is hidden for 5-15 s and the estimate is compared with the hidden fixes. This checks the ±3 km/h / 10 s rule directly.
  - **Steady speed by distance over time.** Distance travelled along the road, from all fixes over at least 3 km at steady highway speed, divided by time. It is compared with the average of the displayed speed over the same stretch. Position is measured separately from Doppler speed, so this checks the ±1 km/h target. 1 km is too short: position error and road curves alone can skew it by about 1 km/h.
  - **Sanity check.** A second speedometer app runs on another phone. It catches gross errors only.
  - The car speedometer is never the reference, because it reads high by design.
  - Limit: none of these catch an error the phone's GPS makes everywhere. A GNSS logger, if I get one later, can confirm the targets again.
- **Calibration offset: dropped.** Adding a percentage to match the car would make the number less true, which is the opposite of this intent.

## Open questions
- **Measured on the device during the build:**
  - The real fix rate.
  - How often speed is -1.
  - What iOS reports inside a tunnel.
  - The reporting delay.
  - How trustworthy `speedAccuracy` is.
  - The battery cost at 50 Hz.
- Left to the spec: whether to remember the learned mount direction across launches, and where the offline analysis code lives.
- Out of scope: calibration offset, OBD-II / Bluetooth car speed, CarPlay, background tracking, trip statistics.
