# Plan: Play a fun sound when the engine starts

**Spec:** specs/engine-sound-clip/spec.md
<!-- Produced in Claude Code plan mode. Update in the same commit when implementation diverges. -->

This is PR 4 (after gauge themes, mascot and visual polish). Work on branch `feat/engine-sound-clip`, cut from the mascot branch, or from `main` once the earlier PRs are merged.

## Files that change

### New: `Xpeet/Core/Audio/`
This becomes the only folder that imports AVFoundation or SoundAnalysis.

- `SoundTriggerDetector.swift`
  - Types:
    - `MicAuthorization` with cases `notDetermined`, `authorized`, `denied`.
    - `SoundTriggerEvent` with `label`, `confidence`, `timestamp`.
  - A `@MainActor` protocol with:
    - `authorizationUpdates()`
    - `requestAuthorization()`
    - `events()`
    - `pause()` and `resume()`
  - The detector yields one raw event per analysis window, carrying the best trigger label even when its confidence is low. The threshold and streak rules live in the ViewModel, not here.
- `SoundPlayer.swift`
  - `enum SoundFile: String, CaseIterable { ohayo, vroom }`
  - `play(_:) async throws`, which returns when playback ends.
- `AudioSession.swift`
  - Category `.playAndRecord` with options `[.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP]`. No HFP.
  - Prefers the built-in mic, on a best-effort basis.
- `SoundAnalysisTriggerDetector.swift`
  - Pipeline: an `AVAudioEngine` tap, then a serial queue, then `SNAudioStreamAnalyzer` with `.version1`, a 1.5 s window and 0.5 overlap.
  - An `NSObject` `SNResultsObserving` object forwards results into an `AsyncStream`.
  - Interruptions, configuration changes and media-services resets are handled through `NotificationCenter.notifications`.
  - Any failure finishes the stream.
- `AVAudioPlayerSoundPlayer.swift`: bridges the delegate with a checked continuation and handles cancellation.
- `FakeSoundTriggerDetector.swift`, `FakeSoundPlayer.swift`: behind `#if DEBUG`.

### Other new files
- `Xpeet/Features/EngineSound/EngineSoundViewModel.swift`: `@Observable @MainActor`. It takes an injected detector, player, `now` and `random`.
  - Constants: the trigger labels, threshold 0.6, 2 windows, a maximum window gap of 1.5 s, a 60 s cooldown, a 0.5 s tail.
  - Handlers:
    - `handle(locationAuthorizationResolved:)`
    - `handle(micAuthorization:)`
    - `handle(event:) -> SoundFile?`
    - `handlePlaybackFinished()` / `handlePlaybackFailed()`
    - `handleListeningEnded(cancelled:)`
  - Exposes `chipText` and `chipSymbol`.
  - `run()` runs two child tasks: one for events, one for playback.
- `Xpeet/Resources/Sounds/ohayo.m4a`, `vroom.m4a`: generated with `say`.
  - `ohayo`: voice "Flo (Tiếng Nhật (Nhật Bản))", `-r 210`.
  - `vroom`: voice "Boing".
  - Convert both with `afconvert -f m4af -d aac`.
- `Xpeet/Resources/Sounds/LICENSE.md`: where the sounds came from.

### Modified
- `Xpeet/Features/Speedometer/SpeedometerViewModel.swift`
  - Inject `engineSound`.
  - Set the `isMoving` closure from `displayedSpeed`.
  - `handle(authorization:)` notifies `engineSound` that location authorization is resolved.
  - Add a group task in `run()`.
  - Chip fallback: `statusText = locationStatusText ?? engineSound.chipText`.
- `Xpeet/Features/Speedometer/SpeedometerView.swift`: the preview helper injects fakes. Add a `#Preview("Mic off")`.
- `project.yml`
  - Add `INFOPLIST_KEY_NSMicrophoneUsageDescription`.
  - Sources become `path: Xpeet` with `excludes: ["Resources/Sounds/LICENSE.md"]`.
  - No `UIBackgroundModes`.
- `XpeetTests/EngineSoundViewModelTests.swift` (new), `XpeetTests/SpeedometerViewModelTests.swift` (modified). `makeViewModel` always injects fakes.
- `CLAUDE.md` Architecture: add one line about `Core/Audio/` (approved by the owner). Run the evals.

## Order of work
1. `project.yml`, the protocols and the fakes. Run `xcodegen generate` and build.
2. `EngineSoundViewModel` and its tests.
3. The sounds, `LICENSE.md`, `AudioSession` and the player, plus the bundle test.
4. The SoundAnalysis detector and the production defaults.
5. Wire it into `SpeedometerViewModel`, its tests and the previews.
6. The CLAUDE.md line, `scripts/verify.sh` and the evals. Then the manual checks on a device via `scripts/install-device.sh`.

## Deviations
- The sound licence note is `Xpeet/Resources/Sounds/SOUNDS-LICENSE.txt`, bundled like the fonts' OFL files, instead of a `LICENSE.md` excluded in `project.yml`. No `excludes` entry is needed.
- `EngineSoundViewModel.handleListeningStarted()` is a handler of its own, so the event rules are unit-tested synchronously without `run()`.
- `SNTimeDurationConstraint` is a Swift enum: the 1.5 s window is applied only when it falls inside `.durationRange`; otherwise the classifier keeps its default window.
- `FakeSoundPlayer` lives in `FakeSoundTriggerDetector.swift`, not a file of its own.
- `project.yml` sources stay `[Xpeet]`: with the licence note bundled as a `.txt`, no `excludes` entry is needed.
- `XpeetTests/GaugeGeometryTests.swift` injects fake audio into its two view models, so no test can build the real detector.
- `specs/speedometer/spec.md` Out of scope now points to this spec for the sound.
- Review fixes: a sound cut off by the screen going away still starts the cooldown; the end of an older `run()` (and the detector's teardown) cannot reset a newer one; analyzer callbacks are matched to the live request instead of a flag; configuration changes are filtered to this engine; an enumerated window constraint picks the duration nearest 1.5 s.
- The `SpeedometerView` preview helper and previews are wrapped in `#if DEBUG` (they use DEBUG-only fakes), so a Release build compiles.
- Three lines over 140 characters in `DialFace.swift` (from the visual-polish PR) are wrapped here so SwiftLint `--strict` passes.

## Risks
- **Labels on iOS are unverified.** The `.version1` labels were only checked on macOS. If a label is missing on iOS, its confidence is 0 and the feature never fires. Check on a device.
- **The simulator cannot test detection.** The simulator mic is the Mac's mic, so detection thresholds can only be tuned in a real vehicle.
- **Threading in Swift 5 mode.** The pipeline is `@unchecked Sendable`. Its state is confined to the analysis queue, or to the main actor for start and stop.
- **Microphone prompt timing.** The automatic mic prompt goes against App Review 5.1.1 (permissions should be requested in context). This is accepted for a personal build.
- **SwiftLint file length.** `SpeedometerViewModelTests.swift` is already long, so the engine-sound tests go in their own file.

## Proof
| Req | Proof |
|---|---|
| R1 | `EngineSoundViewModelTests.testRunSubscribesToEventsWhenAuthorized`, `testCancellingRunStopsEvents`, `testRunDoesNotListenWhenDenied`, `testRunListensAfterAuthorizationGranted`; `SpeedometerViewModelTests.testRunStartsEngineSoundListening`; build: no `UIBackgroundModes` |
| R2 | `EngineSoundViewModelTests.testDoesNotRequestMicWhileLocationNotDetermined`, `testRequestsMicOnceAfterLocationResolved`, `testRequestsMicWhenLocationResolvedBeforeMicStatusArrives`, `testNeverRequestsMicWhenAlreadyAnswered`; `SpeedometerViewModelTests.testMicRequestedOnlyAfterLocationAnswered` |
| R3 | `EngineSoundViewModelTests.testTwoConsecutiveQualifyingWindowsFire`, `testSingleQualifyingWindowDoesNotFire`, `testLowConfidenceWindowBreaksStreak`, `testConfidenceExactlyThresholdQualifies`, `testEveryTriggerLabelQualifies`, `testNonTriggerLabelDoesNotQualify`, `testGapBetweenWindowsBreaksStreak`, `testConstants` |
| R4 | review: no file, log or network in `Core/Audio` |
| R5 | `EngineSoundViewModelTests.testRandomLowPicksOhayo`, `testRandomHighPicksVroom`, `testRandomOneIsClamped`, `testBundledSoundsExistAndAreAtMostThreeSeconds` |
| R6 | `EngineSoundViewModelTests.testEventWhileMovingIsDropped`, `testEventWhenStoppedPlays`, `testDroppedWhileMovingIsNotQueued`; `SpeedometerViewModelTests.testEngineSoundSeesMovingFromDisplayedSpeed` |
| R7 | `EngineSoundViewModelTests.testEventsDuringCooldownAreDropped`, `testPlaysAgainAfterSixtySeconds`, `testFailedPlaybackStartsNoCooldown`, `testCancelledPlaybackStartsCooldown` |
| R8 | `EngineSoundViewModelTests.testEventsWhilePlayingAreDropped`, `testEventsWithinHalfSecondAfterEndAreDropped`, `testEventAfterTailPlays`, `testPausesDetectorWhilePlayingAndResumesAfter`, `testRunPlaysThroughPlayerAndReturnsToListening` |
| R9, R10 | manual on device: music keeps playing, with and without Bluetooth; a call or Siri interrupts |
| R11 | `EngineSoundViewModelTests.testDeniedShowsMicChip`, `testAuthorizedAndNotDeterminedShowNoChip`; `SpeedometerViewModelTests.testMicChipShownWhenNoLocationStatus`, `testLocationChipTakesPriorityOverMicChip` |
| R12 | `EngineSoundViewModelTests.testFailingDetectorSetsFailedSilently`, `testStreamEndingMidRunSetsFailed`, `testFailedRunRetriesOnNextRun`, `testOldRunEndingDoesNotResetNewRun` |
| R13 | manual: Accessibility Inspector |

Run `scripts/verify.sh` after every step.
