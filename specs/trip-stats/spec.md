# Spec: Trip statistics

**Intent:** intent/2026-10-26-trip-stats.md  **Status:** approved

This spec adds a running trip — distance, moving and stopped time, average moving speed — to the speed screen, a trip sheet with details and the last 10 trips, and local storage of trip totals. It builds on the speed estimate from `specs/speed-accuracy/spec.md`; no new sensor, permission or network use.

Design: Stitch project `2676886462094675705` ("Xpeet Anime Speedometer", design system "Nocturne Precision"), frames saved in `specs/trip-stats/design/`. Where a frame and this spec differ, this spec wins.

| Frame | File | Stitch screen |
|---|---|---|
| Portrait, trip line under the gauge | `portrait-trip-line.jpg` | `25e56725f1184a5fbe872019cf0ed8c0` |
| Landscape, trip line right of the gauge, weak-signal chip at the bottom | `landscape-trip-line.jpg` | `370ce36f7bc944dea95c46023a7a4b57` |
| Trip sheet, running trip with history (one approximate) | `trip-sheet.jpg` | `b52ffad748cd48cca09eb95941835b8b` |
| Trip sheet, empty trip, no history | `trip-sheet-empty.jpg` | `5a3958bde9a84452a8edf90bc4fa83b0` |

Known differences, where the spec wins:
- **Fonts:** the trip line in the portrait frame renders in a serif fallback. The app uses the theme's caption font (R12).
- **Faces:** the frames show only the Minimal ring face. Other faces use their own theme tokens (R12).
- **Status chip:** the portrait frame has an empty top row. In the app, the status chip still appears there when there is a status (ui-redesign R7).
- **Device chrome:** the frames' Dynamic Island and phone mock-up are not part of the design.

Changes to earlier specs (each gets a note when this ships):
- `specs/speedometer/spec.md`:
  - **R1** amended: a second modal sheet (the trip sheet) is allowed, besides the face picker.
  - Out of scope "trip statistics (max, average, distance, time)": in scope now, **except max/top speed**, which stays out.
  - Non-functional "location … is never stored": trip **totals** and start/end times are stored; positions never are.
- `specs/ui-redesign/spec.md`: R7 (chrome layout) gains the trip line (R11–R12 here). The gauge, mascot, status chip and face button rules are otherwise unchanged; Out of scope "trip distance, peak or top speed" becomes "peak or top speed".

## Requirements

### Measuring
- **R1** **What is measured.** While the speed screen is running (`run()`), each time the shown reading updates — every accepted fix and every tick — the time since the previous update is added to the current trip:
  - **Moving:** the shown estimate is at or above the zero clamp (1 km/h, speedometer R7). The time is added to *moving time*, and distance grows by the trapezoid of the shown estimate (in m/s) over that time.
  - **Stopped:** the reading shows 0 (below the clamp, or the stationary flag). The time is added to *stopped time*. Distance grows only by the trapezoid down to 0 when the car was moving at the previous update (braking to a stop still covers ground). *(Clarified in build.)*
  - **Weak signal / gap:** while the state is still Live (with "Weak GPS signal"), the shown estimate counts exactly as above (intent Decisions).
  - **Not measured:** Acquiring, Unavailable, and any time the screen is not running (app in background, phone locked). Nothing is added.

  "Shown estimate" is the unrounded estimate behind the number (`SpeedEstimator.shown`), not the rounded integer. *(unit: synthetic sequences)*

- **R2** **Interval cap.** One update adds at most `staleInterval` (5 s) of time. A longer interval between two Live updates is treated as not measured, so a stall can never inflate distance or time. *(unit)*

- **R3** **Lost time and "approximate".**
  - When the state leaves Live for Acquiring while the trip was moving, the time until the next Live update (capped at 10 min per gap) is *lost time*.
  - A trip is **approximate** when lost time is more than 5% of (moving time + lost time). Both 5% and 10 min are named constants.

  *(unit)*

- **R4** **Derived values.**
  - *Average moving speed* = distance / moving time; shown only once moving time is at least 60 s, otherwise "--".
  - *Total time* = time from the trip's start to now (or to its last update, for a finished trip). It includes time not measured.
  - *Measured time* = moving + stopped time.

  *(unit)*

- **R5** **Trip start.** A trip starts — its start time is set — at the first moving update after it was created. Until then it is *empty*: distance 0, all times 0, no start time. *(unit)*

### Trip boundaries
- **R6** **New trip on return.** When `run()` starts and the current trip's last movement was more than 30 min ago (a named constant, measured with the injected clock), the current trip is finished (R8) and a new empty trip begins. A shorter break continues the same trip. *(unit, injected clock)*

- **R7** **New trip by hand.** "New trip" in the trip sheet finishes the current trip (R8) and begins a new empty one at once. There is no confirmation: nothing is lost, the trip moves to history. *(unit)*

- **R8** **Finishing a trip.** A finished trip goes to the front of the history if its distance is at least 100 m (a named constant); a shorter one is dropped. The history keeps the 10 newest trips (a named constant); older ones are deleted. *(unit)*

### Storage
- **R9** **What is stored.** The current trip and the history are saved in the injected `UserDefaults`, as JSON, under `trip.current` and `trip.history`. Each trip stores only: **Amended** by `specs/osm-map/spec.md` R19-R20: each trip also stores an `id`, and its route is stored in a separate file.
  - start time, last-update time and last-movement time;
  - distance (m), moving time, stopped time and lost time (s);
  - nothing else — no coordinates, course, addresses or speeds over time.

  *(unit: decode the stored JSON and check its keys; review)*

- **R10** **When it is saved.** The current trip is saved at most every 10 s while running (a named constant), and always when `run()` ends, on "New trip", and when a trip is finished. A stored value that cannot be decoded is ignored and replaced by an empty trip and empty history; the app never crashes on it. *(unit: round trip through a `UserDefaults` suite; corrupt data)*

### Speed screen
- **R11** **Trip line.** The speed screen shows one line: the current trip's distance and moving time, e.g. "12.4 km · 18 min".
  - **Distance:** in km when the unit is km/h, in miles when it is mph. One decimal below 100, none from 100 up (e.g. "8.0 km", "142 km"). Switching unit converts at once.
  - **Moving time:** "0 min" … "59 min", then "1 h 05 min".
  - **Empty trip:** "0.0 km · 0 min".
  - It is shown in every state except Unavailable (location off): while Acquiring it shows the trip so far, unchanged.

  *(unit: formatting via the ViewModel's text; manual)*

- **R12** **Placement and look.**
  - Portrait: below the gauge, centred, above "Open Settings" when that shows.
  - Landscape: to the right of the gauge, vertically centred on it, mirroring the mascot on the left (intent Decisions, changed after the Stitch design). The status chip stays alone at the bottom edge.
  - The gauge may get smaller to make room, but "199" is never truncated or clipped in any orientation, on any face (speedometer R3, gauge-themes R14). The mascot keeps its placement rule (speed-mascot R12).
  - Look (frames `portrait-trip-line`, `landscape-trip-line`):
    - a quiet frosted-glass capsule (the same glass as the status chip), at least 44 pt tall;
    - a small trip glyph before the text and a faint chevron after it;
    - text in the theme's caption font and **secondary text** colour, with tabular digits, smaller than the unit pill;
    - at least 4.5:1 contrast on every face (already tested for that token, ui-redesign R16).
  - Dynamic Type follows the system up to `accessibility2`, like the unit pill, so it never pushes the gauge below the "199" rule.
  - No colour or style changes with speed, distance or average speed.

  *(manual: every face, both orientations, largest size; unit: existing contrast tests)*

- **R13** **Tapping the line** opens the trip sheet. The hit area is at least 44 × 44 pt. Nothing else on the main screen changes; there is no trip control on the main screen besides the line. *(manual)*

### Trip sheet
- **R14** **Contents** (frames `trip-sheet`, `trip-sheet-empty`). A modal sheet titled "Trip", with "Done", in the face picker's glass style (ui-redesign R18): **Amended** by `specs/osm-map/spec.md` R22-R25: earlier trips open a route view and can be deleted, one by one or all at once.
  - **Header:** a start time under the title ("Started 08:42", or "Not started" for an empty trip).
  - **Current trip card:** a "Current distance" label over the large distance, then a 2 × 2 grid: moving time, stopped time, total time, and average moving speed (R4) in the selected speed unit.
  - **Approximate:** when R3 applies, a neutral "Approximate" note with a short reason ("GPS was lost for part of this trip"). It is never red.
  - **Empty trip:** under the card, the hint "The trip starts when the car moves.", and "New trip" disabled.
  - **"New trip"** button (R7).
  - **History:** "Earlier trips", the last 10 finished trips, newest first.
    - Each row has its day and start time on the left ("Today", "Yesterday", a weekday and date), and distance · moving time · average speed on one line on the right.
    - "Approximate" sits as a small neutral tag under the day, so the values never wrap.
    - There is no count badge.
    - Empty history shows a quiet panel: "No earlier trips".
  - All values use the current unit and the device locale.

  *(manual: frames for empty, running, approximate, with history; unit: the ViewModel exposes the values)*

- **R15** **Live while open.** The current-trip values keep updating while the sheet is open. *(manual)*

- **R16** **No top speed, no ranking.** Neither the line nor the sheet shows a maximum or peak speed, records, streaks, rankings, badges or praise; history is ordered by time only. *(review)*

### Accessibility
- **R17** VoiceOver:
  - The line is one element: label "Trip", value e.g. "12.4 kilometres, 18 minutes moving", hint "Double-tap for trip details".
  - In the sheet, each value has a spoken label ("Distance", "Moving time", …), units are spoken in full, and each history row is one element.
  - The sheet follows Dynamic Type at all sizes and scrolls rather than truncating.

  *(manual: Accessibility Inspector; unit: the label strings)*

### Accuracy
- **R18** **Distance accuracy.** On a synthetic straight drive at constant speed, the trip distance equals speed × moving time within 0.5%. On recorded drives of at least 5 km (specs/speed-accuracy R22, `build/drives/`), the trip distance from replaying the drive (speed-accuracy R26) is within **2%** of the distance from positions over the same stretch (chord sum, R29 there). *(unit: synthetic; manual analysis on recorded drives, added to `specs/speed-accuracy/results.md`)*

- **R19** **Time consistency.** Moving + stopped time equals the time spent Live while running, within 1 s, over any test sequence. *(unit)*

### Repo
- **R20** CLAUDE.md Architecture gains one line for the trip code (see Data & API). Then `evals/run.sh` and `scripts/check-bands.sh` are re-run (docs/ai-sdlc.md). *(review)*

## User flows & UI

**Driving.** The line under the gauge counts up: distance and moving time. Stops at lights add to stopped time, not to the line. A tunnel that drops to "--" stops the counting; if it lasted long enough, the trip is marked approximate in the sheet.

**Back after a break.** Open the app within 30 min: the same trip continues. After more than 30 min without movement: the old trip is in history, and the line reads "0.0 km · 0 min" until the car moves.

**Checking the trip.** Tap the line → the trip sheet. "New trip" archives the current one; "Done" closes the sheet.

| State | Trip line | Trip sheet |
|---|---|---|
| **Empty** (new trip, not moved yet) | "0.0 km · 0 min" | current trip "Not started", average "--"; history or "No earlier trips" |
| **Running** (Live, moving or stopped) | live distance · moving time | live values |
| **Acquiring** (no fix / gap ran out) | the trip so far, frozen | the trip so far; "Approximate" if R3 applies |
| **Unavailable** (location off) | hidden | not reachable: the line is its only entry (Out of scope: history without location) |
| **Stored data unreadable** (error) | empty trip (R10) | empty history; no error shown |

There is no loading state: storage is read synchronously at start.

**Accessibility.** See R17. Reduce Motion: the line changes without animation.

## Data & API
- **Folder:** `Xpeet/Features/Speedometer/Trip/`, like `Mascot/` — no ViewModel of its own; `SpeedometerViewModel` owns the logic.
  - `Trip` (value type, `Codable`, `Equatable`): the stored fields of R9, plus derived values (R4).
  - `TripTracker` (pure value type, Foundation only): the current trip and the history; `update(at:shownMetersPerSecond:isLive:)`, `beginRun(at:)` (R6), `newTrip(at:)` (R7), and the R1–R5, R8 rules. All constants named here.
  - `TripStore`: reads and writes `trip.current` / `trip.history` in the injected `UserDefaults` (R9–R10).
  - `TripLine` (View) and `TripSheet` (View), each with a `#Preview`.
- **`SpeedometerViewModel`:**
  - owns a `TripTracker` (`@ObservationIgnored`) and feeds it from the same places it updates the shown speed (`handle(sample:)`, `tick()`, `handleLocationUnavailable()`), and calls `beginRun` / save from `run()`;
  - exposes observed, already-formatted outputs: `tripLineText`, `tripLineAccessibilityValue`, and a `TripDetails` snapshot for the sheet (current trip + history in the current unit). They are assigned only when their text changes, so the screen is not invalidated on every tick;
  - `startNewTrip()` for the sheet's button.
- **Formatting:** `Measurement<UnitLength>` / `Measurement<UnitSpeed>` with the injected `Locale`; times via `Duration` formatting or explicit "h"/"min" strings in a String Catalog-friendly form.
- **Persistence:** `UserDefaults` keys `trip.current`, `trip.history` (JSON `Data`). Existing keys (`speedUnit`, `gaugeFace`) are unchanged. **Amended** by `specs/break-reminder/spec.md` R13: a third key, `trip.stretch`, holds the driving stretch and is read and written by `TripStore`.
- **Offline:** fully offline.

## Non-functional
- **Performance:** the tracker does constant work per update (2 Hz ticks plus fixes, 10 Hz with fusion later); `UserDefaults` writes at most every 10 s (R10).
- **Battery:** no extra sensors or timers; it reuses the existing tick.
- **Privacy:** only trip totals and times are stored locally (R9). No location data, no network, no analytics. App data is included in the user's device backups like the existing settings. **Exception** (`specs/break-reminder/spec.md` R13): the driving stretch's times are also stored; positions never are.
- **Localization:** new strings: "Trip", "Done", "New trip", "Current distance", "Earlier trips", "The trip starts when the car moves.", "Today", "Yesterday", "Distance", "Moving time", "Stopped time", "Total time", "Average speed", "Started %@", "Not started", "Approximate", "GPS was lost for part of this trip", "No earlier trips", "Double-tap for trip details", and the "h"/"min" time formats.

## Out of scope
- Top, peak or maximum speed; records, streaks, rankings, achievements (R16).
- Showing the trip sheet or history while location is off.
- Exporting or sharing trips; ~~deleting single history entries~~ (now in `specs/osm-map/spec.md` R24).
- Fuel or cost estimates; odometer calibration against the car.
- ~~Route, map or position history~~ (now in `specs/osm-map/spec.md`).
- Background measurement, Live Activity, widgets, CarPlay.
- Mascot reactions to trips (intent Decisions).

## Flagged concerns
- **Privacy, new stored data (owner):** trip start/end times, distances and durations are now stored on the device (R9), where `specs/speedometer/spec.md` said location is never stored. No positions are stored, but times and distances can still hint at routines (e.g. a daily commute length). They stay on the device and in its normal backups. No new permission. The owner approved rewording the existing location usage string to "Xpeet uses your location only to show your current speed and trip totals. It never leaves your device." (2026-10-27, after review).
- **Driving safety (App Review 1.4.4/1.4.5, not binding):** the line is read-only; the sheet is optional and opening it while driving is possible, as with the face picker. No speed-based reward, top speed or alert (R16). Average speed is plain information.
- **Spec amendments:** speedometer R1 (second sheet) and its privacy wording; ui-redesign R7 layout. Both need owner sign-off.
- **CLAUDE.md and evals:** R20 changes the Architecture section → owner approval plus an eval re-run.
- **Accuracy depends on speed-accuracy:** distance is the integral of the shown estimate. Until fusion ships, it is the GPS-only estimate. R18's real-drive check needs recorded drives, which don't exist yet (speed-accuracy results.md is pending).

## Open questions
Carried from the intent (all answered by the owner, 2026-10-26):
- *Top speed?* **Answered:** left out (R16).
- *When does a trip end on its own?* **Answered:** on opening the app after 30 min with no movement, or "New trip" (R6, R7).
- *Distance during a GPS gap?* **Answered:** counts while "Weak GPS signal" is shown; nothing once "--"; "approximate" past a threshold (R1, R3).
- *History size and place?* **Answered:** last 10 trips, totals only, in the trip sheet (R8, R14).
- *Landscape placement?* **Answered:** visible, at the bottom edge with the status chip; the gauge keeps the "199" rule (R12).
- *Mascot reacts to trips?* **Answered:** no (Out of scope).
- *Export, fuel, odometer calibration, Live Activity, CarPlay?* **Deferred** (Out of scope).

Raised by this spec (defaults chosen here, owner may change in review):
- *Thresholds:* 5% lost share and 10 min lost-gap cap (R3); 60 s before showing an average (R4); 100 m minimum to keep a trip (R8); 10 s save interval (R10).
- *Unavailable state:* the line and sheet are hidden while location is off, so history can't be browsed then. Proposed: accept for now (Out of scope).
- *"New trip" confirmation:* none, because the trip is archived, not deleted (R7).
