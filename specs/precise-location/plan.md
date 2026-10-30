# Plan: Say when Precise Location is off

**Spec:** specs/precise-location/spec.md
<!-- Produced in Claude Code plan mode. Update in the same commit when implementation diverges. -->

## Context
- **Problem.** With location allowed but Precise Location off, iOS sends only rough positions. Xpeet never reads the setting, so the screen says "Searching for GPS…" for the whole drive. If iOS marks a rough fix as stationary, the screen shows 0 and the map is kilometres off.
- **Approved.** Intent `intent/2026-10-30-precise-location.md` (accepted) and spec `specs/precise-location/spec.md`, approved by the owner on 2026-10-30. The approval covers every flagged concern and every proposed default:
  - mark fixes at the source (R10);
  - drop fixes taken before Precise came back on (R6);
  - Always is handled like When In Use;
  - the two-line hint may hide the mascot on iPhone SE portrait.
- **Outcome.**
  - A fourth Unavailable reason, `.preciseOff`: the chip says "Precise Location is off", with "Open Settings" and a hint for that reason.
  - The provider marks rough fixes. The ViewModel drops them; the Debug recording still keeps them.
  - Fixes taken before Precise came back on are dropped.
  - No new permission, prompt, Info.plist key, stored data or network use.
- **Shape.** No new app source file and no new folder, so the CLAUDE.md Architecture section does not change. One new test file.
- **Sequence.** This is the first of three specs built on one history: precise-location, then `specs/break-reminder`, then `specs/engine-clip-toggle`. Step 1 turns the chip order into a single resolver with one line per tier, so the next two specs each add one line.
- **Branch.** `feat/precise-location` from `main`, one PR. break-reminder branches from this one.

## Files that change

### Modified: `Xpeet/Core/Location/`
- **`SpeedProvider.swift`**
  - `LocationAuthorization` gains `case authorizedApproximate`: allowed, with Precise Location off (R1).
  - `LocationUpdate` gains `case approximateFix(SpeedSample)` (R10).
- **`CoreLocationSpeedProvider.swift`**
  - The private `authorization(from:)` becomes a pure function: `nonisolated static func authorization(servicesEnabled:status:accuracy:) -> LocationAuthorization`. Precedence (R2):
    1. services off gives `.servicesOff`;
    2. `.notDetermined` stays;
    3. denied and restricted stay;
    4. When In Use or Always with `.reducedAccuracy` gives `.authorizedApproximate`, otherwise `.authorized`.
  - An unknown status stays `.denied`. An unknown accuracy counts as full, which is today's behaviour.
  - `nonisolated static func update(for:accuracy:) -> LocationUpdate` gives `.approximateFix` when accuracy is reduced, otherwise `.fix` (R10).
  - `publishAuthorization()` passes `manager.accuracyAuthorization` to the mapping.
  - `speedUpdates()` marks each fix that passes the duplicate check, reading `manager.accuracyAuthorization` on the main actor.
- **`FakeSpeedProvider.swift`** (`#if DEBUG`): adds `sendApproximate(_:)`.

### Modified: `Xpeet/Features/Speedometer/`
- **`SpeedometerViewModel.swift`**
  - `UnavailableReason.preciseOff`. `recordedName` stays "unavailable".
  - **Chip resolver** (step 1, no behaviour change): a private `chip` returns the first tier that applies, either the location status or the mic chip. `statusText` and `statusSymbol` both read from it.
  - `@ObservationIgnored private var preciseOffEndedAt: Date?`, set on any exit from `.unavailable(.preciseOff)` (see Deviations).
  - `handle(authorization:)`: `.authorizedApproximate` calls `becomeUnavailable(.preciseOff)`.
  - `handle(sample:)`: after recording, drops a fix whose timestamp is before `preciseOffEndedAt` (R6).
  - New `handle(approximateFix:)`: records the fix and touches nothing else (R9, R11). `run()` routes `.approximateFix` to it.
  - `locationStatusText` gains "Precise Location is off". `canOpenSettings` is also true for `.preciseOff`.
  - New `openSettingsHint`:
    - denied: "Enable Location in Settings to see your speed" (moved from the View, same key);
    - `.preciseOff`: "Turn on Precise Location under Location to see your speed";
    - otherwise nil.
- **`SpeedometerView.swift`**: `openSettings` shows `viewModel.openSettingsHint`. Adds previews "Precise off", "Precise off, landscape" and "Map mode, precise off".
- **No change**: `SpeedometerView+Map.swift`, `SpeedometerViewModel+Map.swift`, `MoodResolver`, `TripTracker`, `EngineSoundViewModel`, `Core/Recording/*` (`DriveHeader.currentFormatVersion` stays 1).

### Tests
- **New** `XpeetTests/LocationAuthorizationTests.swift` (imports CoreLocation): R1, R2, R10.
- `SpeedometerViewModelTests.swift`: a `// MARK: - specs/precise-location` section. Reuses `makeViewModel`, `TestClock`, `sample`, `waitUntil` and `SpyDriveLog`.
- `SpeedometerViewModelTests+Trip.swift` and `+Map.swift`: R6, R7 and R9 checks.
- `MascotPlacementTests.swift`: the iPhone SE trade-off.

### Other
- `scripts/pull-drives.sh`: `DEST` override, so the rough recording goes to `build/drives-precise-off/`.
- `specs/precise-location/results.md` (new, after the R15 drive).
- Older specs: notes added at ship time (step 7).
- `project.yml`, `CLAUDE.md`: unchanged. No eval re-run.

## Order of work
Each step: run `xcodegen generate` when a file is added, then `scripts/verify.sh` with the Bash sandbox off, then commit.
0. Branch. Set the spec to approved. Commit the intent, spec and this plan.
1. Chip resolver refactor. The existing chip tests pass unchanged.
2. The new reason in the ViewModel. Tests first: R3–R8 in the main, +Trip and +Map test files.
3. Rough fixes: `LocationUpdate.approximateFix`, `handle(approximateFix:)`, routing, the fake. Tests for R9–R11.
4. Provider: the pure mapping and `update(for:accuracy:)`, plus `LocationAuthorizationTests`.
5. View: `openSettingsHint`, previews, the `MascotPlacementTests` SE case.
6. Simulator check, using throwaway patches that are reverted before commit:
   - every face, gauge and map mode, both orientations;
   - AX2;
   - iPhone SE portrait;
   - "199" in landscape.
7. Older-spec notes (the pattern of commit 0cfc1ef):
   - speedometer R17, R18, the States table, Data & API;
   - speedometer-gauge: portrait layout item 3 and the States table;
   - ui-redesign R4, R17, the States table;
   - gauge-themes States table;
   - osm-map R3 and the States table;
   - speed-accuracy R1 and R22 (exception for rough fixes).
8. Review, `scripts/verify.sh`, PR. Then the device checks (R1, R3–R6) with `scripts/install-device.sh`. R15 drive: not a release gate.

## Deviations
- `preciseOffEndedAt` is set on any exit from `.preciseOff`, not only on `.authorized`. This is a superset of the spec's rule. It covers the path Precise off → denied → allowed with Precise on, where a cached rough fix would otherwise be accepted. With Precise never off it stays nil, so R12 holds.
- `scripts/pull-drives.sh` gains a `DEST` override, so the R15 recording stays out of `build/drives/` and the accuracy report. The spec does not list this file.
- **Built.**
  - All the ViewModel tests live in `XpeetTests/SpeedometerViewModelTests+PreciseLocation.swift`, which is the File-length fallback. They are not spread over the main, +Trip and +Map files, and the test names are unchanged.
  - Steps 2–5 went into one commit.
- **Simulator check (step 6), 2026-10-31.**
  - A throwaway patch forced `.reducedAccuracy`; it was reverted. Three screens were checked: iPhone SE (3rd gen) portrait on Minimal ring, iPhone 15 on Retro, and iPhone 15 in map mode.
  - Each showed the chip "Precise Location is off" with `location.slash`, `--` with an empty gauge, "Open Settings" and a two-line hint. Retro showed the `sad` mascot. On SE the mascot was hidden, as accepted. The map showed the placeholder with no marker.
  - The simulator's own Precise Location switch was not tried, so that open question is left to the device.
  - **AX2 (review follow-up).** iPhone 15 portrait on Analog sport, at `accessibility-large`. The chip wraps to two lines and the hint to three. Nothing is truncated, and the mascot still shows.
  - **Not done in the simulator.** Landscape, and the Accessibility Inspector pass. Simulator.app's window can't be driven from this machine's shell, so rotating isn't possible here. Both move to the device checks (step 8). The landscape previews build: "Precise off, landscape" and "Denied, landscape".
- **`scripts/pull-drives.sh` (review follow-up).** A default pull now skips any drive already in a `build/drives-*/` folder. Without that, the next ordinary pull would copy the Precise-off recording back into `build/drives/`, where the accuracy report would read it.
- R8 with a due break reminder and R9 "break reminder unchanged" are proven in `specs/break-reminder` (`testLocationStatusesRankAboveTheReminder`, `testRoughFixesLeaveTheStretch`). The reminder does not exist yet in this PR.

## Risks
- **Main-actor read.** `CoreLocationSpeedProvider` is `@MainActor`. The `Task` inside the `AsyncStream` builder inherits it. `manager` is main-actor isolated and read without `await`, so the compiler proves the isolation.
- **Inferred races.**
  - The launch race is closed by marking fixes at the source (R10).
  - The reverse race is closed by R6. Its cost: a parked phone may stay on "Searching…" until iOS sends a new fix.
  - A cold launch after Precise comes back on is not covered. R15 checks whether that first fix is rough.
- **iOS may relaunch Xpeet after the Precise toggle** (unverified). The return is then a cold launch, and launch arguments are lost. Record what happens on the device.
- **Simulator.** The Precise switch may not change `accuracyAuthorization`, and `speedAccuracy` is always -1. Visual checks use throwaway patches. Unit tests depend on neither.
- **File length.** `SpeedometerViewModelTests.swift` is long (755 lines). If SwiftLint complains, move the new tests to `SpeedometerViewModelTests+PreciseLocation.swift` and record it here.
- **Eval coupling.** Keep the "Weak GPS signal" literal and the zero-clamp `guard` unchanged in `SpeedometerViewModel.swift`.

## Proof
| Req | Proof |
|---|---|
| R1 | `LocationAuthorizationTests.testAllowedWithFullAccuracyIsAuthorized`, `testAllowedWithReducedAccuracyIsApproximate`; manual: device prompt with "Precise: Off" |
| R2 | `LocationAuthorizationTests.testMappingForEveryCombination`, `testNotDeterminedIgnoresAccuracy` |
| R3 | `SpeedometerViewModelTests.testFollowsPreciseLocationChangesWhileRunning`, `testNewRunPicksUpAChangeMadeInSettings`; manual: device |
| R4 | `testPreciseOffShowsItsOwnUnavailableReason`, `testPreciseOffClearsALiveReading`; manual: device, within 1 s |
| R5 | `testOpenSettingsAndHintForEachReason`; manual: the button opens Settings › Xpeet |
| R6 | `testPreciseBackOnGoesAcquiringThenLive`, `testFixTakenBeforePreciseCameBackIsDropped`, `testPreciseOffToDeniedShowsTheNewReason`, `testFixTakenBeforePreciseCameBackSetsNoPosition` (+Map) |
| R7 | `testPreciseOffShowsSadMascot`, `testEngineSoundCountsPreciseOffAsStopped`, `testMicRequestedAfterPreciseOffAnswer`, `testTripLineHiddenWhilePreciseOff` (+Trip), `testPlaceholderWithoutMarkerWhilePreciseOff` (+Map) |
| R8 | `testPreciseOffChipOutranksMicChip`; existing chip tests; the break tier in `specs/break-reminder` |
| R9 | `testRoughFixesNeverMoveTheReading`, `testRoughFixBeforeFirstAuthorizationIsIgnored`, `testRoughFixesDoNotGrowTheTrip` (+Trip), `testRoughFixesDoNotMoveTheMap` (+Map) |
| R10 | `LocationAuthorizationTests.testFixMarkedOnlyWithReducedAccuracy`; `testRoughFixesAreRecordedButNotShown` |
| R11 | `testRoughFixesAreRecordedButNotShown`; review: no diff in `Core/Recording/` |
| R12 | the existing suite unchanged; `scripts/verify.sh` |
| R13 | review: `project.yml` unchanged; no `requestTemporaryFullAccuracyAuthorization` / `NSLocationDefaultAccuracyReduced` / `NSLocationTemporaryUsageDescriptionDictionary` |
| R14 | `testPreciseLocationStrings`; `MascotPlacementTests.testIPhoneSEPreciseOffHintHidesMascot`; existing contrast tests; manual: step 6 |
| R15 | manual: recorded drive → `specs/precise-location/results.md` |

Run `scripts/verify.sh` (Bash sandbox off) after every step and paste the tail.
