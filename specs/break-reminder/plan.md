# Plan: Break reminder

**Spec:** specs/break-reminder/spec.md
<!-- Produced in Claude Code plan mode. Update in the same commit when implementation diverges. -->

## Context
- **Problem.** On long drives I lose track of how long I have been at the wheel. Xpeet already counts moving and stopped time for each trip (trip-stats R1), but nothing tells me when it is time to stop.
- **Approved.** The owner approved intent `intent/2026-10-30-break-reminder.md` (accepted) and spec `specs/break-reminder/spec.md` on 2026-10-30. That covers every flagged concern and every proposed default:
  - a gap pauses the 15 min stop and does not restart it;
  - no new speed filter;
  - the current stop counts as drive time;
  - the spoken label spells out "hours";
  - the location usage string and the "Delete all trips" text stay as they are;
  - `BreakTracker` sits beside `TripTracker`.
- **Where this sits.** This is the second of three specs on one history. `specs/precise-location` is already in the code: `UnavailableReason.preciseOff`, `LocationAuthorization.authorizedApproximate`, `handle(approximateFix:)`, and the chip resolver `chip` in `SpeedometerViewModel`. `specs/engine-clip-toggle` comes next and gates the mic tier inside `EngineSoundViewModel.chipText`.
- **Outcome.**
  - After 2 h of drive time, the existing status chip shows `cup.and.saucer` and "N h driving · time for a break".
  - It clears after a 15 min stop with the app open, or more than 30 min after the last movement.
  - The stretch is stored as three values under `trip.stretch`.
  - Nothing new runs: no sensor, timer, permission, sound or network. There is no new View or ViewModel.
- **Branch.** `feat/break-reminder`, from `feat/precise-location`. One PR, with base `feat/precise-location`.

## Files that change

### New: `Xpeet/Features/Speedometer/Trip/` (pure Foundation)
- **`DrivingStretch.swift`**: `struct DrivingStretch: Codable, Equatable` with `startedAt: Date?`, `drivingTime: TimeInterval = 0` and `lastMovementAt: Date?`. `isEmpty` is true when `startedAt == nil`.
- **`BreakTracker.swift`**: `struct BreakTracker: Equatable`, owned by `SpeedometerViewModel`.
  - **Constants.** `breakAfter = 7_200` and `restAfter = 900`. It reuses `TripTracker.movingThreshold`, `.maxInterval` and `.newTripAfter`.
  - **State.** `private(set) var stretch`. In memory only: `previous: Date?` (the previous Live update; nil after a gap) and `stop: TimeInterval` (kept across gaps, R4).
  - **`init(stretch:)`.** An inconsistent or non-finite stretch becomes empty.
  - **`update(at:reading:)`:**
    1. **R5 check.** If the last movement was more than `newTripAfter` ago, `clear()`.
    2. **Not Live.** `previous = nil`, and the stop is paused.
    3. **Live.** A moving update starts an empty stretch, or sets `lastMovementAt` and `stop = 0`. A chained interval `0 < Δ ≤ maxInterval` adds to `drivingTime`, and also to `stop` when stopped. When `stop >= restAfter`, `clear()`.
  - **`beginRun(at:)`.** `previous = nil`, then the R5 check.
  - **`endRun(at:)`.** The same as a not-measured update.
  - **`clear()`.** Empties the stretch and resets the stop.
  - **`reminderHours: Int?`.** `Int(drivingTime / 3_600)` when `drivingTime >= breakAfter`, otherwise nil.

### Modified
- **`Trip/TripStore.swift`.** `stretchKey = "trip.stretch"`, `loadStretch()` and `save(_ stretch:)`. They use the same date encoding as the trip. The stretch is decoded on its own: a failure gives an empty stretch, and the trip keys are never affected (R14).
- **`Trip/TripFormatter.swift`:**
  - `breakReminder(hours:)` gives "N h driving · time for a break" (R9).
  - `breakReminderSpoken(hours:)` gives "N hours driving, time for a break", using the same `.wide` duration style as `spokenDuration` (R15).
- **`SpeedometerViewModel.swift`:**
  - `@ObservationIgnored var breakTracker`, loaded in `init`.
  - Observed `private(set) var breakReminderHours: Int?`, assigned only on change.
  - `static let breakReminderSymbol = "cup.and.saucer"`.
  - `updateTrip(_:)` also feeds `breakTracker`, then calls `refreshBreakReminder()`. That covers fixes, ticks and `becomeUnavailable` (including `.preciseOff`).
  - `run()` calls `beginRun` and `endRun` beside the trip's, and `saveTrip()` also saves the stretch.
  - **Chip resolver.** The break tier goes inside `chip`, between the location status and the mic chip. `chip` also carries an optional spoken label, exposed as `statusAccessibilityLabel` (the reminder's spoken text; nil for other chips).
- **`SpeedometerViewModel+Map.swift`.** `deleteAllTrips()` clears the stretch before saving (R7).
- **`SpeedometerView.swift`:**
  - `StatusChip` gains `accessibilityLabel: String?`, and `statusChip` passes `viewModel.statusAccessibilityLabel`.
  - New previews seed a due stretch in every preview: an empty one by default, because the preview suite is shared per face. The seed times are `.distantPast`, which is the preview clock.
- **`CLAUDE.md`** (R16). The `Features/Speedometer/Trip/` line names `DrivingStretch` + pure `BreakTracker`, and says `TripStore` holds the trip totals and the driving stretch.

### Tests
- New `XpeetTests/BreakTrackerTests.swift` (pure): R1–R5, R7–R9.
- New `XpeetTests/SpeedometerViewModelTests+Break.swift`: R1, R6–R10, R12, R14, R15, and the precise-location cases.
- `XpeetTests/SpeedometerViewModelTests+Trip.swift`: the `drive` helper goes from private to internal, so `+Break` can reuse it. This is a visibility change only.
- `XpeetTests/TripStoreTests.swift`: R13, R14. `XpeetTests/TripFormatterTests.swift`: R9, R15.

### Earlier specs (notes at ship time, as in 0cfc1ef)
- speedometer: the Out of scope speed-alert line, Non-functional Privacy, Data & API Persistence.
- speedometer-gauge: R3, the R6 icon table, the States table, Out of scope.
- gauge-themes: R7.
- ui-redesign: the States table (new row, plus "no break reminder" on the mic row), Out of scope "the AI co-pilot text".
- engine-sound-clip: R11 and its User flows row.
- trip-stats: Privacy and Persistence.
- osm-map: R25 and Privacy.
- speed-accuracy: the States table "Live" row.

## Order of work
Each step: run `xcodegen generate` when files are added, then `scripts/verify.sh` with the Bash sandbox off, then commit.
0. Set the spec to approved. Commit the intent, the spec and this plan.
1. `DrivingStretch` + `BreakTracker`, tests first.
2. `TripStore` stretch key, tests first.
3. `TripFormatter` strings, tests first.
4. ViewModel feeding and storage. Make `drive` internal and add the `+Break` tests.
5. The break tier in `chip`, plus `statusAccessibilityLabel`. R10 tests include `.preciseOff` and rough fixes.
6. View:
   - `StatusChip` label and previews.
   - Simulator check with a throwaway patch, reverted before commit: Live, plus a seeded due stretch, in gauge and map mode.
7. CLAUDE.md line and earlier-spec notes. Then `evals/run.sh` and `scripts/check-bands.sh` with the sandbox off.
8. Review workflow, verify, PR.

## Deviations
- **Chip resolver.** The plan agent proposed `locationStatusText ?? breakReminderText ?? engineSound.chipText`. This plan follows the resolver from precise-location instead: one tier list, and the spoken label comes from the same place.
- **Simulator check (step 6), 2026-10-31.**
  - A throwaway patch mapped negative speed and speed accuracy to valid values, and was reverted. The simulator drove a 15 m/s route, and a 2 h `trip.stretch` was seeded through `simctl spawn defaults write`.
  - iPhone SE (3rd gen), Retro, portrait, gauge mode: the chip showed `cup.and.saucer` and "2 h driving · time for a break". The text wrapped to two lines in the top row and nothing moved.
  - The seeded `defaults` reach the app one launch late on this machine (a simulator prefs-cache quirk), so each seed is written, the app launched, then written and launched again.
  - **Map mode (review follow-up).** iPhone SE, Digital HUD: the chip shows on its opaque card over the map and trail, with the speed card and trip line unchanged.
  - **Landscape and largest text (R11), 2026-10-31.** On iPhone SE, a second throwaway patch forced the break tier to the top of `chip` and rotated the scene with `requestGeometryUpdate`. It was reverted. Content size was set with `simctl ui content_size`.
    - **Landscape, default size.** Retro gauge and Digital HUD map mode: the chip sits on the bottom edge, centred and on one line, clear of the gauge and the trip line.
    - **Largest accessibility size, portrait.** Analog sport: the chip wraps to three lines in the top row with nothing truncated. The face and map buttons keep their places, and the mascot shrinks to fit.
    - **Largest accessibility size, landscape.** Gauge and map mode: the chip stays on one line on the bottom edge. In map mode the face button overlaps the speed card's corner. That is the existing osm-map layout at this size and unrelated to the chip.
  - **Still pending (device run).** The Accessibility Inspector pass (R15: one element reading "2 hours driving, time for a break"), and a long drive. Simulator.app's window can't be driven from this machine's shell, so the Inspector isn't available here.
- **Branch hygiene (review follow-up).** `specs/engine-clip-toggle/spec.md` was swept into the docs commit by mistake and is removed here. It belongs to `feat/engine-clip-toggle`.
- **Proofs carried for precise-location.** precise-location R8 with a due reminder, and R9 "break reminder unchanged", are proven here: `testLocationStatusesRankAboveTheReminder` and `testRoughFixesLeaveTheStretch`.

## Risks
- **ViewModel length.** If SwiftLint objects, move the break glue to `SpeedometerViewModel+Break.swift`, as `+Map` does.
- **Observation churn.** `breakReminderHours` is assigned only on change; this is tested with `withObservationTracking`.
- **R5 timing.** The check runs at the same moments as the trip. Non-Live ticks don't feed it, so a stale stretch clears at the next Live update or at run end. Nothing visible changes, because a location chip ranks higher.
- **Boundaries.** `>=` for 15 min and 2 h; `>` for 30 min.
- **Previews.** The clock is `.distantPast`, so seeds use it too.
- **Locale.** In a non-English locale the spoken label mixes languages, which the spec accepts. Tests pin `en_US`.
- **Eval coupling.** Keep the "Weak GPS signal" literal and the zero-clamp guard in `SpeedometerViewModel.swift`.

## Proof
| Req | Proof |
|---|---|
| R1 | `BreakTrackerTests.testLiveUpdatesAddDriveTimeMovingOrStopped`, `testIntervalOverFiveSecondsAddsNothing`, `testAcquiringAndNotMeasuredAddNothing`, `testUsesTheTripThresholds`; `+Break.testDrivingFeedsTheStretch`, `testWeakSignalStillCountsDriveTime`, `testNoReadingAddsNoDriveTime`, `testRoughFixesLeaveTheStretch` |
| R2 | `BreakTrackerTests.testStretchStartsAtFirstMovement`, `testStoppedBeforeFirstMovementIsNotCounted` |
| R3 | `BreakTrackerTests.testSameTimelineAtThirtyAndOneTwentyGivesSameStretch`; `TripFormatterTests.testBreakReminderText` |
| R4 | `BreakTrackerTests.testStopOf14m59sThenMovementKeepsStretch`, `testStopOf15MinutesIsARest`, `testAcquiringGapPausesTheStop`, `testEndRunPausesTheStop`, `testMovementRestartsTheStop` |
| R5 | `BreakTrackerTests.testBeginRunAfter29MinutesKeeps`, `testBeginRunAfter31MinutesClears`, `testGapAfterNotMeasuredClearsAfter31Minutes`, `testClosedGapThenStoppedClearsJustAfterThirtyMinutes`; `+Break.testRunAfterLongBreakClearsTheStretch` |
| R6 | `+Break.testNewTripKeepsTheStretch` |
| R7 | `BreakTrackerTests.testClearEmptiesTheStretch`; `+Break.testDeleteAllTripsClearsAndSavesTheStretch`, `testDeleteOneTripKeepsTheStretch` |
| R8 | `BreakTrackerTests.testReminderAtTwoHoursNotBefore`; `+Break.testReminderAppearsAtTwoHoursOfDriveTime`, `testReminderGoesAfterFifteenMinutesStopped`, `testDueStretchShowsAgainAfterRelaunch` |
| R9 | `BreakTrackerTests.testReminderHoursRoundDown`; `TripFormatterTests.testBreakReminderText`; `+Break.testReminderTextAndSymbol` |
| R10 | `+Break.testLocationStatusesRankAboveTheReminder` (including Precise Location off), `testReminderRanksAboveTheMicChip`, `testReminderShowsWhenTheLocationChipGoes`; "Engine sounds off" in engine-clip-toggle |
| R11 | Simulator check on iPhone SE: portrait and landscape, gauge and map mode, default and largest text (Deviations). The device run is pending. Existing contrast tests |
| R12 | `+Break.testReminderChangesNothingElse`; review: no notifications, haptics or announcements |
| R13 | `TripStoreTests.testStretchStoresTimesOnly`, `testClearedStretchIsSavedEmpty` |
| R14 | `TripStoreTests.testStretchRoundTrip`, `testMissingStretchGivesEmptyStretch`, `testCorruptStretchKeepsTheTrip`, `testCorruptTripKeepsTheStretch`; `+Break.testStretchSavedWithTheTrip`, `testRelaunchWithinThirtyMinutesKeepsDriveTime` |
| R15 | `TripFormatterTests.testBreakReminderSpokenLabel`; `+Break.testStatusAccessibilityLabel`; manual: Accessibility Inspector, pending on the device |
| R16 | Review of the CLAUDE.md diff; `evals/run.sh` + `scripts/check-bands.sh` |
| Non-functional | `+Break.testTicksDoNotInvalidateTheReminder` |
