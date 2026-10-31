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
6. Review workflow, verify, PR. Device checks R5, R8, R9 and R10 by the owner.
7. Part B: R14 spike on `spike/focus-filter`, then stop for the owner's device check. Build R15–R19 only if it passes; otherwise mark them Dropped in the spec.

## Deviations
- **Help line uses `.primary` (R12).** `.secondary` measured 3.0:1 over Retro's light sheet, below 4.5:1, so the help line falls back to `.primary` as R12 allows. It stays apart from the switch label by its smaller footnote size.
- **`runFollowingSwitch()` starts nothing once cancelled.** A change that arrives as the owner is cancelled doesn't start a short-lived `run()` (review nit).
- **`SoundTriggerDetector.events()` documents one reader at a time.** The serialized teardown assumes it (review nit).
- **Part B built without device gate (a) (owner decision, 2026-10-31).** Gate (b) passed on the spike: the `.app`'s `Metadata.appintents/extract.actionsdata` lists the filter with system protocol `com.apple.link.systemProtocol.FocusConfiguration`. The owner asked for the real filter instead of merging the spike (#18), so gate (a) and the device questions move to the device check after install. If iOS does not list the filter, nothing breaks: no Focus can turn it on, `current` throws, and that means no override.
- **`current` read timeout.** The spike didn't measure the read, so `AppIntentsFocusFilterProvider.currentReadTimeout` (2 s) is added now, as R17 allows. After it, there is no override. The race uses unstructured tasks, because a task group would wait for a read that never returns.
- **A `perform()` beats a slower `current` read.** If a `perform()` arrives while a stream's first read is still pending, the read's result is dropped as older.
- **Production provider as the init default.** `SpeedometerViewModel(focusFilter:)` defaults to `AppIntentsFocusFilterProvider()`, like the other production defaults. `nil` means no Focus filter: the test helper passes it unless a test gives a `FakeFocusFilterProvider`, and so do the previews. Without a provider, nothing waits for a first value. Before the first `run()`, the override is "none", so the switch alone sets `isEnabled` at launch. Each `run()` then starts with it unknown (R17).
- **The relay lives beside the intent.** `FocusFilterRelay` is in `EngineSoundsFocusFilter.swift`, so `perform()` touches only main-actor memory (R17).
- **Mic prompt hold.** `EngineSoundViewModel.holdMicPrompt()` / `releaseMicPrompt()`. The hold is set when an override goes from on to off. It is released at the start of each `SpeedometerViewModel.run()`, after engine sound is gated on the unknown override, and when the user turns the switch on (R16). A release with no hold asks nothing, so runs without a provider behave as before.

## Checks
- **Simulator, iPhone SE (3rd gen), iOS 17.5 (R1, R12).** Checked on 2026-10-31 with a throwaway patch that opens the sheet at launch, scrolls it and rotates the scene. The patch was reverted before commit.
  - **Medium height, portrait.** The Sound section sits below the 2×2 grid. Reaching it takes about one screen of scrolling (two thumbnail rows). Heading, switch and help line are all visible once scrolled.
  - **Landscape.** The sheet opens full height. The section is reached by scrolling past the grid, and the help line fits on one line.
  - **Largest accessibility size, portrait and landscape.** The heading, label and help line wrap, with no truncation, and the sheet scrolls.
  - **Help line contrast (R12).** Measured from screenshot pixels: the darkest glyph pixel against the card background, using the WCAG formula, because Accessibility Inspector can't be driven from this machine.

    | Face | `.secondary` | `.primary` |
    |---|---|---|
    | Minimal ring | — | 10.5:1 |
    | Analog sport | — | 10.9:1 |
    | Digital HUD | — | 10.7:1 |
    | Retro | 3.0:1 (fails) | 15.3:1 portrait, 14.9:1 landscape |
  - **Seen but outside this spec**, for a follow-up:
    - On Retro, the sheet's existing subtitle (`.secondary`) measures 3.05:1, and "Done" (pale accent green) is faint.
    - At the largest accessibility size, the existing header truncates ("Gauge…", "Choose…") and takes about half the medium-height sheet.
- **Still pending (device run, owner):**
  - R5: the clip stops at once when switched off.
  - R8: a 10-minute screen-recorded session with the switch off, showing no orange dot.
  - R9 and R10: rapid toggles; listening resumes, and the cooldown holds.
  - Accessibility Inspector's own contrast audit and a VoiceOver pass (R12).
- **Part B.** Built in `feat/focus-filter` after the owner's decision (Deviations). The spike stays on `spike/focus-filter` (#18, closed unmerged).
- **Simulator, Focus override (R18), 2026-10-31.** On iPhone SE, a throwaway patch forced `engineSoundsOffByFocus` and opened the sheet scrolled to Sound. It was reverted. On Retro and Digital HUD, the switch shows off and dimmed, and the line reads "Off while a Focus is on. Your choice applies again when it ends." On Retro it measures 15.3:1.
- **Still pending (device run, owner), Part B:**
  - gate (a): Settings › Focus › (a custom Focus) › Focus Filters › Add Filter lists Xpeet;
  - whether Driving and Sleep list it;
  - a Focus with "Turn off engine sounds" on: the orange dot goes and the sheet shows the switch off and disabled with the Focus line. When it ends, listening resumes with no mic prompt;
  - with Xpeet closed: switch the Focus on, open Xpeet, and nothing listens. While closed, the location arrow and the mic dot stay off;
  - whether the filter shows as a Shortcuts action (R19).

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
| R1 | `GaugeFaceTests.testSoundSectionStrings`; previews; manual: iPhone SE at medium height (done in the simulator, see Checks) |
| R2 | `SpeedometerViewModelTests.testEngineSoundsOnWhenNothingStored`, `testEngineSoundsOnWhenStoredValueIsNotBool`, `testEngineSoundsOffIsRestored` |
| R3 | `testTogglingEngineSoundsChangesNothingElse` |
| R4 | `EngineSoundViewModelTests.testDisablingEndsEventsWhileRunContinues`, `testRunWhileDisabledNeverListens`; `SpeedometerViewModelTests.testEngineSoundsOffStopsListeningWhileRunContinues` |
| R5 | `EngineSoundViewModelTests.testDisablingStopsClipAndCooldownStillApplies`; manual: device |
| R6 | `EngineSoundViewModelTests.testDisabledDoesNotRequestMic`, `testEnablingRequestsDeferredMic`; `SpeedometerViewModelTests.testEngineSoundsOffDefersMicPromptWithPreciseLocationOff` |
| R7 | `EngineSoundViewModelTests.testDisabledHidesMicChip`; `SpeedometerViewModelTests.testEngineSoundsOffHidesMicChip` |
| R8 | manual: device, screen recording |
| R9 | `EngineSoundViewModelTests.testEnablingListensAgainInSameRun`, `testRapidToggleEndsWithNoSubscribers`, `testEnablingRetriesAfterFailure`, `testEnablingWithMicDeniedShowsChipWithoutPrompt`; manual: device |
| R10 | existing `EngineSoundViewModelTests` unchanged; `testTogglingDoesNotResetCooldown`; manual: device |
| R11 | `SpeedometerViewModelTests.testChipOrderWithEngineSoundsOnAndOff` |
| R12 | `GaugeFaceTests.testSoundSectionStrings`; manual: largest size and contrast (simulator, see Checks); Accessibility Inspector and VoiceOver on the device (pending) |
| R13 | `GaugeFaceTests.testAccessibilityStrings` |
| R14 | gate (b): `Metadata.appintents` lists the filter (Deviations). Gate (a): device, pending (owner decision to build first) |
| R15 | build: `EngineSoundsFocusFilter` compiles in the app target and is in the metadata; manual: Settings shows the strings (device, pending) |
| R16 | `SpeedometerViewModelTests.testFocusOverrideStopsListeningAndLeavesTheStoredSwitch`, `testFocusOverrideHidesTheMicChip`, `testSwitchOffStaysOffWhenTheFocusEnds`, `testFocusEndingDoesNotAskForTheMicUntilTheNextRun`, `testTurningTheSwitchOnAsksForAHeldMicPrompt`; `EngineSoundViewModelTests.testHeldMicPromptWaitsForRelease`, `testReleaseWithoutHoldAsksNothing` |
| R17 | `FocusFilterOverrideTests` (value, thrown read, timed-out read); `SpeedometerViewModelTests.testNothingListensUntilTheRunsFirstFocusValue`, `testNoMicPromptUntilTheRunsFirstFocusValue`, `testEachRunWaitsForTheFocusValueAgain`; manual: device, app open and closed (pending) |
| R18 | `GaugeFaceTests.testFocusOverrideHint`; `engineSoundsOffByFocus` in the R16 tests; preview "Picker, off by a Focus"; manual: device (pending) |
| R19 | review: no `project.yml` change, and `Core/Focus/` holds no App Intents type but the filter |
| R20 | review of the older-spec notes; CLAUDE.md `Core/Focus/` line; evals re-run |
