# Plan: Trip statistics

**Spec:** specs/trip-stats/spec.md
<!-- Produced in Claude Code plan mode. Update in the same commit when implementation diverges. -->

## Context
- **Problem:** the app shows only the current speed. I want distance, moving and stopped time, and average moving speed for each drive, plus a short history. Every earlier spec deferred this.
- **Approved:** intent `intent/2026-10-26-trip-stats.md` (accepted) and spec `specs/trip-stats/spec.md`. The owner approved the spec on 2026-10-26, including the flagged concerns and the default thresholds (5% approximate, 10 min lost-gap cap, 60 s before an average, 100 m minimum trip, 10 s save, hidden while Unavailable, no "New trip" confirmation).
- **Design:** Stitch frames in `specs/trip-stats/design/`. In landscape, the trip line goes right of the gauge.
- **Outcome:** a trip line on the speed screen, a trip sheet with details and the last 10 trips, and totals-only local storage. All of it built on the existing speed estimate, with no new permission or sensor.

One PR, on branch `feat/trip-stats` (it already holds the intent, spec and frames).

## Files that change

### New: `Xpeet/Features/Speedometer/Trip/`
Like `Mascot/`: no ViewModel of its own; `SpeedometerViewModel` owns the logic. Everything here except the two views is pure Foundation.
- **`Trip.swift`:** `struct Trip: Codable, Equatable`.
  - Stored fields (R9): `startedAt`, `lastUpdateAt`, `lastMovementAt` (all `Date?`); `distance` (m); `movingTime`, `stoppedTime`, `lostTime` (s).
  - Derived values (R4):
    - `averageMovingSpeed` (nil below 60 s of moving time);
    - `isApproximate` (lost time over 5% of moving + lost);
    - `isEmpty`;
    - `totalTime(now:)`.
- **`TripTracker.swift`:** a pure value type holding `current: Trip` and `history: [Trip]`.
  - `update(at:reading:)`, where `enum TripReading { case live(metersPerSecond: Double), acquiring, notMeasured }`:
    - **Live:** add the time since the previous Live update, capped at `staleInterval` (5 s, R2). The interval counts as moving or stopped by the newer update (zero clamp 1/3.6 m/s). Distance grows by the trapezoid of the two shown speeds, with a stopped speed counting as 0 (R1). The first moving update sets `startedAt` (R5).
    - **Acquiring after moving:** starts lost time, capped at 10 min per gap and closed at the next Live update (R3).
    - **notMeasured** (Unavailable, background): breaks the chain; nothing counts.
  - `beginRun(at:)` starts a new trip when the last movement was more than 30 min ago (R6). `endRun(at:)` breaks the chain.
  - `newTrip(at:)` (R7). `finish` keeps a trip only if it is at least 100 m, and keeps the history to 10 (R8).
  - Constants as named statics.
- **`TripStore.swift`:** load and save `trip.current` / `trip.history` as JSON in the injected `UserDefaults`. Unreadable data gives an empty trip and empty history, with no crash (R9, R10).
- **`TripFormatter.swift`:** pure; takes a `Locale` and a `Calendar`.
  - Line text: "12.4 km · 18 min". Distance has one decimal below 100 and none from 100 up. Times run "0 min" … "1 h 05 min". km or mi follows the unit (R11).
  - Accessibility value: "12.4 kilometres, 18 minutes moving" (R17).
  - Sheet strings (R14): "Started 08:42" or "Not started"; "Today", "Yesterday", or a weekday with date; average speed or "--".
- **`TripDisplay.swift`:** an `Equatable` snapshot of already-formatted strings for the line, the current-trip card and the history rows. The ViewModel assigns it only when it changes.
- **`TripLinePlacement.swift`:** pure geometry, the mirror of `MascotPlacement.frame(in:)` (`Xpeet/Features/Speedometer/Mascot/MascotPlacement.swift`). In landscape it returns the trailing leftover space beside the `min(w,h)` gauge, vertically centred, or nil when there is no room (R12).
- **`TripLine.swift`** (View):
  - a frosted capsule using the existing `GlassBackground` (`Faces/FaceDecor.swift:115`) with `theme.chipFill`, like `StatusChip`;
  - a trip glyph, then the text in `Theme.captionFont`, `theme.secondaryText`, with monospaced digits; a faint chevron;
  - at least 44 pt tall; `.dynamicTypeSize(...accessibility2)`;
  - `ViewThatFits`: one line, else distance and time on two lines (narrow landscape space);
  - VoiceOver as in R17;
  - `#Preview` for each face and for the two-line layout.
- **`TripSheet.swift`** (View), in the `FacePickerSheet` style (`Faces/FacePickerSheet.swift`: header with "Done", `.presentationDetents([.medium, .large])`, `.ultraThinMaterial`):
  - a header with the start time;
  - the current-trip card with the 2 × 2 grid;
  - the empty-trip hint and a disabled "New trip";
  - "Earlier trips" rows, or "No earlier trips" when empty;
  - a neutral "Approximate" tag under the day;
  - scrolls at large Dynamic Type;
  - `#Preview` for empty, running, approximate and with history (R14, R17).

### Modified
- **`Xpeet/Features/Speedometer/SpeedometerViewModel.swift`**
  - **New stored properties:**
    - `@ObservationIgnored tripTracker` and `tripStore` (built from the injected `defaults`);
    - `lastTripSave: Date?`;
    - the observed `private(set) var trip: TripDisplay`.
  - **Feeding the tracker:**
    - `handle(sample:)` (accepted path) passes `.live(shown estimate)`;
    - `tick()` passes `.live` while Live, or `.acquiring` when it falls back to Acquiring;
    - `becomeUnavailable` passes `.notMeasured`.
  - **`run()`:**
    - calls `tripTracker.beginRun(at:)` after the existing `resetFilter()`;
    - in the `defer`: `endRun` and save;
    - `tick()` saves at most every 10 s (R10).
  - **Other:** `startNewTrip()` (R7). `toggleUnit()` refreshes `trip`. `trip.line` is nil while Unavailable (R11).
  - **New init parameter:** `calendar: Calendar = .current`, so tests can pin the time zone.
- **`Xpeet/Features/Speedometer/SpeedometerView.swift`**
  - **Portrait:** the existing `VStack(topRow, gauge)` gains `TripLine` under the gauge, above the `openSettings` inset. The gauge stays a `GeometryReader`, so it only gives up height.
  - **Landscape:** the gauge's `GeometryReader` gets a second overlay at `TripLinePlacement.frame(in:)`, next to the existing `mascot(in:)`. The status chip stays alone in the bottom inset.
  - **Sheet:** `.sheet(isPresented: $showsTrip) { TripSheet(display: viewModel.trip, onNewTrip: viewModel.startNewTrip) }`.
  - **Previews:** existing previews gain a running trip; new previews for landscape with a trip and for the trip sheet.
- **`project.yml`:** the location usage string gains "and trip totals" (owner-approved after review). No new key or permission. Run `xcodegen generate` for the new files.
- **`CLAUDE.md` Architecture:** one line under Features: `Features/Speedometer/Trip/` holds the trip stats. It lists `Trip`, the pure `TripTracker`/`TripFormatter`/`TripLinePlacement` (owned by `SpeedometerViewModel`), `TripStore`, and `TripLine`/`TripSheet`, and has no ViewModel (R20).
- **Supersede notes:**
  - `specs/speedometer/spec.md`: R1, Out of scope "trip statistics", the privacy line.
  - `specs/ui-redesign/spec.md`: R7, and Out of scope "trip distance".

### Tests (new files)
- `XpeetTests/TripTrackerTests.swift` (R1–R8, R18 synthetic, R19).
- `XpeetTests/TripStoreTests.swift` (R9–R10).
- `XpeetTests/TripFormatterTests.swift` (R11, R14, R17 strings), with a fixed `Locale(identifier: "en_US")` / `"fr_FR"` and a UTC `Calendar`.
- `XpeetTests/TripLinePlacementTests.swift` (R12 geometry).
- `XpeetTests/SpeedometerViewModelTests+Trip.swift`: an extension of `SpeedometerViewModelTests` that reuses its internal helpers (`makeViewModel`, `TestClock`, `sample`, `waitUntil`), as `+Accuracy.swift` does. `makeViewModel` gains `defaults` reuse for the persistence tests.
- `XpeetTests/Accuracy/AccuracyReportTests.swift`: `testTripDistanceAgainstPositions` replays each recorded drive through `DriveReplay` and compares the trip distance with the chord-sum distance from positions. It skips without drives (R18, real-drive part).

## Order of work
Each step: `xcodegen generate` when files are added, then `scripts/verify.sh` (Bash sandbox off), then a commit.
0. Spec `Status: approved`; commit it with this plan as `specs/trip-stats/plan.md`.
1. `Trip` + `TripTracker` + `TripTrackerTests`, tests written first.
2. `TripStore` + tests.
3. `TripFormatter` + `TripDisplay` + tests.
4. ViewModel integration and `SpeedometerViewModelTests+Trip.swift`:
   - feeding the tracker;
   - `beginRun` / `endRun`;
   - saving;
   - `startNewTrip`;
   - the Unavailable rule;
   - the unit switch.
5. `TripLinePlacement` + tests; `TripLine` and `TripSheet` with previews; wiring in `SpeedometerView`.
   - Manual: each face, portrait and landscape, the largest Dynamic Type, Reduce Motion, VoiceOver.
   - Compare with the frames in `specs/trip-stats/design/`.
6. `testTripDistanceAgainstPositions` in the accuracy tests.
7. The CLAUDE.md line, the supersede notes, `scripts/verify.sh`, `evals/run.sh` + `scripts/check-bands.sh`. Then the `reviewer` and `verifier` agents, and the PR. Install on the phone with `scripts/install-device.sh` for a test drive.

## Deviations
- **R1 distance:** an interval that ends stopped still adds the trapezoid down to 0, because braking to a stop covers ground. The spec's R1 text is clarified to match.
- **API names:** `TripTracker.newTrip()` takes no time. `TripTracker.endRun(at:)` is the same as feeding `.notMeasured`.
- **ViewModel length:** the trip glue stays in `SpeedometerViewModel.swift` (now about 505 lines), because an extension in another file can't reach the private stored properties. This needs SwiftLint to confirm when it is installed.
- **Trip glyph:** the SF Symbol `point.topleft.down.curvedto.point.bottomright.up`, a route. `road.lanes` was unreadable at caption size.
- **R18 on real drives:** `AccuracyReport.tripDistance` rebuilds the trip from the recorded `shown` lines, which are exactly the readings the ViewModel fed the tracker, instead of replaying through a ViewModel. `positionDistance` restarts its chord chain after gaps, as the trip does.
- **Test locale:** the ViewModel tests run in `fr_FR` (the existing helper's locale), so their expected lines use a decimal comma. The formatter tests cover `en_GB` and `fr_FR`.
- **Visual check:** portrait, landscape (Minimal ring and Retro) and both sheet states were rendered with a temporary `ImageRenderer` test, not committed, and compared with the Stitch frames. `ImageRenderer` leaves a `ScrollView` blank, so the sheet was rendered once with a `VStack` in its place, which was then restored.

- **Review fixes (reviewer agent, 2026-10-26):**
  - **`TripLine`:** now picks the widest of three layouts that fits: one line; two lines with glyphs; two lines without glyphs that shrink (`minimumScaleFactor` 0.5). Nothing truncates at 118 pt (iPhone SE landscape) or 153 pt (15 Pro), up to AX2. The placement tests use the real container sizes (635×367, 702×364).
  - **Sheet history rows:** values stay on one line beside the day when they fit, and stack under it otherwise. No row truncates or breaks inside a word, up to AX3.
  - **VoiceOver:** the card values are spoken with units in full, through new `TripDisplay` fields (`distanceSpoken`, … `averageSpeedSpoken`).
  - **Approximate note:** it now reads "Approximate · GPS was lost for part of this trip".
  - **Total time:** while the reading is not Live, `tick()` still refreshes the trip, so total time keeps counting with the sheet open.
  - **R18 measurement:** `AccuracyReport.tripAndPositionDistance` compares the trip and the positions over the same gap-free stretches, so the 5 s held speed at a tunnel mouth no longer biases it.
  - **Location usage string** (owner-approved): it now mentions trip totals, in `project.yml`.
  - **Save on a new trip:** `run()` saves right after `beginRun`, so a trip archived by the 30-minute rule is stored at once (verifier).
  - **Shared thresholds:** `TripTrackerTests.testThresholdsMatchTheSpeedometer` pins `movingThreshold` and `maxInterval` to the ViewModel's zero clamp and stale interval.

## Risks
- **The ViewModel keeps growing:** it is about 450 lines, and SwiftLint `--strict` may flag `type_body_length` / `file_length` (SwiftLint isn't installed locally). Keep the trip glue to a few calls into `TripTracker`. If it passes the limits, move the trip methods into an extension file, `SpeedometerViewModel+Trip.swift` (stored properties stay in the class), and record that under Deviations.
- **Observation churn:** ticks run at 2 Hz. `trip` is assigned only when a formatted string changes, so the screen updates at most when the 0.1 km or minute values change.
- **Time zone and locale in tests:** "Today/Yesterday" and "Started 08:42" depend on the calendar. The formatter takes a `Calendar` and `Locale`, the ViewModel injects them, and tests pin UTC with `en_US`.
- **Landscape room:** on the smallest phones the trailing space beside the gauge is about 150 pt. `ViewThatFits` falls back to two lines. If even that doesn't fit, `TripLinePlacement` returns nil and the line hides, and the gauge never shrinks for it. Check on the iPhone SE simulator; if it hides, record it as a deviation.
- **Classifying intervals:** each interval counts as moving or stopped by the newer update, so at 2 Hz a stop-and-go edge mis-assigns at most 0.5 s. Distance still uses the trapezoid, so it is unaffected.
- **Persistence while recording:** `UserDefaults` writes happen on the main actor every 10 s, which is negligible. The drive recorder is unchanged.
- **Eval coupling:** the literals `guard metersPerSecond >= Self.zeroClampMetersPerSecond else` and "Weak GPS signal" must stay unchanged.

## Proof
| Req | Proof |
|---|---|
| R1 | `TripTrackerTests.testMovingAddsTrapezoidDistanceAndMovingTime`, `testStoppedAddsStoppedTimeOnly`, `testWeakSignalStillCounts` |
| R2 | `TripTrackerTests.testLongIntervalIsNotMeasured` |
| R3 | `TripTrackerTests.testAcquiringAfterMovingIsLost`, `testLostGapIsCappedAtTenMinutes`, `testApproximateAboveFivePercent`, `testAcquiringAtStartIsNotLost` |
| R4 | `TripTrackerTests.testAverageNeedsSixtySeconds`, `testTotalTimeIncludesUnmeasured` |
| R5 | `TripTrackerTests.testTripStartsAtFirstMovement`, `testEmptyTripHasNoStart` |
| R6 | `TripTrackerTests.testBeginRunAfterThirtyMinutesStartsNewTrip`, `testShortBreakContinues`; `SpeedometerViewModelTests.testRunAfterLongBreakArchivesTrip` |
| R7 | `TripTrackerTests.testNewTripArchivesCurrent`; `SpeedometerViewModelTests.testStartNewTrip` |
| R8 | `TripTrackerTests.testShortTripIsDropped`, `testHistoryKeepsTenNewest` |
| R9 | `TripStoreTests.testStoresTotalsOnly` (decoded JSON keys), `testRoundTrip` |
| R10 | `TripStoreTests.testCorruptDataGivesEmptyTrip`, `testEmptyStoreGivesEmptyTrip`; `SpeedometerViewModelTests.testSavesWhileDrivingAndOnRunEnd` |
| R11 | `TripFormatterTests.testLineText`, `testEmptyLine`, `testDistanceUsesLocaleDecimalSeparator`; `SpeedometerViewModelTests.testDrivingGrowsTheTripLine`, `testWeakSignalGapStillCounts`, `testTripLineHiddenWhileUnavailable`, `testUnitSwitchConvertsTripLine` |
| R12 | `TripLinePlacementTests.testLandscapeTrailingFrame`, `testPortraitReturnsNil`, `testNoRoomReturnsNil`; renders compared with the frames; existing contrast tests for `secondaryText` |
| R13 | manual: tap opens the sheet, hit area ≥ 44 pt |
| R14 | `TripFormatterTests.testSheetStrings`, `testDisplayOfTracker`; renders of the sheet, running and after "New trip" |
| R15 | manual: values update with the sheet open |
| R16 | review: no max/peak strings or ranking; `TripStoreTests.testStoresTotalsOnly` |
| R17 | `TripFormatterTests.testAccessibilityValue`; manual: Accessibility Inspector |
| R18 | `TripTrackerTests.testConstantSpeedDistanceWithinHalfPercent`; `AccuracyReportTests.testTripDistanceMatchesPositionsOnStraightDrive`; `testTripDistanceAgainstPositions` on `build/drives/` (skips until drives are recorded) |
| R19 | `TripTrackerTests.testMovingPlusStoppedEqualsLiveTime` |
| R20 | review CLAUDE.md; `evals/run.sh` + `scripts/check-bands.sh` |

Run `scripts/verify.sh` (sandbox off) after every step and paste the tail.
