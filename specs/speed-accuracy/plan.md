# Plan: Accurate, responsive speed reading

**Spec:** specs/speed-accuracy/spec.md
<!-- Produced in Claude Code plan mode. Update in the same commit when implementation diverges. -->

## Context
- **Problem:** the speed lags real driving by 1-3 s.
  - Fixes arrive at 1 Hz and go through an EMA (α = 0.6).
  - Every fix counts the same, whatever its accuracy.
  - The reading drops to "--" in tunnels.
  - There is no way to measure accuracy.
- **Approved fix** (intent `intent/2026-10-25-speed-accuracy.md`, spec `specs/speed-accuracy/spec.md`):
  - a GPS-only Kalman filter weighted by accuracy;
  - optional GPS + motion-sensor fusion, which stays **off** until an accuracy gate passes on real recorded drives;
  - a Debug-only drive recorder and a replay harness, so accuracy is measured.

Owner decisions (2026-10-25):
- All 3 flagged concerns are approved: the Debug opt-in drive recording, `NSMotionUsageDescription`, and the CLAUDE.md Architecture change with an eval re-run.
- The spec becomes `approved` in step 0.

Work happens in **2 PRs** (owner choice), so I can start recording drives after PR 1 while PR 2 is built:
- **PR 1** `feat/speed-accuracy`: richer fixes, the GPS-only estimator, the motion source (recorded, not yet shown), the recorder, replay and measurement tools.
- **PR 2** `feat/speed-fusion`: the fused filter, forward-axis learning, reliability and stop detection, synthetic-drive targets and the accuracy gate. `fusionEnabled` stays false. Turning it on is a separate one-line change, with `results.md` as evidence.

## Files that change

### Core/Location (modified, PR 1)
- `Xpeet/Core/Location/SpeedProvider.swift`
  - `SpeedSample` gains `latitude`, `longitude`, `horizontalAccuracy`, `course`, `courseAccuracy`. An explicit init defaults them to invalid (−1 / 0), so the ~60 existing test call sites and the previews still compile.
  - A new `enum LocationUpdate: Sendable { case fix(SpeedSample), unavailable }`. `speedUpdates()` yields `LocationUpdate`.
- `CoreLocationSpeedProvider.swift`
  - Maps the new fields.
  - iOS 18+ `update.locationUnavailable` yields `.unavailable`, inside `if #available`, next to the existing `isDeviceStationary` shim.
  - Drops a fix whose timestamp is ≤ the previous one (R1).
- `FakeSpeedProvider.swift`: keeps `send(_ sample:)` and `init(samples:)`, both wrapped as `.fix`. Adds `sendUnavailable()`.

### New: `Xpeet/Core/Motion/` (PR 1). The only Core Motion importer.
- `MotionProvider.swift`:
  - `struct Vector3` (Foundation only: dot, cross, norm);
  - `struct MotionSample: Sendable` (timestamp since boot, userAcceleration m/s², gravity unit vector, rotationRate);
  - `@MainActor protocol MotionProvider { func motionUpdates() -> AsyncStream<[MotionSample]> }`.
- `CoreMotionProvider.swift`. It mirrors `SoundAnalysisTriggerDetector`'s queue-confined `@unchecked Sendable` pipeline (`Xpeet/Core/Audio/SoundAnalysisTriggerDetector.swift:99`).
  - A lazy single `CMMotionManager` and a serial `OperationQueue`.
  - `.xArbitraryZVertical` at 1/50 s.
  - Batches of 5, `.bufferingNewest(8)`.
  - If `!isDeviceMotionAvailable`, the stream finishes at once.
  - `onTermination` stops updates on the main actor.
- `FakeMotionProvider.swift` (`#if DEBUG`): `send(_ batch:)`, `finish()`.

### New: `Xpeet/Features/Speedometer/Estimation/` (pure value types, Foundation only)
- PR 1:
  - `SpeedEstimator.swift`: the orchestrator.
    - Inputs: `fix(_:)`, `motion(_:)`, `unavailable(at:)`, `tick(now:)`.
    - Outputs: `gpsOnly`/`fused: Estimate?` (speed, σ), `shown`, `inGap`, `gapStarted`. Plus `Configuration` (`fusionEnabled`, `usesPositionSpeed`, every constant from the spec table).
    - In PR 1 the fused path is absent (`fused == nil`).
  - `GPSOnlyFilter.swift`
    - 2-state constant-acceleration Kalman filter. R = (k_R·max(acc, 0.1))².
    - Physics bound of 12 m/s². A fix with Δt ≤ 0 is an update with no predict step.
    - Position-derived speed (R13) sits behind `usesPositionSpeed`.
  - `MotionClock.swift`: running-minimum offset from motion time to `Date` (R3).
- PR 2:
  - `FusedFilter.swift`: state [v, b]. Predict per sample. Q terms (q_v, k_sf, σ_δ). A 3 s ring buffer and replay for τ. NIS gate 9, re-init after 3 rejections.
  - `ForwardAxisLearner.swift`: horizontal basis (e1, e2) from gravity; recursive least squares with λ 0.99; convergence (σθ < 3°, gain 0.85-1.15, Σα² ≥ 20); re-learns on re-mount.
  - `MotionReliability.swift`: the 4 handling triggers, 3 s quiet to resume, re-mount detection.
  - `StopDetector.swift`: still over 1 s, AND (GPS < 0.5 m/s, or the stationary flag, or v < 1 m/s). Gives a bias reset value.

### New: `Xpeet/Core/Recording/` (PR 1)
- `DriveEvent.swift` (compiled in Release too, tiny):
  - a `Codable` tagged enum: `header`, `fix`, `unavailable`, `motion`, `shown`;
  - `protocol DriveLogging: Sendable { func record(_:) }`;
  - `enum DriveLog { static func makeDefault() -> DriveLogging? }`, which returns nil in Release.
- `DriveRecorder.swift` (`#if DEBUG`)
  - On only with the launch argument `-XpeetRecordDrives YES`.
  - `record` yields into an `AsyncStream` continuation. One writer task encodes JSON Lines into `Documents/Drives/<yyyyMMdd-HHmmss>.jsonl`, buffered.
  - Keeps the 5 newest files, sorted by name.
  - A failure finishes the stream silently.
  - The file sink is injectable for tests.

### Modified
- `Xpeet/Features/Speedometer/SpeedometerViewModel.swift`
  - **New init parameters:**
    - `motionProvider: MotionProvider?` (default `CoreMotionProvider()`);
    - `recorder: DriveLogging?` (default `DriveLog.makeDefault()`);
    - `estimatorConfiguration` (default reads `-XpeetFusion` in Debug).
  - **Estimator replaces the EMA:**
    - `smoothedMetersPerSecond` and `smoothingFactor` are removed.
    - `@ObservationIgnored var estimator`.
    - `handle(sample:)` keeps its name. New handlers: `handle(unavailable:)` and `handle(motion:)`.
  - **Shown number:**
    - `displayedSpeed` becomes stored and observed, and is set only when the rounded value or the state changes. That gives at most 10 Hz invalidation.
    - A 0.6 hysteresis is applied; `toggleUnit()` recomputes without it.
    - The rounding helper keeps the exact line `guard metersPerSecond >= Self.zeroClampMetersPerSecond else`, because the eval `evals/cases/fix-zero-clamp.json` seds it.
  - **States and readers:**
    - Weak signal = σ > 0.5 m/s, or a gap in progress.
    - GPS-only gap: hold for 5 s, then Acquiring (the existing `staleInterval`).
    - The mood is fed per accepted fix with `estimator.gpsOnly`.
  - **`run()`:**
    - adds a motion task to the task group;
    - the tick drops from 1 s to 0.5 s, so a 1.5 s gap start is detected on time;
    - writes `shown` events to the recorder.
- `Xpeet/Features/Speedometer/Faces/GaugeDisplay.swift:39`: `.smooth(duration: 0.6)` becomes `.linear(duration: 0.1)` (R16). Reduce Motion is unchanged.
- `Xpeet/Features/Speedometer/SpeedometerView.swift` (preview helper ~l.234) and `XpeetTests/GaugeGeometryTests.swift:27,74`: inject `FakeMotionProvider()` and `recorder: nil`.
- `project.yml`: `INFOPLIST_KEY_NSMotionUsageDescription` (R33). Then `xcodegen generate`.
- `CLAUDE.md` Architecture: add lines for `Core/Motion/`, `Core/Recording/` (Debug recorder) and `Features/Speedometer/Estimation/`.
- "Superseded/Amended by specs/speed-accuracy" notes in `specs/speedometer/spec.md` (R4-R12, weak row, Non-functional), `specs/speedometer-gauge/spec.md` R10 and `specs/gauge-themes/spec.md` R15.

### Tools and docs
- `scripts/pull-drives.sh` (new, PR 1)
  - Uses `devicectl device info files` to list `Documents/Drives`.
  - Copies the files one by one, with `devicectl device copy from --domain-type appDataContainer --domain-identifier app.plouton.xpeet`, into the gitignored `build/drives/`.
- `scripts/install-device.sh`: optional `RECORD=1`, which launches with `-- -XpeetRecordDrives YES` (and `FUSION=1` for `-XpeetFusion YES`).
- `scripts/make-fixture.py` (new, stdlib only, run with `python3 -I`): trims a drive to ≤ 2 min, turns lat/lon into metres relative to the first fix and dates into seconds from the start, and writes `XpeetTests/Fixtures/Drives/<name>.jsonl` (R31).
- `specs/speed-accuracy/results.md` (new): the R30 measurements, then the R28 gate results.

### Tests (new files; `SpeedometerViewModelTests.swift` modified)
- PR 1:
  - `GPSOnlyFilterTests.swift`, `SpeedEstimatorTests.swift`, `MotionClockTests.swift`, `DriveRecorderTests.swift`.
  - `XpeetTests/Accuracy/`:
    - `DriveFile.swift` (a JSON Lines loader that rejects absolute coordinates in fixtures);
    - `DriveReplay.swift`;
    - `DriveReplayTests.swift`;
    - `AccuracyReportTests.swift` (R29/R30 metrics over `build/drives/`, located via `#filePath`; `XCTSkip` when empty; writes `build/drives/report.txt`).
- PR 2:
  - `FusedFilterTests.swift`, `ForwardAxisLearnerTests.swift`, `MotionReliabilityTests.swift`, `StopDetectorTests.swift`.
  - `XpeetTests/Accuracy/`:
    - `SyntheticDrive.swift` (a seeded generator);
    - `RTSSmoother.swift` (fused, and GPS-only constant-acceleration);
    - `FusionTargetTests.swift` (R27);
    - `AccuracyGateTests.swift` (R28; skips without drives).
- `SpeedometerViewModelTests.swift`: the tests for superseded R9-R11 and the 2 m/s weak-signal test are rewritten (the spec says the behaviour changes). All other existing tests must pass unchanged: the first fix initialises the filter exactly.

## Order of work
Each step: `xcodegen generate` if files were added, then `scripts/verify.sh` with the Bash sandbox off (simulator), then commit.

**PR 1 (`feat/speed-accuracy`)**
0. Commit intent + spec (`Status: approved`) + this plan as `specs/speed-accuracy/plan.md`.
1. Location: new `SpeedSample` fields, `LocationUpdate`, provider mapping and duplicate drop, the fake's `sendUnavailable`. VM: `run()` switches on `LocationUpdate`. No behaviour change, all tests green.
2. `GPSOnlyFilter` + `SpeedEstimator` (GPS-only), with their tests first.
3. VM uses the estimator:
   - the observed `displayedSpeed` with hysteresis;
   - weak signal from σ;
   - gap handling;
   - the mood from GPS-only;
   - a 0.5 s tick.

   Rewrite the superseded tests and add the new VM tests.
4. `GaugeDisplay` 0.1 s linear animation. Manual check in the Freeway Drive preview/simulator.
5. `Core/Motion` + `MotionClock` + `project.yml` usage key. VM `handle(motion:)` feeds the estimator, which only records it (fusion is absent). Inject fakes in previews and `GaugeGeometryTests`.
6. `Core/Recording` + recorder tests + VM hooks + the failing-recorder test.
7. `XpeetTests/Accuracy` loader, replay and report. `scripts/pull-drives.sh`, `make-fixture.py`, the `install-device.sh` flags.
8. CLAUDE.md lines and the supersede notes in older specs. `scripts/verify.sh`, then `evals/run.sh` + `scripts/check-bands.sh`. `reviewer` and `verifier` agents, then the PR.
9. On the device: `RECORD=1 scripts/install-device.sh`, ≥ 3 drives (city, highway, tunnel), `scripts/pull-drives.sh`, the report. Fill `results.md` (R30): fix rate, share of −1, tunnel behaviour, τ, k_R, typical σ, battery at 50 Hz on vs off.

**PR 2 (`feat/speed-fusion`, after PR 1 merges and drives are recorded)**
10. `FusedFilter` + tests (R6-R8).
11. `ForwardAxisLearner` + tests (R9).
12. `MotionReliability`, `StopDetector` + tests (R10-R12).
13. `SpeedEstimator` fused path:
    - which estimate is shown (R14);
    - the fused gap rule (R18);
    - the axis is kept across a reset (R19);
    - the VM refreshes on each motion batch when fused.
14. `SyntheticDrive` + `FusionTargetTests` (R25, R27).
15. RTS references + `AccuracyGateTests`. Set τ and k_R from `results.md`, run the gate on the recorded drives, and write the outcome to `results.md` (R28). Commit 1-2 anonymised clips (R31).
16. Verify, evals, reviewer, PR. Fusion stays off. If the gate passed, a follow-up one-line PR flips `fusionEnabled`.

## Deviations
PR 1:
- **ViewModel names:**
  - The "unavailable" handler is `handleLocationUnavailable()`, not `handle(unavailable:)`.
  - `displayedSpeed` stays computed: it reads a stored, observed `shownSpeed` while Live. Leaving Live hides the number with no extra bookkeeping.
- **Recorder:**
  - It is injected as a per-run factory (`makeRecorder`), because the spec writes one file per `run()`.
  - A recording that never got a fix is deleted when it closes, so opening the app briefly cannot push a real drive out of the 5 kept files.
  - A run token stops an ending run from clearing a newer run's recorder.
- **Fixtures (R31):** coordinates are converted to metres from the first fix, then written back as degrees around 0°, 0° on the app's sphere. That keeps distances exact for `SpeedEstimator.distance`, and no real place is left. The loader rejects anything beyond 0.5° or any real date.
- **Small additions:**
  - `GPSOnlyFilter.predicted(at:)`, for the k_R measurement.
  - `SpeedometerState.recordedName`, shared by the recorder and the replay.
  - `scripts/device-id.sh`, extracted from `install-device.sh` and also used by `pull-drives.sh`.
  - The accuracy maths lives in `XpeetTests/Accuracy/AccuracyReport.swift`.
- **τ in PR 1:** the report estimates it from acceleration magnitudes. The signed forward-axis estimate comes with PR 2.
- **Rewritten tests:**
  - `testToggleUnitConvertsWithoutResettingFilter` and `testChangingFaceDoesNotResetFilter` used a 100 → 50 km/h jump within one instant, which the 12 m/s² physics bound rejects (correctly). They now use 100 → 90.
  - The EMA tests became `testFollowsHardBrakingWithinOneFix`, `testFollowsAccelerationWithinOneFix`, `testHysteresisHoldsNumber` and `testUnitToggleRecomputesWithoutHysteresis`.
  - `testMoodUsesFilteredSpeed` became `testMoodUsesGPSOnlyEstimate`.

- **Review fixes (reviewer agent, 2026-10-25):**
  - **GPS-only gate:** a fix is judged against the last accepted speed, not the prediction, and the acceleration state is clamped to ±12 m/s². One accepted glitch used to lock out the true fixes for about 5 s. The plan's R8-style re-init after rejections is not needed for GPS-only: the bound grows with the time since the last accepted fix.
  - **Provider:**
    - a repeated fix passes when only its stationary flag changed, because that is how a stop arrives;
    - "unavailable" is checked before the location.
  - **Recorder:**
    - the Drives folder is excluded from backups;
    - pruning happens only when a recording is kept;
    - the file is opened in the writer task, off the main actor;
    - `-XpeetRecordDrives` and `-XpeetFusion` are read from the launch-argument domain only (`App/LaunchArguments.swift`);
    - the header carries every constant and rate.
  - **ViewModel:**
    - an ignored or rejected fix keeps its estimator state (its position, for R13);
    - each `run()` starts a fresh motion clock, because Core Motion's clock pauses while the phone sleeps;
    - display values use exact unit factors, and an estimate exactly 0.6 away holds. Spec R15 now says "more than 0.6", to match its own 59.4 ↔ 60.4 example.
  - **Motion:**
    - an ending stream stops the manager only if no newer stream started;
    - the handler is built off the main actor.
  - **Replay:**
    - motion is replayed in its recorded batches;
    - unit changes are followed;
    - mid-drive clips compare state and GPS-only estimate after a 10 s warm-up instead of the exact number.
  - **`pull-drives.sh`:** copies to a temporary name, and always re-pulls the newest drive.
- **Verifier fixes (verifier agent, 2026-10-25):**
  - The new ViewModel tests moved to `SpeedometerViewModelTests+Accuracy.swift`, an extension sharing the main file's helpers (now internal). The main file had passed SwiftLint's 1000-line limit.
  - Lines over 140 characters are wrapped.
  - R29 compares against the time-average of the shown estimate.
  - `-XpeetMotionOff YES` (`MOTION_OFF=1 scripts/install-device.sh`) runs without motion, for the R30 battery comparison. Tested in `LaunchArgumentsTests.swift`.
  - `state` and `mood` are assigned only when they change.
  - Spec R1, R5 and R22 now say what the reviewed code does.

## Risks
- **Eval coupling:** `fix-zero-clamp` seds the literal guard line in `SpeedometerViewModel.swift`, and `rename-weak-signal-status` greps "Weak GPS signal". Keep both strings, or the eval suite breaks.
- **Existing VM tests:** several of them send 2 fixes with the same timestamp. The filter treats Δt ≤ 0 as an update with no predict step, which blends the two. Any test that changes value under this is updated and listed under Deviations.
- **Concurrency (Swift 5, minimal checking):**
  - `CMDeviceMotion` is not Sendable, so it is copied into `MotionSample` on the motion queue.
  - Batching keeps main-actor hops at 10/s.
  - The estimator is `@ObservationIgnored`, so 50 Hz maths does not invalidate SwiftUI.
  - The recorder writes off the main actor through one continuation (no Task per event).
- **"No completion handlers" convention:** Core Motion has no async API on iOS *(research)*. The handler is bridged to `AsyncStream` inside `Core/Motion`, as `Core/Audio` does.
- **iOS 17:** no `locationUnavailable` and no `stationary`. Both sit behind `#available`. The gap then starts after 1.5 s without a fix.
- **Simulator:** no device motion, so `CoreMotionProvider` finishes at once and the app runs GPS-only. Fusion is tested only with synthetic or recorded drives and on a device.
- **Recorder privacy:**
  - Debug only, launch argument only, 5 files kept.
  - Full drives live in the gitignored `build/drives/`.
  - Fixtures go through `make-fixture.py`; the loader test fails on absolute coordinates.
- **devicectl:** check the launch-argument passthrough (`process launch … -- -XpeetRecordDrives YES`) and the per-file copy on the device. Directory copies are reported to time out *(research)*.
- **Accuracy:**
  - τ and the speedAccuracy confidence are undocumented. Measure them before any tuning (step 9).
  - The gate may fail, in which case fusion ships off. That is an accepted outcome.
- **Battery:** unmeasured on modern iPhones. Measure at 50 Hz in step 9. The owner decides whether the cost is acceptable.
- **SwiftLint** isn't installed locally (lint is skipped). `--strict` file-length limits still apply in CI-like runs, so new tests go in their own files and `SpeedometerViewModelTests.swift` stays under its current size plus about 150 lines.

## Proof
| Req | Proof |
|---|---|
| R1 | `SpeedometerViewModelTests.testUnavailableUpdateStartsGap`, `GPSOnlyFilterTests.testSameTimestampUpdatesWithoutPredict`; review: field mapping + duplicate drop in `CoreLocationSpeedProvider` |
| R2 | `SpeedometerViewModelTests.testRunFeedsMotionBatchesToEstimator`, `testFinishedMotionStreamKeepsGPSOnly`; review: frame and 50 Hz; manual: device |
| R3 | `MotionClockTests.testOffsetIsRunningMinimum`, `testMapsMotionTimestampToDate`; `SpeedometerViewModelTests.testEachRunStartsAFreshMotionClock` |
| R4 | `SpeedEstimatorTests.testSameInputsSameOutputs`, `testKeepsGPSOnlyEstimateWithoutFusion` (PR 1); `testKeepsBothEstimates` (PR 2) |
| R5 | `GPSOnlyFilterTests.testMatchesHandComputedStep`, `testLessAccurateFixMovesEstimateLess`, `testImpossibleJumpIsRejected`, `testBoundGrowsWithTimeSinceLastAcceptedFix`; `SpeedEstimatorTests.testFirstFixInitialisesExactly`; `SpeedometerViewModelTests.testFollowsHardBrakingWithinOneFix`, `testFollowsAccelerationWithinOneFix`; `GPSOnlyFilterTests.testGlitchRecoversWithinThreeFixes` |
| R6 | `FusedFilterTests.testPredictIntegratesForwardAcceleration`, `testCorrectionWeightsBySpeedAccuracy`, `testBiasConvergesOnSyntheticDrive` |
| R7 | `FusedFilterTests.testDelayCompensationReducesLag`, `testHistoryCappedAtThreeSeconds` |
| R8 | `FusedFilterTests.testHighInnovationFixRejected`, `testThreeRejectionsReinitialise` |
| R9 | `ForwardAxisLearnerTests.testConvergesForRandomMounts` (including upside down and backwards), `testConstantSpeedNeverConverges`, `testSkipsInaccurateFixes` |
| R10 | `MotionReliabilityTests.testEachHandlingTriggerMarksUnreliable`, `testReliableAfterThreeQuietSeconds`, `testRemountRestartsAxisLearning` |
| R11 | `SpeedEstimatorTests.testUnreliableMotionShowsGPSOnly`, `testEndedMotionStreamShowsGPSOnly` |
| R12 | `StopDetectorTests.testStillAndLowGPSSpeedStops`, `testStillAloneDoesNotStop`, `testStopResetsBias`; existing `SpeedometerViewModelTests.testStationaryShowsZero` |
| R13 | `SpeedEstimatorTests.testNegativeSpeedIgnoredByDefault`, `testPositionSpeedUsedWhenEnabledAndAccurate`, `testPositionSpeedSkippedWhenInaccurate`, `testPositionSpeedSkippedOutsideInterval`; `SpeedometerViewModelTests.testPositionSpeedStartsFromAcquiring` |
| R14 | `SpeedEstimatorTests.testShowsGPSOnlyWhenFusionDisabled`, `testFusionLaunchArgumentOnlyInDebug` (PR 1); `testShowsFusedWhenConvergedAndReliable`, `SpeedometerViewModelTests.testFusedRefreshesOnMotionBatch` (PR 2) |
| R15 | `SpeedometerViewModelTests.testHysteresisHoldsNumber`, `testUnitToggleRecomputesWithoutHysteresis`, existing `testSpeedBelowOneKmhShowsZero`, `testDisplayIsNeverNegative`; `SpeedometerViewModelTests.testHysteresisHoldsSpecWobble` |
| R16 | manual: device drive with Reduce Motion on/off; review `GaugeDisplay` |
| R17 | `SpeedEstimatorTests.testGapStartsAfterOnePointFiveSeconds`, `testUnavailableStartsGap`, `testFixEndsGap` |
| R18 | `SpeedometerViewModelTests.testGPSOnlyGapHoldsWeakThenAcquiring`, `testFusedGapEndsOnUncertainty`, `testFusedGapEndsAfterTenSeconds`, existing `testStaysAtZeroWhenStationaryUpdatesPause` |
| R19 | existing `SpeedometerViewModelTests.testFilterResetsAfterAcquiring`, `testFilterResetsWhenSampleArrivesAfterGap`; `SpeedEstimatorTests.testAxisKeptAcrossReset` |
| R20 | `SpeedometerViewModelTests.testWeakSignalWhenSigmaAboveLimit`, `testUnavailableUpdateStartsGap`; `SpeedEstimatorTests.testWeakSignalWhenSigmaAboveLimit`, `testWeakSignalDuringGap` |
| R21 | `SpeedometerViewModelTests.testMoodUsesGPSOnlyEstimate` (rewritten), existing `testEngineSoundSeesMovingFromDisplayedSpeed` |
| R22 | `DriveRecorderTests.testOffWithoutLaunchArgument`, `testWritesAllLineTypes`, `testKeepsFiveNewestByName`, `testRecordingWithoutFixIsDeleted`; `SpeedometerViewModelTests.testRunRecordsHeaderInputsAndShown`; review: `#if DEBUG`, Release build; `DriveRecorderTests.testRecordingWithoutFixKeepsOldDrives`, `testDrivesAreExcludedFromBackup` |
| R23 | `DriveRecorderTests.testWriteFailureStopsSilently`, `SpeedometerViewModelTests.testFailingRecorderDoesNotChangeOutput` |
| R24 | manual: `scripts/pull-drives.sh` on device |
| R25 | `SyntheticDriveTests.testSameSeedSameDrive`, `testProfileHasAllSegments` |
| R26 | `DriveReplayTests.testReplayMatchesLiveFeed`, `testClipFromMiddleMatchesAfterWarmUp`, `testFixturesReplayAfterWarmUp` |
| R27 | `FusionTargetTests.testSteadySpeedError`, `testHardBrakeLag`, `testTunnelWithinThreeKmh`, `testHandlingFallsBackToGPSOnly` |
| R28 | `AccuracyGateTests` on `build/drives/` + `results.md` (manual) |
| R29 | `AccuracyReportTests.testSteadyStretchDistanceMatchesSpeed`, `testShortOrUnsteadyDrivesHaveNoStretch`; `testDistanceOverTime` on `build/drives/` + `results.md` (manual) |
| R30 | `AccuracyReportTests.testGapWhileMovingIsFound`, `testMissingSpeedCountsUsableFixes`; `testReportOnRecordedDrives` + Xcode energy gauge + `results.md` (manual) |
| R31 | `DriveReplayTests.testFixturesHaveNoAbsoluteCoordinates`, `testLoaderRejectsAbsoluteCoordinates`; review `make-fixture.py` |
| R32 | review CLAUDE.md; `evals/run.sh` + `scripts/check-bands.sh` |
| R33 | review `project.yml`; manual: fresh install shows no motion prompt |

Run `scripts/verify.sh` (sandbox off) after every step and paste the tail.
