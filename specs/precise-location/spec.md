# Spec: Say when Precise Location is off

**Intent:** intent/2026-10-30-precise-location.md  **Status:** approved

This spec makes the speed screen say **"Precise Location is off"** when location is allowed but iOS gives Xpeet only approximate positions. Today that case looks like a tunnel ("Searching for GPS…") for the whole drive. It becomes a fourth Unavailable reason, with "Open Settings" and a hint line. The rough fixes iOS sends in that mode are never used. No new permission, prompt, Info.plist key, stored data or network use.

Research: the researcher agent's findings from 2026-10-30 are cited inline as "(research)" and summarised under Data & API and Flagged concerns.

Related specs written at the same time, referred to by path and not redefined here:
- `specs/break-reminder/spec.md`: the "2 h driving · time for a break" chip. Its R1 already leaves Precise-off time uncounted, and its R10 already ranks this status above the reminder.
- `specs/engine-clip-toggle/spec.md`: an "Engine sounds" switch. The mic chip shows only while the switch is on (its R7), and it stays last in the chip order (its R11; R8 here).

Changes to earlier specs (each gets a note when this ships):
- `specs/speedometer/spec.md`:
  - **R17**: a fourth reason and a third message, "Precise Location is off", with "Open Settings" and its own hint (R4, R5). Today only the denied case has the button. The States table's Unavailable row gains this reason.
  - **R18**: the screen also recovers with no restart when Precise Location comes back on (R6).
  - Data & API: the `SpeedProvider` authorization values gain *authorized, approximate* (R1). `CoreLocationSpeedProvider`'s manager also reads the accuracy setting.
- `specs/speedometer-gauge/spec.md`: the States table and the portrait layout show "Open Settings" when denied **or when Precise Location is off**. R6 does not change: this reason keeps the Unavailable icon, `location.slash`.
- `specs/ui-redesign/spec.md`:
  - **R4**: `sad` also shows while Precise Location is off.
  - **R17**: "Open Settings" is no longer denied-only. The hint line depends on the reason (R5 here), and the new hint may wrap to two lines.
  - States table: a new row, "Unavailable, Precise Location off": chip "Precise Location is off", `--`, `sad`, and Open Settings with its own hint.
- `specs/gauge-themes/spec.md`: the States table's Unavailable row shows "Open Settings" when denied **or when Precise Location is off**.
- `specs/osm-map/spec.md`: **R3** and the States table show "Open Settings" also when Precise Location is off. R5 and R9 do not change, because Unavailable already gives the placeholder and no marker.
- `specs/speed-accuracy/spec.md`. The intent proposed no change here. These two are added to close a launch race (Flagged concerns):
  - **R1**: with each fix, the provider also passes on whether Precise Location was on (R10).
  - **R22**: an exception to "every field in R1". Rough fixes are written as ordinary fix lines, without the Precise Location mark, so the recording format and `DriveHeader.formatVersion` stay the same (R11).
  - R13 does not change. (`specs/break-reminder/spec.md` amends the speed-accuracy States table, not these rules.)
- No change:
  - `specs/trip-stats/spec.md` R1 and R11, where "Unavailable (location off)" covers every Unavailable reason;
  - `specs/engine-sound-clip/spec.md` R2, R6 and R11 need nothing from this spec: the new status counts as answered for R2, as stopped for R6, and as a location status for R11. `specs/engine-clip-toggle/spec.md` amends R2 and R11, and `specs/break-reminder/spec.md` amends R11, for their own reasons;
  - `specs/speed-mascot/spec.md`, already superseded on Unavailable by ui-redesign R4;
  - `specs/break-reminder/spec.md`, which already names this status.
- **Shared with the sibling specs.** These are also changed by `specs/break-reminder/spec.md` or `specs/engine-clip-toggle/spec.md`. The edits touch different rows or bullets, so the three specs can be built in any order, and whichever ships later adds its note beside the others:
  - the chip order: R8 here, break-reminder R10 and engine-clip-toggle R11 give the same list;
  - the ui-redesign States table: this spec adds "Unavailable, Precise Location off"; break-reminder adds "Live, break due" and extends "Live, mic denied, no location status" with "and no break reminder"; engine-clip-toggle limits that row to "Engine sounds" on;
  - the speedometer-gauge States table: this spec changes the Unavailable row; break-reminder adds "Live, break due";
  - speedometer Data & API: this spec changes the `SpeedProvider` bullet; break-reminder and engine-clip-toggle add their keys (`trip.stretch`, `engineSound.enabled`) to the Persistence line;
  - osm-map R3: this spec changes its "Open Settings" bullet; break-reminder leaves R3 alone and amends R25.

## Requirements

### Detecting the setting
- **R1** **Reading the setting.**
  - When location is allowed, the location provider also reads whether Precise Location is on. Allowed means When In Use, or Always if it was ever granted.
  - It uses `CLLocationManager.accuracyAuthorization`. That is iOS 14+, so no `#available` check is needed. Reading it shows no prompt.
  - "Allowed with Precise Location off" is reported as its own authorization value, *authorized, approximate*. It comes on the existing authorization updates: the current value first, then every change (speedometer Data & API).

  *(unit: the provider's mapping from services, status and accuracy, as a pure static function like today's `authorization(from:)`; manual: device)*

- **R2** **Precedence.** Precise Location matters only when location is allowed. The accuracy setting is read only when the status is When In Use or Always:
  1. When Location Services is off, the screen shows "Location Services is off", whatever the other settings are.
  2. When access is not determined, the prompt is requested and the screen is Acquiring, as today (speedometer R16), whatever the accuracy setting reads. Before the prompt it may read either value.
  3. When access is denied or restricted, it shows "Location access is off", as today, whatever the accuracy setting reads.
  4. When access is allowed and Precise Location is off, it shows "Precise Location is off".

  *(unit: the mapping, for every combination of services, status and accuracy, including not determined with full and with reduced accuracy)*

- **R3** **Following changes.**
  - Precise Location changes only in the first prompt or in Settings, so the app is never active while it changes.
  - When the app is active again, the screen shows the new setting with no relaunch.
  - Two existing paths carry the change, and both stay:
    - The manager's authorization callback. iOS also calls it when only the accuracy changes (WWDC20 10660), and Apple's reference says to read both values there.
    - `run()` subscribes again every time the app becomes active, and subscribing publishes the current value at once (`SpeedometerView` `.task(id: scenePhase)`, `CoreLocationSpeedProvider.authorizationUpdates()`).

  *(unit: the fake sends authorized, then approximate, then authorized; manual: device, both directions)*

### Status
- **R4** **A fourth Unavailable reason.** While location is allowed but Precise Location is off, the state is **Unavailable** with the reason *Precise Location off*. The owner chose Unavailable over Acquiring on 2026-10-30.
  - The number shows `--` in the placeholder colour (gauge R8), and the gauge shows no reading: ring empty, needle at 0, no segments lit (gauge R2, gauge-themes States).
  - The status chip shows `location.slash` and **"Precise Location is off"** instead of "Searching for GPS…".
  - It shows within 1 s of opening the app with Precise Location off. On first launch, it shows right after "Precise: Off" is chosen in the system prompt.

  *(unit: status text and symbol after the fake sends the approximate value, with and without fixes; manual: device, 1 s from launch)*

- **R5** **Open Settings.** The existing "Open Settings" button also shows for this reason, with the same look and action (ui-redesign R17). It opens the app's own page in iOS Settings; there is no public link straight to the Precise Location switch (research). The line under the button depends on the reason:

  | Reason | "Open Settings" | Hint under it |
  |---|---|---|
  | Location access denied | yes | "Enable Location in Settings to see your speed" (unchanged) |
  | Precise Location off | yes | "Turn on Precise Location under Location to see your speed" |
  | Restricted, Location Services off | no | none (unchanged) |

  It shows wherever it shows for denied today: in gauge and map mode, in both orientations (User flows). *(unit: `canOpenSettings` and the hint for each reason; manual: the button opens Settings › Xpeet, whose Location row holds the switch)*

- **R6** **Clears by itself.** When Precise Location is on again:
  - The state goes straight to Acquiring, with "Searching for GPS…" and the `searching` mascot (ui-redesign R4). It goes to Live with the next accepted fix, with no relaunch (speedometer R18).
  - A fix that arrives before the app sees the new setting is dropped, as every fix is while Unavailable today. The reading starts with the fix after it.
  - **The other order.** When the app sees the new setting first, the next fix may still be a rough one taken earlier: the cached last-known position that a new subscription often starts with. The provider reads full accuracy by then, so it is not marked (R10). If iOS marks it stationary, today's code would take it at any age and show 0 and a map position kilometres off. So, after the state leaves *Precise Location off*, the ViewModel drops every fix timestamped before that moment, without looking at its content. The reading starts with a fix taken after it. This is an inference (Flagged concerns).
  - A switch from one reason to another, e.g. from Precise Location off to Location access denied, shows the new reason straight away.

  *(unit: fake provider; the fake sends the approximate value, then authorized, then a stationary fix timestamped before that moment, and nothing in R9 moves; a fix timestamped after it goes Live. manual: device, to Settings and back)*

- **R7** **The rest of the screen follows Unavailable.** Nothing new is built for these. Each already follows the Unavailable state, and this is one more reason:
  - **Mascot:** `sad` (ui-redesign R4).
  - **Trip:** nothing is measured. The trip line is hidden and the trip sheet can't be opened (trip-stats R1, R11).
  - **Break reminder:** this is "no reading" (`specs/break-reminder/spec.md` R1). The time is neither driving nor rest: drive time doesn't grow, a stop in progress is paused (its R4), and the 30 min rule still applies (its R5). The reminder's chip, if due, is hidden by this status and shows again when it goes (R8).
  - **Map mode:** the placeholder shows, with no marker and no tile requests, and the trail doesn't grow (osm-map R5, R9). The chip and "Open Settings" show over it (User flows).
  - **Engine sound:**
    - The vehicle counts as stopped, so a clip may play (engine-sound R6) while "Engine sounds" is on (`specs/engine-clip-toggle/spec.md`). The owner chose no change on 2026-10-30.
    - The location question counts as answered, so the mic prompt may follow it (engine-sound R2), again only while "Engine sounds" is on (engine-clip-toggle R6).

  *(unit: mood, `trip.line`, `showsMapPlaceholder`, `mapScene.marker`, and that the engine sound sees location as resolved, all with the approximate value)*

- **R8** **Chip order.** One chip shows at a time, in this order. The same list is in `specs/precise-location/spec.md` R8, `specs/break-reminder/spec.md` R10 and `specs/engine-clip-toggle/spec.md` R11:
  1. **Location statuses:** "Searching for GPS…", "Weak GPS signal", "Location access is off", "Location Services is off" and "Precise Location is off" (speedometer R6, R17; speed-accuracy R20; `specs/precise-location/spec.md`).
  2. **The break reminder** (`specs/break-reminder/spec.md`).
  3. **The mic chip** (engine-sound R11), only while "Engine sounds" is on (`specs/engine-clip-toggle/spec.md`).

  A lower chip shows only when no higher one does, and shows at once when the higher one goes if it still applies. The three specs can be built in any order: each adds only its own tier, and whichever ships later keeps this order in `statusText` and `statusSymbol`.

  This spec adds "Precise Location is off" to tier 1. It is a location status because it says the number can't be trusted. *(unit: `statusText` and `statusSymbol` with the mic denied and with a due break reminder)*

### Rough fixes
- **R9** **Rough fixes are never used.** A fix that iOS sends while Precise Location is off changes nothing, in any state. This holds even before the status shows, e.g. for a cached rough fix handled before the first authorization value at launch. It never moves:
  - the number, the estimate, the stale timer or the weak-signal flag;
  - the mascot;
  - the trip: distance, moving time and stopped time stay the same, and no route point is added (osm-map R16);
  - the break reminder: no drive time is added, and a stop neither grows nor ends (`specs/break-reminder/spec.md` R1, R4);
  - the map: the marker, trail, camera and first position (`hasPosition`, `lastPosition`) stay as they were.

  Stationary rough fixes are included, so a rough fix never shows 0. *(unit: the fake sends rough fixes while Acquiring, Live and Unavailable: stationary, moving with a valid speed, fresh and cached. Every output above is unchanged)*

- **R10** **Marked at the source.**
  - The provider marks each fix with the Precise Location setting at the moment it passes the fix on. This makes R9 hold before the first authorization value arrives.
  - The ViewModel drops marked fixes without looking at their content. Telling an approximate fix apart by its content (km-scale accuracy, no speed) is not reliable (research: Apple, Foursquare).

  *(unit: fake; review: the provider reads the setting for each fix)*

- **R11** **Still recorded.** In a Debug build launched with `-XpeetRecordDrives YES` (speed-accuracy R22), rough fixes are written to the recording before they are dropped. They are written as ordinary fix lines, as fixes are while Unavailable today, without the Precise Location mark. That is an exception to speed-accuracy R22's "every field in R1" (Changes to earlier specs). The recording format and `DriveHeader.formatVersion` are unchanged.
  - A rough fix line can't be told from a precise one. A recording is still all one or the other: each `run()` writes its own file (speed-accuracy R22), and Precise Location can't change while the app is active (R3). The one exception is the stale rough fix at the start of a run that R6 drops.
  - A rough recording is kept out of `build/drives/` by hand (R15).

  *(unit: a fake recorder receives the fix)*

### Unchanged
- **R12** **Precise Location on.** With Precise Location on, the screen behaves exactly as it does today, and every existing test passes unchanged. *(unit: full suite)*

- **R13** **Nothing to tap, hear or grant.**
  - **No new prompt:** the app never asks for precise location just this once (`requestTemporaryFullAccuracyAuthorization`). The owner ruled this out on 2026-10-30.
  - **No new Info.plist key:** `NSLocationDefaultAccuracyReduced` and `NSLocationTemporaryUsageDescriptionDictionary` stay unset, so the first prompt keeps "Precise: On" as its default.
  - **No signal when the status appears:** no sound, haptic, alert or VoiceOver announcement.
  - **Nothing to tap while driving:** the status is read-only. "Open Settings" is for when I am parked.

  *(review: the `project.yml` diff; no `requestTemporaryFullAccuracyAuthorization`, `sensoryFeedback` or `AccessibilityNotification` for this status)*

### Accessibility
- **R14** **VoiceOver, text size, motion, contrast.**
  - **VoiceOver,** like the other location messages:
    - The chip is one element and reads "Precise Location is off". Its dot and icon are hidden (gauge R6).
    - "Open Settings" is a button, and the hint is read as text after it.
    - The speed reads "No GPS signal", as in every state without a reading (speedometer R21).
  - **Dynamic Type:**
    - The chip, the button and the hint follow Dynamic Type up to `accessibility2`, as today.
    - Text wraps and is never truncated.
    - In landscape, with the chip, button and hint at the bottom edge, the gauge keeps the "199" rule (gauge-themes R14).
  - **Reduce Motion:** nothing about this status animates.
  - **Contrast:** there are no new colours.
    - The chip text, the "Open Settings" label and the hint already reach 4.5:1 on every face (ui-redesign R16).
    - In map mode, the chip sits on its opaque card (osm-map R4), and the hint sits on the placeholder, which is the theme background.

  *(manual: Accessibility Inspector, largest text size, both orientations, every face, gauge and map mode, and iPhone SE portrait at the default text size, where the two-line hint may hide the mascot (Open questions); unit: the strings and the existing contrast tests)*

### Device check
- **R15** **What iOS sends: one recorded drive.** Record a drive with Precise Location off, in a Debug build launched with `-XpeetRecordDrives YES` (R11), until at least 4 rough fixes are recorded. Apple says rough positions are recomputed about four times an hour (research), so that is about 60 min or more.
  - **Keep Xpeet in front** for the whole drive. An app switch starts a new file, and a file with no fix is deleted (speed-accuracy R22). Count the fixes after copying the files off; with fewer than 4, drive again.
  - **Where it goes:** copy the recording off the phone into a folder other than `build/drives/`, e.g. `build/drives-precise-off/`. The accuracy report reads every `.jsonl` file in `build/drives/` (`XpeetTests/Accuracy/DriveFile.swift`).
  - **What to write down,** in `specs/precise-location/results.md`, for the rough fixes:
    - speed and speed accuracy (-1 is expected, but unconfirmed);
    - course;
    - the stationary flag;
    - horizontal accuracy;
    - the time between fixes. It is measured on recorded fixes, after the provider has dropped repeated timestamps (speed-accuracy R1), so repeats iOS sends are not counted.
  - **No real places or dates** in `results.md`, which is committed: no coordinates, and times as seconds from the start (as speed-accuracy R31 asks of committed clips).
  - **Back on, while parked:** turn Precise Location on in Settings and return to Xpeet. Note whether the first fix after the return is rough (horizontal accuracy in kilometres) and stationary. This checks the inference behind R6's "other order".
  - **On screen:** the same drive checks R4 and R9 by eye. The status shows within 1 s and nothing moves.
  - **Not a release gate:** the status does not depend on the answer (intent).

  *(manual)*

## User flows & UI

**Opening the app with Precise Location off.** Within 1 s the chip says "Precise Location is off" and the number shows "--". The mascot is sad and the trip line is gone. "Open Settings" shows, with "Turn on Precise Location under Location to see your speed" under it. Nothing on screen changes while I drive.

**First launch, "Precise: Off" chosen.** The screen is in Acquiring under the system prompt. After "Allow While Using App" or "Allow Once" with Precise off, "Searching for GPS…" becomes "Precise Location is off".

**Turning it on.**
1. Parked, I tap "Open Settings". It opens Settings › Xpeet.
2. I tap Location and switch Precise Location on.
3. I go back to Xpeet. The chip says "Searching for GPS…" and the mascot searches.
4. The speed shows with the next fix. There is no relaunch.

**Turning it off.** I switch it off in Settings while Xpeet is in the background. When I come back, the status shows, and everything in R7 stops.

| State | Chip | Number, arc | Mascot (gauge) | Trip line | Map mode | Open Settings |
|---|---|---|---|---|---|---|
| **Permission not determined** (prompt showing) | `location.magnifyingglass` "Searching for GPS…" | `--`, empty | `searching` | shown, frozen | placeholder | no |
| **Acquiring** (loading: no fix yet, a gap, or just after Precise came back on) | "Searching for GPS…" | `--`, empty | `searching` | shown, frozen | placeholder until the first fix since launch, then the dimmed marker | no |
| **Live** (success, Precise on) | none, or weak signal, break reminder or mic chip (R8) | speed | per mood curve | live | tiles, marker, trail | no |
| **Unavailable, Precise Location off** (new) | `location.slash` "Precise Location is off" | `--`, empty | `sad`; may be hidden on iPhone SE portrait, where the two-line hint leaves less than 44 pt (Open questions) | hidden | placeholder, no marker, no tiles | yes, with "Turn on Precise Location under Location to see your speed" |
| **Unavailable, denied** (permission denied) | `location.slash` "Location access is off" | `--`, empty | `sad` | hidden | placeholder | yes, with "Enable Location in Settings to see your speed" |
| **Unavailable, restricted** | `location.slash` "Location access is off" | `--`, empty | `sad` | hidden | placeholder | no |
| **Unavailable, Location Services off** | `location.slash` "Location Services is off" | `--`, empty | `sad` | hidden | placeholder | no |

There is no empty state, as in speedometer: "no fix yet" is Acquiring. The Unavailable rows are the error states. There is no loading state of its own: the setting comes with the first authorization value.

| Mode and orientation | Chip | "Open Settings" and hint | What moves |
|---|---|---|---|
| Gauge, portrait | top row, centred (ui-redesign R7) | at the bottom edge, as for denied | nothing in the top row, which stays reserved. The gauge gives up the button's height, as for denied |
| Gauge, landscape | bottom edge | under the chip | the gauge gives up the chip, button and hint height, as for denied; "199" rule kept (gauge-themes R14) |
| Map, portrait | top row over the placeholder, opaque card (osm-map R3, R4) | at the bottom edge, as for denied | as for denied |
| Map, landscape | bottom edge, opaque card | under the chip | as for denied |

The sheets show nothing new. The trip sheet can't be reached while Unavailable (trip-stats).

**Accessibility.** See R14. The status is text with an icon, so nothing depends on colour alone.

## Data & API
- **No new folder or app source file.** Everything fits existing files, so the CLAUDE.md Architecture section does not change. The only new files are one test file and, after R15, `results.md`. CoreLocation stays inside `Core/Location/`.
- **`Core/Location/SpeedProvider.swift`** (Foundation only):
  - `LocationAuthorization` gains `case authorizedApproximate`: allowed, Precise Location off (R1).
  - `LocationUpdate` gains `case approximateFix(SpeedSample)`: a fix passed on while Precise Location was off (R10). `SpeedSample` is unchanged. The recording writes rough fixes as ordinary `DriveEvent.fix` lines without the mark (R11, the speed-accuracy R22 exception), so the recording format, `DriveHeader.formatVersion` and the replay are unchanged too.
  - The `SpeedProvider` protocol is unchanged.
- **`Core/Location/CoreLocationSpeedProvider.swift`:**
  - `publishAuthorization()` also reads `manager.accuracyAuthorization` when the status is `.authorizedWhenInUse` or `.authorizedAlways`. `.reducedAccuracy` gives `.authorizedApproximate` (R1, R2). The mapping becomes a static function of "services enabled", status and accuracy, so it can be unit-tested.
  - `speedUpdates()` reads `manager.accuracyAuthorization` as it passes each fix on, and yields `.approximateFix` when the value is `.reducedAccuracy` (R10).
    - Its task runs on the main actor, where the manager lives. This is an inference from the research, to be confirmed in the plan.
    - The duplicate drop is unchanged.
  - `locationManagerDidChangeAuthorization` is unchanged. It already republishes, and iOS calls it for accuracy changes too (R3).
  - Not used: iOS 18's `CLLocationUpdate.accuracyLimited` and the `CLServiceSession` diagnostics (Out of scope).
- **`Core/Location/FakeSpeedProvider.swift`** (`#if DEBUG`): `send(.authorizedApproximate)` already works through `send(_:)`. The fake gains `sendApproximate(_ sample:)`.
- **`Features/Speedometer/SpeedometerViewModel.swift`** (`@Observable @MainActor`, no new injected dependency). All logic is in synchronous handlers; `run()` only feeds streams:
  - `SpeedometerState.UnavailableReason` gains `.preciseOff`. `recordedName` stays "unavailable".
  - `handle(authorization:)`:
    - `.authorizedApproximate` calls `becomeUnavailable(.preciseOff)`. That already resets the filter, sets `sad`, stops the trip and refreshes the map (R4, R7).
    - `.authorized` leaves every Unavailable reason for Acquiring, as today (R6). When it leaves `.preciseOff`, it also stores `now()` in a new `@ObservationIgnored` property, `preciseOffEndedAt: Date?`.
  - `handle(sample:)` records the fix as today, then drops it if its timestamp is before `preciseOffEndedAt` (R6, the other order). The property is kept until the next exit from `.preciseOff` replaces it, because a fix taken before that moment is rough or older still. With Precise Location never off it stays nil, so R12 holds.
    - The engine-sound prompt gate (`authorization != .notDetermined`) already counts the new value as answered.
  - A new synchronous `handle(approximateFix:)` records the fix (R11) and returns (R9). `run()` routes the new `LocationUpdate` case to it.
  - `locationStatusText` maps `.unavailable(.preciseOff)` to "Precise Location is off". `locationStatusSymbol` is unchanged: `location.slash` for every Unavailable reason.
  - `canOpenSettings` is true for `.denied` and `.preciseOff`.
  - A new `openSettingsHint: String?` gives the hint for the current reason (R5), and nil when there is no button.
  - The mascot, trip, break reminder and map code don't change. They follow `state` (R7).
- **`Features/Speedometer/SpeedometerView.swift`:** `openSettings` shows `viewModel.openSettingsHint` instead of a fixed string, and map mode reuses it (`SpeedometerView+Map.swift`). The previews gain "Precise off" in gauge portrait, gauge landscape and map mode.
- **Tests:**
  - `XpeetTests/SpeedometerViewModelTests.swift`: R4–R9, R11 and R14's strings. The trip and map checks go in the `+Trip` and `+Map` extensions.
  - `XpeetTests/LocationAuthorizationTests.swift`: the provider mapping (R1, R2), as a pure helper. It imports CoreLocation for the status values, as the map tests already import MapKit.
- **Persistence:** none. Nothing new is stored (intent Constraints).
- **Offline:** no network is involved.

## Non-functional
- **Performance:** one property read per fix and per authorization change. There is no new timer, no new sensor, and no observed property that changes on every tick.
- **Battery:** location updates keep running while Precise Location is off, as in every foreground state (speedometer R20). iOS sends rough fixes only a few times an hour (research: `kCLLocationAccuracyReduced`), so the cost is at most today's.
- **Privacy:**
  - No new data is collected. There is no new permission, prompt or Info.plist string. The location usage string (osm-map R28) is unchanged.
  - Rough positions are never shown, stored or sent. Like every fix, they reach only the opt-in Debug recording (R11).
- **Localization:** two new strings, through `String(localized:)`:
  - "Precise Location is off"
  - "Turn on Precise Location under Location to see your speed"

  "Precise Location" and "Location" match the labels iOS uses in Settings and in the prompt (research: the `PRECISE_LOCATION` string in the iOS 17.5 runtime). A translation must use the system's own term.

## Out of scope
- Asking for precise location just this once (`requestTemporaryFullAccuracyAuthorization`) and its Info.plist text (owner, 2026-10-30).
- An onboarding or pre-prompt screen. Setting `NSLocationDefaultAccuracyReduced`.
- Any use of the rough positions, e.g. a rough marker or map centre.
- Marking the trip approximate for the time with Precise Location off. The status is the warning, and trip-stats R3 is unchanged.
- iOS 18 signals: `CLLocationUpdate.accuracyLimited`, and `CLServiceSession` diagnostics such as `fullAccuracyDenied`. iOS 17 has neither, and a session with a full-accuracy purpose key may prompt (research).
- Telling Precise Location from a fix's content.
- Stopping location updates while Precise Location is off.
- A new spoken speed label for this reason. It stays "No GPS signal".
- A sound, haptic, alert or announcement for this status.
- Engine clip changes. Turning clips off is `specs/engine-clip-toggle/spec.md`.

## Flagged concerns
- **Privacy (for the owner's record):**
  - No new data, permission, prompt or Info.plist key (R13). The app reads one more setting on a manager it already owns.
  - Rough fixes reach only the opt-in Debug recording (R11).
  - Nothing needs approval beyond this spec.
- **Info.plist:** unchanged.
  - `NSLocationDefaultAccuracyReduced` stays unset, so the first prompt offers "Precise: On" by default (`project.yml`).
  - There is no `NSLocationTemporaryUsageDescriptionDictionary`, because there is no temporary request.
- **App Review Guidelines and HIG** (not binding for a sideloaded build; for reference):
  - **5.1.1(iv):** respect the user's permission choice, and don't manipulate or force consent. The status appears only after the choice. It says what is off and where to change it, blocks nothing else, and never prompts again.
  - **HIG Privacy:** no custom screen before the system prompt. None is added.
  - **WWDC20 10660:** Apple prefers a temporary full-accuracy request to sending people to Settings, except when a feature needs precise location all the time. A speedometer is that case, and the owner ruled the request out.
  - **Driving safety (1.4.4, 1.4.5):** the status is read-only. "Open Settings" is for when I am parked. There is no sound or haptic (R13).
- **Spec amendments needing owner sign-off** (listed at the top):
  - speedometer R17, R18, the States table and Data & API;
  - the speedometer-gauge States table and portrait layout;
  - ui-redesign R4, R17 and the States table;
  - the gauge-themes States table;
  - osm-map R3 and the States table;
  - speed-accuracy R1 and R22, which the intent did not list (see the next item).
- **Launch race (an inference from the research, not seen on a device):**
  - The state starts as Acquiring. Authorization and fixes arrive on separate tasks, and the first authorization value waits on a detached `locationServicesEnabled()` call. So a cached rough fix could be handled before the status appears.
  - If iOS marks that fix stationary, the screen shows 0 briefly. The map keeps a position kilometres off, and the trip may gain a stopped update.
  - R9 and R10 close the race by marking fixes at the source. That costs the speed-accuracy R1 and R22 amendments and one `LocationUpdate` case. The owner may drop R10 and accept the race instead.
- **The reverse race (also an inference):**
  - After Precise Location comes back on, `run()` starts again and the first fix may be the cached rough one. If `.authorized` is handled first, the state is Acquiring and the provider reads full accuracy, so the fix is not marked.
  - Today's code takes a stationary fix at any age (speedometer R6) and sets the map's first position (`hasPosition`, `lastPosition`). The map would show tiles and a marker kilometres off while parked, and iOS pauses updates while stationary, so it could last.
  - R6 closes it in the ViewModel by dropping fixes timestamped before the state left *Precise Location off*. The cost: while parked, the screen may stay on "Searching for GPS…" until iOS sends a new fix.
  - **Not covered:** a cold launch after Precise Location came back on. The state starts as Acquiring, so there is no moment to compare with. The rule can't drop every cached fix at launch, because a cached stationary precise fix shows 0 today (speedometer R6) and R12 keeps that. R15 checks whether the first fix after the return is rough.
- **Unverified (R15):**
  - **What iOS sends with Precise Location off.** The speed, speed accuracy, course and stationary flag of rough fixes are undocumented. Apple documents only "usually within 1–20 kilometers" and "at most a few times per hour". The status does not depend on this.
  - **The accuracy-change callback** rests on WWDC20 10660. Apple's reference page says to read both values in the callback, but does not say outright that it fires for an accuracy change alone. R3's second path, subscribing again on return, covers it either way.
  - **The simulator.** `simctl privacy` has no accuracy option. The simulator runtime ships the "Precise Location" strings, so its Settings probably has the switch, but whether that switch changes `accuracyAuthorization` is unconfirmed. The simulator never goes Live, so it can check only the status UI.
- **Where the recording goes:** a Precise-off recording must stay out of `build/drives/`. Otherwise the accuracy report would treat its rough fixes as an ordinary drive (R15).
- **Sibling specs:** the chip order (R8) is the same list as `specs/break-reminder/spec.md` R10 and `specs/engine-clip-toggle/spec.md` R11. The three can be built in any order; whichever ships later keeps the order in `statusText`. The older-spec rules they share are listed under Changes to earlier specs.
- **No security, payment or CLAUDE.md impact,** so no eval re-run is needed.

## Open questions
Carried from the intent:
- *Unavailable or Acquiring?* **Answered (owner, 2026-10-30):** Unavailable, with its own reason. The trip line and sheet are hidden, nothing is measured, the map shows its placeholder and the mascot is `sad` (R4, R7).
- *Ask for precise location just this once?* **Answered (owner, 2026-10-30):** no. It would ask on every launch and needs its own Info.plist text (R13, Out of scope).
- *Engine clip?* **Answered (owner, 2026-10-30):** no change. engine-sound R6 treats every Unavailable reason as stopped (R7). Turning clips off is `specs/engine-clip-toggle/spec.md`.
- *Chip order?* **Answered (owner, 2026-10-30):** it is a location status, above the break reminder and the mic chip (R8).
- *What does iOS send?* **Answered (owner, 2026-10-30):** record one drive (R15). **Still open:** the result. It is not a release gate.
- *Out of scope list?* **Answered (owner, 2026-10-30):** onboarding, any use of the rough positions, and marking the trip approximate (Out of scope).

Raised by this spec and its research (defaults chosen here; the owner may change them in review):
- *Mark fixes at the source (R10) for a race that is only inferred?* Proposed: yes. It is small, and it keeps "rough fixes are never used" true at launch.
- *Drop fixes taken before Precise Location came back on (R6, the other order), for a reverse race that is also only inferred?* Proposed: yes. It needs one stored date and no content check. The cost is that a parked phone may stay on "Searching for GPS…" until iOS sends a new fix. **Still open:** a cold launch after the switch is not covered; R15 checks whether the first fix is rough at all (Flagged concerns).
- *Always with Precise Location off?* Proposed: the same as When In Use (R1). The app never asks for Always (speedometer R16).
- *The new hint is longer than the denied one,* and wraps to two lines on most phones, where ui-redesign R17 and the intent say "one line".
  - **Effect on the mascot:** on iPhone SE (2nd/3rd gen) portrait, the denied state already leaves only about 58 pt above the gauge (`MascotPlacementTests`). A second 13 pt hint line takes about 17 pt more, which leaves about 49.5 pt. Less the 8 pt gap, that is about 41.5 pt, below the 44 pt floor, so the `sad` mascot hides (`MascotPlacement`, ui-redesign R5, which was amended in build so the sad face shows on iPhone SE when denied).
  - Proposed: keep the intent's wording and accept the hidden mascot on iPhone SE portrait (States table, R14). The other choice is a hint that fits one line on a 375 pt phone, which keeps the mascot. The owner may choose it in review.
- *The speed still reads "No GPS signal" for this reason* (R14). Proposed: accept. The chip says why, as it does for denied.
- *Location updates keep running while Precise Location is off* (Non-functional). Proposed: accept.
- *Does the simulator's Precise Location switch change `accuracyAuthorization`, and does it degrade simulated fixes?* **Still open:** check by hand in the iOS 17.5 simulator. If it does, R4, R5 and R14 can be checked there. Otherwise they are checked on a device.
- *Is iOS 18's `accuracyLimited` set on every reduced update?* **Not needed:** it isn't used (Out of scope).
