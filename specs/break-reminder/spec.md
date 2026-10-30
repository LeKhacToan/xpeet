# Spec: Remind me to take a break on long drives

**Intent:** intent/2026-10-30-break-reminder.md  **Status:** approved

This spec adds a **break reminder**: after 2 h of driving without a rest, the status chip says "2 h driving · time for a break". It is a time-based, silent, read-only status. It is fed by the same moving/stopped readings as the trip (`specs/trip-stats/spec.md` R1) and adds no sensor, timer, permission, sound or network use.

Related specs written at the same time, referred to by path and not redefined here:
- `specs/precise-location/spec.md`: a new Unavailable reason, "Precise Location is off". It is a location status, so it ranks above the reminder (R10).
- `specs/engine-clip-toggle/spec.md`: an "Engine sounds" switch. The mic chip shows only while the switch is on, and stays last in the chip order (R10).

Changes to earlier specs (each gets a note when this ships):
- `specs/speedometer/spec.md`:
  - Out of scope "Speed-limit data, over-speed alerts, speed-based colours or sounds": a note that the break reminder is a time-based, silent status and not a speed alert (R3, R12).
  - Non-functional Privacy: another exception after the trip-stats one. The driving stretch's three times are stored on the device (R13). Positions never are.
  - Data & API, Persistence ("one `UserDefaults` key, `speedUnit` … Nothing else is stored."): a note that `trip.stretch` is stored too (R13). The trip keys (trip-stats) were never noted on this line either. `specs/engine-clip-toggle/spec.md` adds `engineSound.enabled` to the same note.
- `specs/speedometer-gauge/spec.md`:
  - **R3** ("no alerts, and no haptics or sounds tied to speed"): the same note as above.
  - **R6**: the icon table gains "Break reminder | `cup.and.saucer`" (R9).
  - States table: a new row, "Live, break due" (see User flows). `specs/precise-location/spec.md` changes the Unavailable row of the same table.
  - Out of scope "Speed-limit markers, speed-based colours, over-speed alerts": the same note as above.
- `specs/gauge-themes/spec.md`:
  - **R7** ("no alerts"): the same note as above.
  - States table: no change. It names only the location chips (weak signal, the Unavailable reason) beside the number and the gauge fill, and lists no mic chip either. The reminder changes neither the number nor the fill (R12), and the chip's content is in the ui-redesign table. `specs/precise-location/spec.md` changes the Unavailable row.
- `specs/ui-redesign/spec.md`:
  - States table: a new row, "Live, break due". The "Live, mic denied, no location status" row becomes "…, no location status and no break reminder". `specs/engine-clip-toggle/spec.md` limits the same row to "Engine sounds" on, and `specs/precise-location/spec.md` adds "Unavailable, Precise Location off". Together, in any order: "Live, mic denied, no location status and no break reminder ("Engine sounds" on)".
  - Out of scope "the AI co-pilot text": a note that the break reminder is one fixed status line and not the co-pilot bubble. The co-pilot stays out.
  - R7 (chip look and positions): no change.
- `specs/engine-sound-clip/spec.md` (also amended by `specs/engine-clip-toggle/spec.md`; the two notes combine, in either order, into the wording below):
  - **R11**: with "Engine sounds" on, the mic chip shows when there is no location status **and no break reminder** (R10).
  - User flows table, row "Mic denied or restricted" (with "Engine sounds" on): "mic chip, unless a location chip or the break reminder is showing". engine-clip-toggle adds the row "Clips off (switch)".
- `specs/trip-stats/spec.md`:
  - Non-functional Privacy: the stretch's times are also stored (R13).
  - Data & API, Persistence: a third key, `trip.stretch`, read and written by `TripStore`.
  - R7 ("New trip") and R9 (what a trip stores) stay as they are: the stretch is kept beside the trip, not in it (R6, R13).
- `specs/osm-map/spec.md`:
  - **R25**: confirming "Delete all trips" also clears the driving stretch (R7). The dialog text and the button's enable rule are unchanged (R7).
  - Non-functional Privacy ("'Delete all trips' clears both (R25)"): it also clears the driving stretch (R7).
  - R3 needs no change, because the map's chip already shows the same content. (`specs/precise-location/spec.md` amends R3's "Open Settings" bullet, not the chip.)
- `specs/speed-accuracy/spec.md` States table: the "Live (success)" row's chip, "hidden", becomes "hidden, or the break reminder when due (R8)". Nothing else changes there from this spec: nothing feeds the estimate. (`specs/precise-location/spec.md` amends speed-accuracy R1 and R22, not this table.)
- No change: `specs/speed-mascot/spec.md` (no reaction; R12 here).

## Requirements

### Drive time
- **R1** **What counts as driving.** The reminder keeps one **driving stretch** with a *drive time*. It is fed with the same readings, at the same moments, as the trip (trip-stats R1: every accepted fix and every 0.5 s tick):
  - **Live update** (with or without "Weak GPS signal"): the time since the previous Live update is added to drive time, whether the car is moving or stopped. A stop shorter than a rest (R4), such as a red light or a jam, therefore counts as driving.
  - **Moving or stopped** uses the trip's line: the shown estimate at or above 1 km/h (`TripTracker.movingThreshold`, speedometer R7).
  - **Interval cap:** an interval longer than 5 s (`TripTracker.maxInterval`, trip-stats R2) adds nothing.
  - **Not counted:** Acquiring ("--"), Unavailable for any reason (including Precise Location off, `specs/precise-location/spec.md`), and any time the screen is not running (background, locked, closed). This time is neither driving nor rest (R4, R5).

  *(unit: synthetic sequences with an injected clock)*

- **R2** **Stretch start.** An empty stretch starts at its first moving update, like a trip (trip-stats R5). Until then its drive time is 0, and stopped time before the first movement is not counted. *(unit)*

- **R3** **Speed-blind.** Speed enters only through the moving/stopped line in R1. The same timeline driven at 30 km/h and at 120 km/h gives the same drive time, shows the reminder at the same moment, and shows the same text and look. *(unit: one timeline replayed at both speeds; the outputs are equal)*

### Rest
- **R4** **Rest with the app open.**
  - A *stop* is the stopped time since the last moving update. Each stopped Live update adds the same interval to it that R1 adds to drive time. Only a moving update ends it.
  - **A gap pauses it.** Acquiring, Unavailable, the screen not running (a call, Control Center, a lock) or an interval over 5 s adds nothing to the stop and does not end it. If the first Live update after the gap is stopped, the stop carries on from where it was. This is the intent's "neither driving nor rest".
  - When the stop's measured time reaches **15 min** (`BreakTracker.restAfter`), it is a **rest**. The stretch is cleared: drive time 0, with no start and no last movement.
  - A stop that ends (a moving update) before 15 min is a short stop. Its time stays in drive time (R1), and the next stop counts from 0.
  - The stop's time is kept in memory only, not stored (R13). If the app is relaunched rather than resumed, the stop counts from 0 again, and R5's 30 min rule still applies.

  *(unit: a 14:59 stop then movement keeps the stretch; a 15:00 stop clears it; 10 min stopped, a 3 s Acquiring gap, then 5 min stopped clears it; 10 min stopped, `endRun`, `beginRun` 2 min later, then 5 min stopped clears it; 10 min stopped, one moving update, then 10 min stopped does not)*

- **R5** **Rest across a gap** (the app closed, or no reading with the app open). The check runs when `run()` starts, at the same moment as trip-stats R6, and again on every update (R1), whatever the reading. So it also fires while the app is open and stopped after a gap:
  - If the stretch's last movement was **more than 30 min** ago (`TripTracker.newTripAfter`), it is a rest and the stretch is cleared. A trip that trip-stats R6 starts anew therefore always comes with a fresh count.
  - With the app open and Live the whole time, R4's 15 min rest always comes first, so in practice this rule decides only after a gap.
  - A shorter gap adds no drive time and counts as no rest. The stretch carries on, and the gap's time counts as neither (R4 pauses the stop).
  - Positions are never compared to detect a rest (intent, Open questions).

  *(unit, injected clock: a 29 min gap keeps the drive time; a 31 min gap clears it; both on relaunch and after Acquiring/Unavailable; last movement at t0, the screen not running until t0 + 20 min, then Live and stopped every 0.5 s: still kept at t0 + 30 min, cleared within 1 s after it)*

- **R6** **"New trip" does not reset it.** "New trip" (trip-stats R7) and finishing a trip (trip-stats R8) leave the stretch untouched. A rest is about the driver, not the trip. *(unit)*

- **R7** **"Delete all trips" clears it.**
  - Confirming "Delete all trips" (osm-map R25) clears the stretch and saves the empty stretch at once. Deleting one trip (osm-map R24) leaves it untouched.
  - **Edge case, accepted:** the button is disabled when the history and the current trip are both empty (osm-map R25), but the stretch can still hold time then. For example, "New trip" drops a trip under 100 m (trip-stats R8) while R6 keeps the stretch. The R25 rule is not changed: the stretch clears itself 30 min after the last movement (R5).

  *(unit)*

### The reminder
- **R8** **When it shows.**
  - It shows when the stretch's drive time is at least **2 h** (`BreakTracker.breakAfter`) and no higher-priority chip is showing (R10).
  - It appears within 1 s of drive time reaching 2 h, and never before.
  - It goes within 1 s of a rest (R4), or when R5 clears the stretch. Drive time then starts again from 0 at the next movement.
  - After a relaunch within 30 min, a stretch that is already due shows the reminder again with the first Live update.

  *(unit: ticks every 0.5 s with an injected clock; not shown at 1:59:59.5 of drive time, shown at 2:00:00; gone at 15 min stopped)*

- **R9** **Text and icon.**
  - **Text:** "N h driving · time for a break". N is the drive time in whole hours, rounded down. "2 h driving · time for a break" shows from 2:00:00 to 2:59:59, then "3 h driving · time for a break", and so on with no upper limit.
  - **Icon:** the SF Symbol `cup.and.saucer`.
  - **Nothing escalates.** Only N changes. The colour, size, weight, icon, chip style and position are the same at every drive time and every speed. Nothing flashes or animates.

  *(unit: text and symbol for 2 h, 2 h 59 min and 3 h; the symbol name resolves with `UIImage(systemName:)`; review: no style depends on N or speed)*

- **R10** **Chip order.** One chip shows at a time, in this order. The same list is in `specs/precise-location/spec.md` R8, `specs/break-reminder/spec.md` R10 and `specs/engine-clip-toggle/spec.md` R11:
  1. **Location statuses:** "Searching for GPS…", "Weak GPS signal", "Location access is off", "Location Services is off" and "Precise Location is off" (speedometer R6, R17; speed-accuracy R20; `specs/precise-location/spec.md`).
  2. **The break reminder** (`specs/break-reminder/spec.md`).
  3. **The mic chip** (engine-sound R11), only while "Engine sounds" is on (`specs/engine-clip-toggle/spec.md`).

  A lower chip shows only when no higher one does, and shows at once when the higher one goes if it still applies. The three specs can be built in any order: each adds only its own tier, and whichever ships later keeps this order in `statusText` and `statusSymbol`.

  This spec adds tier 2:
  - While "Weak GPS signal" shows, drive time still counts, because it is Live (R1). While another location chip shows, "Precise Location is off" included, nothing is counted (R1), the stop is paused (R4), and R5 applies. If the reminder is still due when the location chip goes, it shows straight away.
  - The mic chip never hides the reminder: it ranks below it, and with "Engine sounds" off it doesn't show at all. The switch never changes drive time or the reminder.

  *(unit: `statusText` and `statusSymbol` for each combination, with "Engine sounds" on and off)*

- **R11** **Look and placement.** The reminder uses the existing status chip (ui-redesign R7) with no style of its own:
  - **Colours:** the accent status dot, the icon in the face's accent, and the text in the face's chip text colour on the chip fill. Over the map, the chip uses the opaque card (osm-map R4).
  - **Positions:** the same as every chip, on every face:
    - gauge mode, portrait: in the reserved top row, so nothing moves at standard text sizes. At accessibility sizes the text can wrap to more lines and grow the row, shifting the gauge down, as ui-redesign accepts for every chip;
    - gauge mode, landscape: at the bottom edge. The gauge gives up the chip's height while it shows, as it does for "Weak GPS signal", and "199" is never clipped (gauge-themes R14);
    - map mode: the same positions over the map (osm-map R3).
  - **Contrast:** no new colour tokens. The chip text and chip fill tokens already pass at least 4.5:1 on every face (ui-redesign R16).

  *(manual: previews using `FakeSpeedProvider` and a due `trip.stretch` seeded in the injected `UserDefaults`, with a last movement under 30 min old because R5 clears a staler one; on every face, in both orientations, in gauge and map mode, at the default and the largest text size; plus one device run on a long drive. The Simulator never reaches Live (its fixes have `speedAccuracy` −1), so a Simulator check needs the throwaway local patch that maps it to a valid value, reverted before commit, plus the same seeded stretch. unit: the existing contrast tests)*

- **R12** **Silent and hands-free.**
  - **Nothing to hear or feel:** no sound, haptic, notification, alert, sheet or VoiceOver announcement.
  - **Nothing to tap:** the chip is not a button and has no dismiss or snooze.
  - **Nothing new running:** no new permission, background mode, timer or sensor. The existing 0.5 s tick drives it.
  - **Nothing else changes:** the number, gauge, trip line, map, mascot mood (speed-mascot) and engine-sound gate (engine-sound R6) behave exactly as they would without it.

  *(review: no `UNUserNotificationCenter`, `sensoryFeedback`, `AccessibilityNotification` or audio for the reminder; unit: mood, `displayedSpeed` and the trip are equal with and without a due stretch)*

### Storage
- **R13** **What is stored.** The stretch is saved in the injected `UserDefaults` as JSON under `trip.stretch`, beside the trip keys. It holds only:
  - when the stretch started;
  - its drive time, in seconds;
  - when the car last moved.

  It holds no positions, speeds, stop counts, break history or finished stretches. A cleared stretch (R4, R5, R7) is saved empty, so nothing of it is kept. The trip's stored fields (trip-stats R9) are unchanged. *(unit: decode the stored JSON and check its keys)*

- **R14** **When it is saved.**
  - The stretch is saved together with the trip, at the same moments (trip-stats R10): at most every 10 s while running (`SpeedometerViewModel.tripSaveInterval`), when `run()` ends, on "New trip" and on a finished trip. It is also saved on "Delete all trips" (R7).
  - Closing and reopening the app within 30 min of the last movement keeps the drive time, losing at most the last 10 s.
  - A missing or unreadable `trip.stretch` gives an empty stretch, with no error shown and no crash. It never affects `trip.current` or `trip.history`, and they never affect it.

  *(unit: round trip through a `UserDefaults` suite; relaunch within 30 min; corrupt data)*

### Accessibility
- **R15** **VoiceOver and text size.**
  - **VoiceOver:** the chip is one element, as today. The dot and icon are hidden. The label reads the chip text with the hours spelled out: "2 hours driving, time for a break".
    - It is built the way `TripFormatter` speaks durations: `Measurement(value: N, unit: UnitDuration.hours)` formatted `.wide` with the injected `Locale`, followed by " driving, time for a break".
    - N is always 2 or more, so English never needs a singular form. No String Catalog or plural rules are added (the repo has none).
    - There is no announcement when it appears (R12). VoiceOver reads it when focused, like every other status.
  - **Dynamic Type:** it follows the chip's cap of `accessibility2` (osm-map R26). The text wraps and is never truncated (ui-redesign R7).
  - **Reduce Motion:** nothing about the reminder animates, with or without Reduce Motion.

  *(unit: the label strings; manual: Accessibility Inspector, largest text size in both orientations)*

### Repo
- **R16** The CLAUDE.md Architecture line for `Features/Speedometer/Trip/` gains the new types (see Data & API), and its "`TripStore` (UserDefaults, totals only)" also names the driving stretch. Then `evals/run.sh` and `scripts/check-bands.sh` are re-run (docs/ai-sdlc.md). `specs/engine-clip-toggle/spec.md` R20 may add a `Core/Focus/` line to the same section. The two edits touch different lines, so either can go first, and each re-runs the evals. *(review)*

## User flows & UI

**Long drive.** For the first 2 h, nothing changes. At 2 h of drive time the chip shows `cup.and.saucer` and "2 h driving · time for a break". It stays as it is and becomes "3 h driving · time for a break" at 3 h. A short stop still counts as driving, so the reminder can appear while I wait at a light.

**Break with the app open.** I park and the number shows 0. After 15 min stopped, the chip goes. A call, Control Center or a tunnel during the stop pauses the 15 min and does not restart it. When I drive on, the count starts from 0.

**Break with the app closed.** I lock the phone or switch apps.
- If I come back more than 30 min after the last movement, there is no chip and the count starts fresh.
- If I come back sooner, the count continues where it stopped. The closed time counts as neither driving nor rest, so a 20 min locked coffee stop does not clear the reminder.
- If I then stay stopped with the app open, the chip goes 30 min after the last movement (R5), or once the stop reaches 15 min (R4), whichever comes first.

**Tunnel, location off or Precise Location off.** The location chip replaces the reminder, in gauge and map mode, and the time is not counted. A stop in progress is paused (R4), and the 30 min rule applies (R5).

**New trip.** It has no effect on the reminder. "Delete all trips" clears the count.

| State | Chip | Drive time | Rest |
|---|---|---|---|
| **Empty** (first launch, after a rest, or under 2 h) | none, or the mic chip while "Engine sounds" is on | counts from the first movement | a 15 min stop clears it |
| **Live, break due** (success) | `cup.and.saucer` "N h driving · time for a break" | counts, moving and short stops | a 15 min stop clears it; the chip goes |
| **Live, weak signal, break due** | "Weak GPS signal" | counts | counts |
| **Live, mic denied, break due** | the reminder; the mic chip waits ("Engine sounds" on) or never shows (off) | counts | counts |
| **Acquiring** (loading: no fix, gap, tunnel) | "Searching for GPS…" | frozen | the stop is paused (R4); the 30 min rule applies (R5) |
| **Unavailable** (permission denied or restricted, services off, Precise Location off) | the location reason, and "Open Settings" where those specs say | frozen | the stop is paused; the 30 min rule applies |
| **Screen not running** (background, locked, call, Control Center) | n/a | frozen | the stop is paused; R5 check at the next `run()` |
| **Stored stretch unreadable** (error) | as Empty | starts fresh | n/a |

There is no loading state of its own, because the stored stretch is read synchronously at start.

| Mode and orientation | Where the chip is | What moves |
|---|---|---|
| Gauge, portrait | top row, centred (ui-redesign R7) | nothing at standard text sizes; the row is reserved. At accessibility sizes a wrapped chip can grow the row and shift the gauge down, as ui-redesign accepts |
| Gauge, landscape | bottom edge | the gauge shrinks by the chip's height, as for "Weak GPS signal"; "199" is never clipped; the mascot and trip line keep their rules (ui-redesign R5, trip-stats R12) |
| Map, portrait | top row over the map, opaque card (osm-map R3, R4) | nothing |
| Map, landscape | bottom edge over the map, opaque card | the overlays above it rise by the chip's height, as in frame `map-landscape-weak-signal` |

The sheets (trip sheet, gauge style) show nothing new.

**Accessibility.** See R15. The reminder is text with an icon, so it carries no colour-only signal. The chip text contrast is already tested on every face (ui-redesign R16).

## Data & API
- **Folder:** `Xpeet/Features/Speedometer/Trip/`. The stretch is fed and stored like the trip and has no ViewModel of its own. It is pure Foundation code, with no framework import and no change to `Core/`.
  - **`DrivingStretch`** (value type, `Codable`, `Equatable`): `startedAt: Date?`, `drivingTime: TimeInterval`, `lastMovementAt: Date?`. It is empty when `startedAt` is nil (R13).
  - **`BreakTracker`** (pure value type): owns a `DrivingStretch`, plus in memory the previous Live update and the current stop's measured time (kept across gaps, R4). Its API:
    - `beginRun(at:)` (R5);
    - `update(at:reading:)`, taking the same `TripReading` the trip gets (R1, R2, R4, R5);
    - `endRun(at:)`;
    - `clear()` (R7);
    - `reminderHours: Int?`, nil below 2 h (R8, R9).

    Constants: `breakAfter = 7_200` s and `restAfter = 900` s. It reuses `TripTracker.movingThreshold`, `TripTracker.maxInterval` and `TripTracker.newTripAfter`, so the trip and the stretch can never disagree on moving, gaps or the 30 min rule.
  - **`TripStore`** gains `stretchKey = "trip.stretch"`, plus `loadStretch()` and `save(_ stretch:)`. These are decoded on their own, so one bad value never resets the other keys (R14).
- **`SpeedometerViewModel`** (`@Observable @MainActor`, no new injected dependency; it uses the existing `UserDefaults` and clock):
  - It owns a `BreakTracker` (`@ObservationIgnored`) and feeds it from the same places as the trip, all synchronous:
    - `updateTrip(_:)`, reached from `handle(sample:)`, `tick()` and `becomeUnavailable`;
    - `beginRun` and `endRun` in `run()`;
    - `clear()` in `deleteAllTrips()`;
    - saving in `saveTrip()`.

    `run()` only feeds streams, as today.
  - It exposes an observed `breakReminderHours: Int?`, assigned only when it changes (at most once an hour, plus show and hide), so the 0.5 s tick does not invalidate the screen.
  - `statusText` and `statusSymbol` become: location status, else break reminder, else mic chip (R10). A new `statusAccessibilityLabel` gives R15's spoken text, formatted with the injected `Locale` as `TripFormatter` does. It is nil for the other chips, which keep reading their text.
- **`StatusChip`** (in `SpeedometerView.swift`) gains an optional accessibility label. There is no new View. Previews gain "Break due" in gauge portrait, gauge landscape and map mode.
- **Tests:**
  - `XpeetTests/BreakTrackerTests.swift` (pure helper, R1–R9);
  - `SpeedometerViewModelTests+Trip.swift` or a new `+Break` extension (R6–R8, R10, R12, R15);
  - `TripStoreTests.swift` (R13, R14).
- **Persistence:** `UserDefaults` key `trip.stretch` (JSON `Data`, dates as seconds since 1970, like `trip.current`). The existing keys are unchanged, and so is `engineSound.enabled` from `specs/engine-clip-toggle/spec.md`.
- **Offline:** fully offline.

## Non-functional
- **Performance:**
  - Constant work per update, on the existing fixes and the 0.5 s tick.
  - No extra `UserDefaults` writes beyond the trip's 10 s saves.
  - One observed property changes at most once an hour.
- **Battery:** no new sensors, timers, background work or network use.
- **Privacy:**
  - Three new values are stored on the device (R13): two times and a duration. There are no positions.
  - They are emptied by a rest and by "Delete all trips", and are included in device backups like the trip totals (trip-stats Non-functional).
  - No new permission, no new Info.plist key, no network, no analytics.
- **Localization:** new strings, in a String Catalog-friendly form (`String(localized:)`):
  - "%lld h driving · time for a break";
  - "%@ driving, time for a break" (spoken; `%@` is the hours as a `.wide` `Measurement<UnitDuration>`, such as "2 hours", R15).

  The "·" separator and the "h" abbreviation match the trip line (trip-stats R11).

## Out of scope
- A spoken or sound reminder, haptics, notifications, or a VoiceOver announcement.
- A reminder on Apple Watch, CarPlay, the Lock Screen, a Live Activity or a widget.
- Any longest-stretch or hours-without-a-break figure. The count shows only while the reminder is up, and a finished stretch is not kept.
- A "Driving since" line in the trip sheet, because it can disagree with the chip after a closed gap.
- Detecting tiredness, suggesting a place to stop, any history or count of breaks, and praise for resting.
- Comparing positions to detect a rest with the app closed.
- Dismiss, snooze, or an off switch. A switch may be revisited with `specs/engine-clip-toggle/spec.md`, the app's first switch.
- Changeable thresholds.
- A mascot reaction.
- Measuring while the screen is not running (speedometer R20).
- The AI co-pilot text, or any other advice line (ui-redesign Out of scope).

## Flagged concerns
- **Privacy, new stored data (owner):**
  - The stretch's start time, drive time and last movement time are stored on the device (R13). There are no positions, but the times can still hint at when I drive.
  - They stay on the device and in its normal backups, and are cleared by a rest or by "Delete all trips".
  - This amends the privacy wording in speedometer and trip-stats.
  - No new permission. The location usage string (osm-map R28) is left as it is. Proposed: the reminder only reuses the moving/stopped line already behind "trip totals". The owner may still want it named.
- **Driving safety (App Review 1.4.4/1.4.5, not binding):**
  - This adds one more line of text on screen while driving. It appears at most once an hour and is static, with nothing to tap and no sound (R9, R12).
  - The wording is advice. It makes no claim to detect fatigue, which matters if the app is ever distributed (App Review 1.4.1).
  - Passenger time counts as driving, and there is no off switch (accepted by the owner).
- **Spec amendments needing owner sign-off** (listed at the top):
  - the "time-based, not a speed alert" notes in speedometer Out of scope, gauge R3 and Out of scope, and gauge-themes R7;
  - gauge R6 (the icon table);
  - the States tables in gauge, ui-redesign and speed-accuracy;
  - the ui-redesign co-pilot note;
  - engine-sound R11 and its table;
  - the privacy and storage wording: speedometer Non-functional Privacy and Data & API Persistence, trip-stats Non-functional Privacy and Persistence, osm-map Non-functional Privacy;
  - osm-map R25 (what it clears; its enable rule stays, R7).
- **CLAUDE.md:** R16 changes the Architecture section, so it needs owner approval plus an eval re-run. engine-clip-toggle R20 may change another line of the same section (R16).
- **Honest limits:** the app measures only while it is open and has a reading.
  - Driving with the app closed or in a tunnel is not counted, so the reminder can come late.
  - A gap of more than 30 min counts as a rest even if I drove during it (the trip-stats R6 rule).
  - A long "Weak GPS signal" stretch hides the reminder (R10, accepted).
  - A rest needs 15 min below the trip's 1 km/h line (R4). Walking with the phone while the app is open counts as driving and ends the stop, so a break spent walking counts only if the app is closed (the 30 min rule, R5).
  - One stray moving reading while parked does the same: it ends the stop and adds drive time. An example is GPS-only Doppler drift without the iOS stationary flag, since fusion's stop detection (speed-accuracy R12) is not built yet. No new speed filter is added, because the intent allows only the trip's line.
- **A gap pauses the rest count (a spec decision, R4):**
  - A call, Control Center, a short lock or a tunnel during a stop pauses the 15 min and does not restart it, as the intent's "neither driving nor rest" reads.
  - Restarting it instead would make the reminder appear during a real break and stay up to 15 min longer. For example: 1 h 46 min of driving, then I park with the app open and pull down Control Center at minute 14. R1 has counted the stop, so the chip shows at minute 14. With a pause it goes at minute 15; with a restart it would stay until about minute 29.
  - The catch of pausing: the app cannot see a closed gap. If I drive during one and am stopped when I come back, the stops before and after it join, and can make a rest I did not take. The 30 min rule already trusts a closed gap the same way.
- **Sibling specs:** the chip order (R10) is the same list as `specs/precise-location/spec.md` R8 and `specs/engine-clip-toggle/spec.md` R11. The three can be built in any order; whichever ships later keeps the order in `statusText`. The older-spec rules they share (engine-sound R11 and its table, the ui-redesign and gauge States tables, speedometer Persistence, CLAUDE.md) are noted where each is listed under Changes to earlier specs.
- **Unverified / to be measured:**
  - No 2 h drive with the reminder yet. The timing is covered by unit tests with an injected clock, and the first long drive is the manual check (R11).
  - Long parked stops: on recorded drives replayed through the harness (speed-accuracy R22, R26), the shown estimate stays below 1 km/h for 15 min while parked. No drives are recorded yet (`specs/speed-accuracy/results.md`).
  - The Simulator never reaches Live, so it shows the reminder only with the throwaway patch and a seeded stretch (R11).
- **No security or payments impact.**

## Open questions
Carried from the intent:
- *Thresholds?* **Answered (owner, 2026-10-30):** 2 h of drive time; a 15 min stop is a rest (R4, R8).
- *What counts as driving?* **Answered (owner, 2026-10-30):** moving time plus stops shorter than a rest, so a jam still counts (R1).
- *Rest with the app closed?* **Answered (owner, 2026-10-30):** more than 30 min since the last movement, the trip-stats R6 rule (R5). Positions are not compared, so a 20 min locked coffee stop doesn't count. To have it count, I leave Xpeet open.
- *No reading with the app open (tunnel, car park, location or Precise Location off)?* **Answered (owner, 2026-10-30):** neither driving nor rest. When a reading comes back, the closed-gap rule applies (R1, R5).
- *Does "New trip" reset the count?* **Answered (owner, 2026-10-30):** no. The stretch is stored beside the trip (R6, R13).
- *The co-pilot exclusion?* **Answered (owner, 2026-10-30):** ui-redesign Out of scope gets a note that the break reminder is a status, and the co-pilot stays out (Changes to earlier specs).
- *Chip priority?* **Answered (owner, 2026-10-30):** location statuses, including "Precise Location is off", then the reminder, then the mic chip. A long "Weak GPS signal" stretch hiding the reminder is accepted (R10).
- *VoiceOver announcement?* **Answered (owner, 2026-10-30):** none. The chip is read when focused (R15).
- *Mascot?* **Answered (owner, 2026-10-30):** no reaction (R12).
- *Off switch?* **Answered (owner, 2026-10-30):** none for now. Revisit with `specs/engine-clip-toggle/spec.md` (Out of scope).
- *Out of scope list?* **Answered (owner, 2026-10-30):** as listed under Out of scope.

Raised by this spec (defaults chosen here; the owner may change them in review):
- *A gap in measuring pauses the 15 min stop and does not restart it* (R4). Proposed: accept, because the intent says such time is neither driving nor rest, and a call or Control Center should not reset the count. The catch: driving during a closed gap can join two stops into a rest. The alternative, a restart, can show the reminder during a real break and keep it up to 15 min longer (Flagged concerns).
- *Stray moving readings while parked, and walking with the app open, end a rest* (R4). Proposed: accept with no new speed filter. **Still open (to be measured):** whether parked stops stay below 1 km/h for 15 min on recorded drives (Flagged concerns, Unverified).
- *The current stop counts toward drive time while it lasts* (R1), so the reminder can appear while I am stopped. Proposed: accept. It goes at 15 min stopped anyway.
- *The spoken label spells out "hours"* (R15), as trip-stats R17 does for units. Proposed: accept.
- *The location usage string stays as it is* (Flagged concerns). Proposed: accept for the personal build.
- *The "Delete all trips" dialog text stays as it is,* although it now also clears the stretch (R7). Proposed: accept, since the stretch belongs with the trip data.
- *Where the logic lives:* `BreakTracker` beside `TripTracker`, fed by `SpeedometerViewModel` (Data & API). The plan may fold it into `TripTracker` instead, if the stored key and R6 stay as specified.
