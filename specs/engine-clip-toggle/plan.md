# Plan: Turn the engine-start clip on or off

**Spec:** specs/engine-clip-toggle/spec.md
<!-- Produced in Claude Code plan mode. Update in the same commit when implementation diverges. -->

## Context
- **Problem.** The engine-start clip can't be turned off. It plays over passengers and ignores the ring/silent switch. The mic and the classifier run, with the orange dot showing, whenever the speed screen is active. The only way out today is to deny the mic, and then the mic chip shows.
- **Approved.** The owner approved intent `intent/2026-10-30-engine-clip-toggle.md` (accepted) and spec `specs/engine-clip-toggle/spec.md` on 2026-10-30, including every flagged concern and proposed default.
  - **Focus filter:** R15–R19 stay in this spec, gated behind the R14 device spike, and are built last.
- **Outcome.** An "Engine sounds" switch in the gauge style sheet:
  - on by default and stored under `engineSound.enabled`;
  - off stops the mic, the classifier, any playing clip and the mic chip within the same `run()`;
  - on resumes at once.

  If the spike passes, an optional Focus filter does the same while a chosen Focus is on.
- **Sequence.** Third of three stacked specs, so `specs/precise-location` and `specs/break-reminder` are already on the base branch.
  - The chip resolver `chip` in `SpeedometerViewModel` ranks: location status, then the break reminder, then `engineSound.chipText`.
  - This spec gates tier 3 inside `EngineSoundViewModel.chipText`, so the resolver doesn't change.
- **Branch.** `feat/engine-clip-toggle` from `feat/break-reminder`, one PR with base `feat/break-reminder`.
  - **Part A** (R1–R13, R20 notes) ships regardless.
  - **Part B** (R14 spike, then R15–R19) follows only if the spike passes.

## Files that change

### Part A
- **`Xpeet/Features/EngineSound/EngineSoundViewModel.swift`**
  - Observed `private(set) var isEnabled = true`.
  - `func handle(enabled:)` sets it, notifies a running `runFollowingSwitch()`, then `requestMicIfReady()`.
  - Gates:
    - `chipText` is nil while off (R7);
    - `requestMicIfReady()` guards `isEnabled` (R6);
    - `run()` guards `isEnabled` before listening.
  - New `func runFollowingSwitch() async` starts and cancels a listening `run()` as the switch changes, without ending itself (R4, R9).
    - Each change cancels the current listening task and awaits it, then starts a new one when on.
    - When the owner is cancelled, the last task is cancelled and awaited.
    - `run()` keeps its contract, so the existing tests pass unchanged (R10).
- **`Xpeet/Features/Speedometer/SpeedometerViewModel.swift`**
  - `engineSoundsDefaultsKey = "engineSound.enabled"`.
  - `private(set) var engineSoundsOn`, read through a pure `engineSoundsSetting(from:)` in which only a real Bool counts (R2).
  - `setEngineSounds(_:)` saves the value and forwards it.
  - `runEngineSound()` calls `runFollowingSwitch()`.
- **`Xpeet/Features/Speedometer/Faces/FacePickerSheet.swift`**: a "Sound" section under the grid, inside the existing scroll view, with a header, a `Toggle` and a help line. The help line is the switch's hint and is hidden as its own element. Previews: on, off, AX3, landscape (R1, R12).
- **`Xpeet/Features/Speedometer/SpeedometerView.swift`**:
  - `faceButtonHint` becomes "Double-tap for gauge faces and engine sounds" (R13);
  - wires the sheet;
  - adds a preview with the mic denied and engine sounds off.
- **`Xpeet/Core/Audio/SoundAnalysisTriggerDetector.swift`**: a new `events()` waits for the previous teardown to finish. The deactivate runs only if no newer pipeline took over.
- **`Xpeet/Core/Audio/FakeSoundTriggerDetector.swift`**: `FakeSoundPlayer.play` honours cancellation, as the real player does, and counts it.
- **Tests:**
  - `EngineSoundViewModelTests` (new cases);
  - new `SpeedometerViewModelTests+EngineSounds.swift`;
  - `GaugeFaceTests.testAccessibilityStrings`: the R13 hint, a change the spec allows.

### Part B (only if R14 passes)
- New `Xpeet/Core/Focus/`, the only code that imports AppIntents:
  - `FocusFilterProvider` (protocol) and a pure `FocusFilterOverride` mapping;
  - `EngineSoundsFocusFilter` (`SetFocusFilterIntent`, default false);
  - an in-memory relay and `AppIntentsFocusFilterProvider`, which reads `current` on each run;
  - `FakeFocusFilterProvider` (`#if DEBUG`).
- `SpeedometerViewModel+Focus.swift`: the effective switch and the mic prompt hold (R16).
- The sheet's disabled state and note (R18).
- CLAUDE.md `Core/Focus/` line, then evals.

## Order of work
Each step: `xcodegen generate` when files are added, then `scripts/verify.sh` with the Bash sandbox off, then commit.
0. Set the spec to approved. Commit the intent, the spec and this plan.
1. Fakes and audio teardown, with no behaviour change.
2. `EngineSoundViewModel` gates and `runFollowingSwitch()`, tests first.
3. `SpeedometerViewModel` switch and `+EngineSounds` tests, including the chip order with engine sounds on and off (break-reminder R10's "off" rows).
4. Sheet, wiring, R13 hint, previews. Simulator check: iPhone SE scrolling at medium height, AX sizes.
5. Older-spec notes, merged into the combined wording with break-reminder's notes.
6. Review workflow, verify, PR. Device checks R5, R8 and R9 by the owner.
7. Part B: R14 spike on `spike/focus-filter`, then stop for the owner's device check. Build R15–R19 only if it passes; otherwise mark them Dropped in the spec.

## Deviations
(none yet)

## Risks
- **Teardown race.** On a fast off→on, the old `AudioSession.deactivate()` could run after the new `activate()` and silently stop the new engine. Step 1 serializes them. The device check covers rapid toggles.
- **Fake player and cancellation.** The current fake ignores cancellation, which would hang a cancelled run in tests. Fixed in step 1.
- **Main-actor stalls.** Engine start and stop run on the main actor; toggling while Live must not stall the number. Manual check.
- **UserDefaults typing.** `bool(forKey:)` bridges numbers and strings. The pure reader accepts only a real Bool.
- **Help line contrast.** The sheet uses `.ultraThinMaterial`, and Retro is light. Fall back to `.primary` if `.secondary` fails.
- **Eval coupling.** New tests avoid the "Weak GPS signal" literal.

## Proof
| Req | Proof |
|---|---|
| R1 | `GaugeFaceTests.testSoundSectionStrings`; previews; manual: iPhone SE at medium height |
| R2 | `SpeedometerViewModelTests.testEngineSoundsOnWhenNothingStored`, `testEngineSoundsOnWhenStoredValueIsNotBool`, `testEngineSoundsOffIsRestored` |
| R3 | `testTogglingEngineSoundsChangesNothingElse` |
| R4 | `EngineSoundViewModelTests.testDisablingEndsEventsWhileRunContinues`, `testRunWhileDisabledNeverListens`; `SpeedometerViewModelTests.testEngineSoundsOffStopsListeningWhileRunContinues` |
| R5 | `EngineSoundViewModelTests.testDisablingStopsClipAndCooldownStillApplies`; manual: device |
| R6 | `EngineSoundViewModelTests.testDisabledDoesNotRequestMic`, `testEnablingRequestsDeferredMic`; `SpeedometerViewModelTests.testEngineSoundsOffDefersMicPromptWithPreciseLocationOff` |
| R7 | `EngineSoundViewModelTests.testDisabledHidesMicChip`; `SpeedometerViewModelTests.testEngineSoundsOffHidesMicChip` |
| R8 | manual: device, screen recording |
| R9 | `EngineSoundViewModelTests.testEnablingListensAgainInSameRun`, `testRapidToggleEndsWithNoSubscribers`, `testEnablingRetriesAfterFailure`, `testEnablingWithMicDeniedShowsChipWithoutPrompt`; manual: device |
| R10 | existing `EngineSoundViewModelTests` unchanged; `testTogglingDoesNotResetCooldown` |
| R11 | `SpeedometerViewModelTests.testChipOrderWithEngineSoundsOnAndOff` |
| R12 | `GaugeFaceTests.testSoundSectionStrings`; manual: Accessibility Inspector, largest size, contrast |
| R13 | `GaugeFaceTests.testAccessibilityStrings` |
| R14 | spike results table in this plan (gates a and b) |
| R15–R19 | Part B tests and device checks, or Dropped after R14 |
| R20 | review of the older-spec notes; CLAUDE.md and evals only if Part B ships |
