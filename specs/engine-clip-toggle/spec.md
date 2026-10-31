# Spec: Turn the engine-start clip on or off

**Intent:** intent/2026-10-30-engine-clip-toggle.md  **Status:** approved

This spec adds one "Engine sounds" switch to the gauge style sheet. It is on by default. Off means the app stops listening: the microphone, the sound classifier and the orange mic indicator stop, no clip plays and no mic chip shows. On resumes listening at once with today's rules. An optional Focus filter turns clips off while a chosen Focus is on. It is built only if a throwaway device spike passes (R14). No new permission, screen, button on the speed screen or Info.plist string.

Research: the researcher agent's findings from 2026-10-30 are cited as [R: …] under Data & API, Flagged concerns and Open questions. Sources are listed at the end.

Sibling specs written from intents of the same date: `specs/precise-location/spec.md` (a new location status, "Precise Location is off") and `specs/break-reminder/spec.md` (a break-reminder chip). The chip order agreed across all three is in R11. This spec does not restate their behaviour.

Changes to other specs (each gets a note in the implementation commit, as trip-stats did):
- `specs/engine-sound-clip/spec.md`:
  - **R1** amended: listening also needs the switch on (R4, R9 here). "and no toggle" goes. The lifecycle and "no background audio mode" stay.
  - **R2** amended: the automatic mic request also waits for the switch to be on (R6 here). Still asked once, after location, never again.
  - **R7** unchanged, clarified: a clip cut off by turning the switch off has started, so it starts the cooldown (R5 here), as a clip cut off by leaving the app does today.
  - **R10** amended: when an interruption ends and the app is active, listening resumes only if the switch is on and no Focus override is active (R4, R16 here).
  - **R11** amended: the mic chip shows only while the switch is on (R7 here), and it comes last in the chip order, after the break reminder (R11 here). `specs/break-reminder/spec.md` amends R11 too. The two notes combine, in either order, into: "with 'Engine sounds' on, the mic chip shows when there is no location status and no break reminder".
  - **R12** amended: "silently stays off for that session" now ends when the switch is turned off and on again. That retries listening (R9 here). A repeat failure is silent again.
  - User flows table: a new row "Clips off (switch)". The "Mic denied or restricted" row applies only while the switch is on. `specs/break-reminder/spec.md` changes the same row's UI cell to "mic chip, unless a location chip or the break reminder is showing"; the two edits combine in either order.
  - Data & API "Persistence: none" becomes one key (R2 here). Localization: no change, because the switch strings belong to the sheet (gauge-themes Localization).
  - Out of scope: "and an on/off toggle" goes. Open questions: "Import, volume setting, toggle?" and "Should the mic-denied chip be permanent?" are answered by this spec.
  - Flagged concerns, "revisit … with an opt-in toggle": the switch now exists, but it is on by default. Opt-in for distribution stays open (Flagged concerns here).
- `specs/gauge-themes/spec.md`:
  - **R10** amended: the sheet also holds the "Sound" section (R1 here).
  - **R16** amended: VoiceOver covers the switch (R12 here). The face button hint changes (R13 here). The label "Gauge style" stays.
  - **R17** amended: the section and help line follow Dynamic Type like the rest of the sheet (R12 here).
  - Localization gains the strings in Non-functional here.
  - Out of scope "Mascot and engine-sound settings in the sheet": engine-sound settings move into scope; mascot settings stay out.
- `specs/ui-redesign/spec.md`:
  - **R18** amended: under the 2×2 grid, the sheet has the "Sound" section (R1 here).
  - States table: the row "Live, mic denied, no location status" applies only while the switch is on. `specs/break-reminder/spec.md` extends the same row with "and no break reminder" and adds "Live, break due"; `specs/precise-location/spec.md` adds "Unavailable, Precise Location off". Together, in any order: "Live, mic denied, no location status and no break reminder ("Engine sounds" on)".
- `specs/speedometer/spec.md`:
  - Data & API, Persistence ("one `UserDefaults` key, `speedUnit` … Nothing else is stored."): a note that `engineSound.enabled` is stored too (R2). `specs/break-reminder/spec.md` adds `trip.stretch` to the same note; either can go first.
  - No other change. R20 (foreground only, no `UIBackgroundModes`) and Out of scope "Settings screen (except the face picker sheet …)" stay, because the switch lives in that sheet.
- `specs/osm-map/spec.md`: no change. Map mode hides the face button (R3), so the switch is reached from gauge mode. R1's "engine sound carry on" still holds.

## Requirements

### The switch
- **R1** **Place and wording.** In the gauge style sheet (gauge-themes R10, ui-redesign R18), under the 2×2 grid of faces:
  - a section heading "Sound";
  - one standard switch labelled "Engine sounds";
  - one help line under it: "Plays a short clip when the engine starts. Off stops the microphone."

  The sheet keeps its title "Gauge style", its subtitle and "Done". The section sits in the sheet's existing scroll view, so at medium height it may need a scroll. That is checked on iPhone SE (Open questions). *(manual: previews; iPhone SE at medium height, both orientations)*

- **R2** **Default and memory.**
  - The switch is stored in the injected `UserDefaults` under `engineSound.enabled` (a Bool).
  - With nothing stored, or with a stored value that is not a Bool, the switch is **on**. First launch is unchanged.
  - A change is saved at once and restored on the next launch.

  *(unit: injected `UserDefaults` suite: absent, wrong type, off, on, round trip)*

- **R3** **Always available, touches nothing else.**
  - The switch works in every state, including Acquiring, Unavailable and while moving. It is not locked while moving, like face changes (gauge-themes R11).
  - It is reachable only from gauge mode, because map mode hides the face button (osm-map R3). Its effect applies in both modes.
  - Changing it never changes the displayed speed, unit, face, screen mode, trip, route, recording, filter, any location chip, or the break reminder and its drive time (`specs/break-reminder/spec.md`).

  *(unit: toggling leaves `state`, `displayedSpeed`, `unit`, `face`, `screenMode`, `trip` and `breakReminderHours` unchanged)*

### Off
- **R4** **Off stops listening.** Turning the switch off ends the detector's events stream at once. That runs the existing teardown in `SoundAnalysisTriggerDetector.events()`: the tap is removed, `AVAudioEngine` stops, the analyzer requests are removed, and the audio session is deactivated.
  - `pause()` is not used for this, because it only drops buffers and leaves the input running [R: codebase].
  - While off, nothing calls `detector.events()` and nothing activates the audio session. This holds across leaving and returning to the app.
  - Listening stops without the scene leaving the active state and without `SpeedometerViewModel.run()` ending. Location, motion, ticks and tiles keep running.

  *(unit: with `FakeSoundTriggerDetector`, `eventSubscriberCount` drops to 0 after off while `run()` continues, and stays 0 through a new `run()` while off)*

- **R5** **Off stops a playing clip.** A clip that is playing when the switch goes off stops at once. It has started, so the 60 s cooldown runs from its start (engine-sound R7). Turning the switch back on within 60 s therefore plays no clip until the cooldown ends (Open questions). *(unit: off while the fake player plays cancels the play, and a qualifying detection within 60 s of its start is dropped after turning on again. manual: device)*

- **R6** **Off: no prompt.** If the mic is still "not determined" while the switch is off, the mic is not requested, even once location is answered. Answered includes allowed with Precise Location off (`specs/precise-location/spec.md` R7). The deferred request is made only when the user turns the switch on in the sheet, if location is answered by then (engine-sound R2). It is never made because a Focus ends (R16). *(unit: switch off, location resolved, mic not determined: `requestAuthorizationCount` stays 0. Turn on: it becomes 1)*

- **R7** **Off: no mic chip.** While the switch is off, the mic chip never shows, even when the mic is denied. It disappears as soon as the switch goes off. *(unit: mic denied, no other status: `statusText` is "Microphone off: enable it in Settings to hear engine sounds" when on and nil when off)*

- **R8** **Off, measured on a device** (intent Measurable):
  - With the switch off, a 10-minute session with engine starts and revs plays no clip and never shows the orange mic indicator.
  - Switching off clears the mic indicator within 2 s. The 2 s is a manual target, not a code constant.

  *(manual: device with screen recording; the simulator cannot show this)*

### On again
- **R9** **On resumes at once.** Turning the switch on starts listening again in the same `run()`, without relaunching the app, without closing the sheet and without the scene leaving active. The mic authorization is read again:
  - **authorized:** listening starts (a new events stream). The indicator returns within 2 s (manual target).
  - **denied:** no prompt, because iOS never asks again once answered [R: requestRecordPermission]. The mic chip comes back unless a higher chip shows (R11).
  - **not determined:** R6 applies.
  - **listening failed earlier** (engine-sound R12): off then on retries listening with a new events stream. A repeat failure stays silent (`phase` `.failed`, no chip). The existing `.failed → .idle` reset at the start of `EngineSoundViewModel.run()` already does this [R: codebase].

  *(unit: off then on: `eventSubscriberCount` returns to 1 and `phase` is `.listening`. Rapid off/on/off ends at 0 subscribers. With `failOnStart`, then `failOnStart = false`, off then on reaches `.listening`. manual: device)*

- **R10** **Same rules when on.** Detection (engine-sound R3), the moving gate (R6: no clip while the displayed speed is above 0), the 60 s cooldown (R7) and the self-trigger tail (R8) are unchanged. Toggling does not reset the cooldown. With the mic allowed and the speed showing 0, an engine start after the cooldown plays a clip. *(unit: existing engine-sound tests pass unchanged. manual: device, intent Measurable)*

### Status chip
- **R11** **Chip order.** One chip shows at a time, in this order. The same list is in `specs/precise-location/spec.md` R8, `specs/break-reminder/spec.md` R10 and `specs/engine-clip-toggle/spec.md` R11:
  1. **Location statuses:** "Searching for GPS…", "Weak GPS signal", "Location access is off", "Location Services is off" and "Precise Location is off" (speedometer R6, R17; speed-accuracy R20; `specs/precise-location/spec.md`).
  2. **The break reminder** (`specs/break-reminder/spec.md`).
  3. **The mic chip** (engine-sound R11), only while "Engine sounds" is on (`specs/engine-clip-toggle/spec.md`).

  A lower chip shows only when no higher one does, and shows at once when the higher one goes if it still applies. The three specs can be built in any order: each adds only its own tier, and whichever ships later keeps this order in `statusText` and `statusSymbol`.

  This spec changes only tier 3:
  - The mic chip shows while the switch is on and the mic is denied (R7). Its text and icon are unchanged: `mic.slash` and "Microphone off: enable it in Settings to hear engine sounds".
  - The switch never hides, shows or delays a tier 1 or tier 2 chip (R3). With the switch off, nothing shows below the break reminder.

  *(unit: `statusText`/`statusSymbol` priority, with the switch on and off, the mic denied, and a location status or a due break reminder)*

### Accessibility
- **R12** **Switch accessibility.**
  - **VoiceOver:**
    - "Sound" has the header trait.
    - The switch is a standard SwiftUI `Toggle`. VoiceOver reads its name and state ("Engine sounds, off").
    - The help line is the switch's accessibility hint. As its own element it is hidden, so it is not read twice.
  - **Dynamic Type:** the heading, label and help line follow Dynamic Type up to accessibility sizes, like the rest of the sheet (gauge-themes R17). They wrap and are never truncated, and the sheet scrolls.
  - **Contrast:** the help line reaches at least 4.5:1 against the sheet background over every face, Retro included, measured with Accessibility Inspector's contrast audit. It uses `.secondary`, like the subtitle, only if that passes on every face. Otherwise it uses `.primary` or a theme token. The switch state is shown by the knob position as well as colour (standard switch).
  - **Reduce Motion:** nothing new animates. The switch's own animation is the system's.

  *(manual: Accessibility Inspector, largest size, both orientations. unit: the label and hint strings)*

- **R13** **Face button hint.** The face button keeps the label "Gauge style". Its hint becomes "Double-tap for gauge faces and engine sounds" (was "Double-tap to choose a gauge face", gauge-themes R16). *(unit: `SpeedometerView.faceButtonHint`)*

### Focus filter (optional)
- **R14** **Go/no-go spike, before the plan.** The intent asked for the device checks before the spec. They need a build that already contains a filter, so they run as a throwaway spike:
  - a minimal `SetFocusFilterIntent` with one Bool parameter, on a scratch branch that is never merged;
  - built after `xcodegen generate`, and installed on the owner's device signed with the free personal team.

  Gates, recorded in `plan.md` before any R15–R19 code is written:
  - (a) Xpeet is listed under Settings › Focus › (a custom Focus) › Focus Filters › Add Filter;
  - (b) the built `.app` contains `Metadata.appintents`.

  The spike also records the other device checks in Open questions. They are answers, not gates. Among them: whether Driving and Sleep list the filter (the intent's example is a custom "Passenger" Focus), and how long reading `current` takes (R17). If (a) or (b) fails, R15–R19 and R20's Focus line are dropped by a spec amendment, and R1–R13 ship alone. The owner may instead move R15–R19 to a follow-up amendment now (Flagged concerns). *(manual: device; build: inspect the bundle)*

- **R15** **The filter.** One `SetFocusFilterIntent` type in the app target (not in a framework [R: WWDC22 10032]):
  - title "Engine sounds";
  - description "Turns Xpeet's engine sounds off and stops the microphone while this Focus is on.";
  - one Bool parameter, "Turn off engine sounds", **default false**. iOS calls `perform()` with the default values when the Focus ends [R: WWDC22 10121], so the default must mean "no change" [R: forum 766761]. This means one extra tap when adding the filter;
  - summary (`displayRepresentation`): "Engine sounds off" when the parameter is on, "Engine sounds unchanged" when it is off.

  *(build: compiles in the app target. manual: Settings shows the strings)*

- **R16** **Effect.** While a Focus whose Xpeet filter has "Turn off engine sounds" on is active, the app behaves as with the switch off (R4–R8). The stored switch value (R2) is not changed. When that Focus ends, the stored switch applies again: if it is on, R9 applies, with one exception. A mic still "not determined" is not requested when the Focus ends, so no system prompt pops up over the speed screen without a tap. It is requested the next time the speed screen starts (`run()`) with the switch on and no override, as engine-sound R2 does at launch, or when the user turns the switch on in the sheet (R6). *(unit: with a fake Focus provider, the effective state is "switch on and no Focus override"; the stored key is untouched. Override on, location resolved, mic not determined: the Focus ends and `requestAuthorizationCount` stays 0. A new `run()` makes it 1)*

- **R17** **Delivery.**
  - While the app runs, a `perform()` takes effect at once.
  - Each time the speed screen starts running (`run()`, on each return to active), the app reads the filter's current value (`SetFocusFilterIntent.current`). That picks up a change made while the app was not running.
  - If reading throws (for example `SetFocusFilterIntentError.notFound`), there is no override [R: `current` behaviour undocumented].
  - **First value.** With a Focus provider present, engine sound treats "Focus value not yet known" as off (R4, R6, R7) on each `run()`. Nothing calls `detector.events()` and nothing requests the mic until that run's first value arrives. Without this, every return to the app during a filtered Focus could start the mic or show the prompt for a moment. If the spike (R14) finds the read can hang, the plan adds a named timeout, after which there is no override.
  - **No active scene.** With no extension, iOS may launch the app's process without a scene to run `perform()` [R: WWDC22 10032]. Then `perform()` only updates the in-memory relay. It creates no `SpeedometerViewModel` and starts no location, motion, mic or tile work. That work starts only from the speed screen's `.task(id: scenePhase)` while the scene is active (speedometer R20).
  - No App Intents extension, no App Group, no `UIBackgroundModes`. The Focus value is held in memory only, never stored.

  *(unit: the pure mapping from a `current` read to an override: a thrown error gives no override, a value gives that value. With a fake provider: override applied and cleared. A fake that holds back its first value keeps `eventSubscriberCount` and `requestAuthorizationCount` at 0 until it yields, then today's rules apply. manual: device, Focus switched on and off with the app open and with the app closed. While closed, the location arrow and the orange mic dot stay off)*

- **R18** **The sheet says so.** While the Focus override is on:
  - the switch shows off and is disabled;
  - the help line is replaced by "Off while a Focus is on. Your choice applies again when it ends.";
  - VoiceOver reads the switch as dimmed, with that line as its hint.

  *(unit: the ViewModel exposes the override. manual: preview and device)*

- **R19** **Nothing else.**
  - No new permission prompt, Info.plist usage string or entitlement. Apple's material lists no entitlement for Focus filters [R: inference].
  - No `AppShortcutsProvider`, no Siri phrase, and no `AppIntent` type other than the filter (R15). No Control Center or Lock Screen control.
  - Anything iOS lists for the filter on its own, for example in the Shortcuts app, is not suppressed by this spec. Whether it shows there, and whether it can be hidden without also leaving Focus settings, is settled in the spike (R14, Open questions).

  *(review: `project.yml` diff; `Core/Focus/` holds no other App Intents types)*

### Repo
- **R20** The amended specs get their notes in the implementation commit (see the list above). If R14 passes, CLAUDE.md Architecture gains one line for `Xpeet/Core/Focus/` (the only code that imports AppIntents). Then `evals/run.sh` and `scripts/check-bands.sh` are re-run (docs/ai-sdlc.md). `specs/break-reminder/spec.md` R16 changes the `Features/Speedometer/Trip/` line of the same section. The two edits touch different lines, so either can go first, and each re-runs the evals. *(review)*

## User flows & UI

**Turning clips off.** In gauge mode, tap the face button. In the sheet, scroll under the faces to "Sound" and turn "Engine sounds" off. A clip that is playing stops. The orange dot goes within 2 s. A mic chip behind the sheet goes away. Close with Done or a swipe. Nothing else on the speed screen changes.

**Turning clips back on.** Same place. Listening resumes at once, with the sheet still open:
- mic allowed: the dot returns;
- mic denied: the mic chip returns (if no higher chip);
- mic never asked (and location answered): the mic prompt appears over the sheet.

**Relaunch.** The switch keeps its last value.

**Focus filter (if R14 passes).** Settings › Focus › (e.g. "Passenger") › Focus Filters › Add Filter › Xpeet › "Engine sounds" › turn on "Turn off engine sounds". While that Focus is on, clips are off and the sheet shows the disabled switch with its note. When the Focus ends, the switch applies again. No mic prompt appears at that moment (R16).

| State | Sheet switch | Listening / mic indicator | Clip may play | Mic chip |
|---|---|---|---|---|
| **First launch** (switch on, location prompt pending; loading) | on | no | no | none |
| **On, mic not determined, location answered** | on | no; the mic prompt shows (engine-sound R2) | no | none |
| **On, mic allowed, stopped** (speed 0, `--` or Unavailable for any reason, Precise Location off included) | on | yes | yes, after the cooldown (engine-sound R6, R7) | none |
| **On, mic allowed, moving** | on | yes | no | none |
| **On, mic denied** (permission denied) | on | no | no | shown, last in the chip order (R11) |
| **On, listening failed** (error, engine-sound R12) | on | no, silently. Off then on retries once more (R9) | no | none |
| **Off** (any mic state) | off | no; dot clears ≤ 2 s | no; a playing clip stops (R5) | never |
| **Off, mic not determined** | off | no, and no prompt (R6) | no | none |
| **Focus override** (R16, optional) | off, disabled, note (R18) | no | no | never |
| **Stored value unreadable** (error) | on (R2) | as "On" rows | as "On" rows | as "On" rows |
| **App not active** | n/a | no (engine-sound R1) | no | n/a |

- **Empty state:** none. The sheet has no loading, empty or error state. The switch value is read synchronously at start.
- **Gauge and map mode:** the switch is reached from gauge mode only (osm-map R3). It applies in both modes, and the chip in map mode follows R11 (osm-map R3: same chip content).
- **Portrait and landscape:** the sheet is the same in both, and the "Sound" section scrolls into view under the grid. On the speed screen, the chip keeps its positions (ui-redesign R7): top row in portrait, bottom edge in landscape. When the mic chip goes away in landscape, the gauge gets back the chip's height, as with any chip.
- **Accessibility:** see R12–R13 and R18. VoiceOver strings: "Sound" (header); "Engine sounds" (switch, on/off); hint "Plays a short clip when the engine starts. Off stops the microphone." (or the Focus note while overridden); face button hint "Double-tap for gauge faces and engine sounds". Dynamic Type up to accessibility sizes in the sheet. Contrast ≥ 4.5:1 for the help line over every face (Accessibility Inspector). Reduce Motion: nothing new animates.

## Data & API
- **Where logic lives** (CLAUDE.md):
  - **`SpeedometerViewModel`** (`Features/Speedometer/SpeedometerViewModel.swift`) owns the stored switch, like `face` and `screenMode`:
    - `static let engineSoundsDefaultsKey = "engineSound.enabled"`;
    - `private(set) var engineSoundsOn: Bool`, read in `init` from the injected `defaults` (absent or not a Bool means true);
    - `func setEngineSounds(_ on: Bool)` saves it and forwards the effective value to `engineSound`;
    - `statusText`/`statusSymbol` keep the R11 order: location, then the break reminder (`specs/break-reminder/spec.md`), then `engineSound.chipText`.
  - **`EngineSoundViewModel`** (`Features/EngineSound/`, `@Observable @MainActor`) gains `private(set) var isEnabled = true` and a synchronous `handle(enabled:)`. It gates three places:
    - `chipText` (R7);
    - `requestMicIfReady()` (R6). The gate must be here and not only in `run()`, because `handle(locationAuthorizationResolved:)` runs on every location authorization update [R: codebase];
    - the start of listening in `run()`.
  - **Lifecycle:** off cancels the listening work (the events loop and the playback loop), and on starts it again, inside one `SpeedometerViewModel.run()`. The plan decides where that cancellable child lives. The researcher suggests a child task in `SpeedometerViewModel.run()`, keyed on the effective value. The existing `runCount` guard and the `.failed → .idle` reset already allow cancelling and restarting `EngineSoundViewModel.run()` within one session [R: codebase]. `SpeedometerView`'s `.task(id: scenePhase)` is unchanged.
- **`Core/Audio/`:** no change expected. Ending `events()` already stops the pipeline and deactivates the session. Deactivating with a clip still playing stops it and returns `isBusy`, which `AudioSession.deactivate()` already ignores (`try?`) [R: setActive]. The player's own cancellation hop is asynchronous, so either path stops the clip.
- **`FacePickerSheet`** (`Features/Speedometer/Faces/`) gains the "Sound" section inside its existing `ScrollView`, under the grid. It takes the switch value, the Focus override and a callback, and holds no logic. `SpeedometerView` passes them. It has previews for on, off, Focus override, and an accessibility text size.
- **Focus filter (only if R14 passes):** `Xpeet/Core/Focus/` is the only code that imports AppIntents. It mirrors `Core/Location`:
  - `EngineSoundsFocusFilter: SetFocusFilterIntent` (R15), in the app target;
  - `FocusFilterProvider` (`@MainActor` protocol): `updates() -> AsyncStream<Bool>` yields the current override first (from `current`), then each `perform()`;
  - the mapping from a `current` read (a value or an error) to the override is a pure function with no App Intents types, unit-tested directly (R17). `AppIntentsFocusFilterProvider` only calls it;
  - `AppIntentsFocusFilterProvider` (production) and `FakeFocusFilterProvider` (`#if DEBUG`);
  - `SpeedometerViewModel` gets it injected (`focusFilter: FocusFilterProvider? = nil`, production default), feeds `handle(focusOverride:)` from `run()`, and exposes `engineSoundsOffByFocus: Bool` for the sheet. Until a run's first value arrives, the override is unknown and engine sound stays off (R17). The sheet shows the stored switch until then.

  How `perform()` reaches the running provider (a main-actor relay) is decided in the plan.
- **Persistence:** one new `UserDefaults` key, `engineSound.enabled` (Bool). Existing keys are unchanged, and so is `trip.stretch` from `specs/break-reminder/spec.md`. The Focus value is not stored.
- **Offline:** fully offline. No network.
- **Tests:**
  - `XpeetTests/EngineSoundViewModelTests.swift` (gates; `testCancellingRunStopsEvents` is the pattern for R4; retry after failure, R9);
  - `XpeetTests/SpeedometerViewModelTests.swift` (persistence, chip order, off/on with `eventSubscriberCount`, Focus override and held-back first value with the fake);
  - `XpeetTests/GaugeFaceTests.swift`: the face button hint assertion changes to the R13 string. This spec is what allows that test change (CLAUDE.md Verification).

## Non-functional
- **Performance and battery:**
  - Off removes the mic and classifier cost (engine-sound Non-functional, to be measured once with the Xcode energy gauge).
  - Session activation and engine start/stop run on the main actor today, as on every return to the app. Toggling must not visibly stall the speed number (manual).
  - There are no new timers or polling: the Focus value is read once per `run()` plus each `perform()`.
- **Privacy:**
  - No new data leaves the device. The new stored data is one Bool. No new permission, and the mic usage string (`project.yml`) is unchanged.
  - Audio is still analysed in memory only (engine-sound R4).
  - With the filter, the app learns only its own filter's parameter, not which Focus is on, and does not store it.
- **Localization:** new strings via `String(localized:)`/`Text("…")`:
  - "Sound", "Engine sounds", "Plays a short clip when the engine starts. Off stops the microphone.";
  - "Double-tap for gauge faces and engine sounds";
  - Focus filter (if R14 passes): "Turn off engine sounds", "Turns Xpeet's engine sounds off and stops the microphone while this Focus is on.", "Engine sounds off", "Engine sounds unchanged", "Off while a Focus is on. Your choice applies again when it ends." (the filter title reuses "Engine sounds"; the App Intents strings are `LocalizedStringResource`).
- **Compatibility:** iOS 17 APIs only. `SetFocusFilterIntent` is iOS 16+. There are no `#available` branches.

## Out of scope
- Volume; importing clips; turning single clips on or off.
- A Siri or Shortcuts action, App Shortcuts, Control Center or Lock Screen control (R19). Hiding whatever iOS lists for the filter on its own, unless the spike finds a safe way (R14).
- Following the ring/silent switch. While the switch is on, clips still ignore it (engine-sound R9 session).
- Detecting passengers, the car, Bluetooth or CarPlay. Turning clips off by speed. Changing engine-sound R6 so `--` counts as moving.
- Off by default ("opt-in"): a distribution question (Flagged concerns).
- A settings screen, renaming the sheet ("Style & sound"), and any switch on the speed screen or in map mode.
- An App Intents extension, App Group or background delivery of Focus changes (researcher option C). `INFocusStatusCenter` (researcher option D: it adds a prompt).
- A switch for the break reminder (`specs/break-reminder/spec.md` Out of scope defers it), and mascot settings in the sheet.

## Flagged concerns
- **Privacy (owner):** no new permission, Info.plist usage string or entitlement. One new `UserDefaults` key, covered by the existing required-reason note (speedometer Flagged concerns). The switch reduces mic use. With the filter, the Focus value is held in memory only.
- **App Review 5.1.1 (not binding, personal build):** the default stays on, so the mic prompt still comes at first launch, not in context (engine-sound Flagged concerns). The switch makes an opt-in default possible. Choosing it is left to distribution. R6 already gives an in-context prompt when someone turns clips on with the mic never asked.
- **Mic indicator timing unverified:** Apple documents what the orange dot means but not when it clears [R: Apple Support 108331]. A third-party report saw it clear within about 1 s of stopping the engine and deactivating the session [R: dictus #430]. That is one device, not Apple. The 2 s targets (R8, R9) need a device measurement. Whether Control Center still lists Xpeet as "recently used" after the dot clears is unverified.
- **Focus filter order (owner decision):** the intent asked for the Focus device checks before the spec (intent Open questions, "Unverified … Check on the device before the spec"). The checks need a build that contains a filter, so this spec was written first and R14 turns them into a throwaway spike. The owner chooses one path:
  - (1) keep R15–R19 in this spec, built only after the spike passes;
  - (2) move R15–R19 to a follow-up amendment written after the spike, and ship R1–R13 now.

  Until the owner chooses, R15–R19 are provisional.
- **Background process launch (Focus filter):** with no extension, iOS may launch Xpeet's process in the background, without a scene, to run `perform()` [R: WWDC22 10032]. That is a system launch, not a background mode: there is still no `UIBackgroundModes`, and R17 limits such a launch to updating memory. Whether it happens at all is a device check (R14).
- **Focus filter feasibility (gate R14):**
  - Whether a free-team build lists the filter is undocumented, and there are past "app not listed" reports [R: forum 720662].
  - Whether Driving and Sleep offer third-party filters is undocumented. Apple names Do Not Disturb, "or another Focus" [R: Defining your app's Focus filter].
  - `perform()` is not guaranteed to reach an app that is not running and has no extension. The read of `current` on each `run()` covers this, but what `current` returns or throws with no active filter is undocumented.
  - Metadata extraction under XcodeGen is unverified.
- **CLAUDE.md and evals:** if R14 passes, R20 adds a `Core/Focus/` Architecture line. That needs owner approval plus an eval re-run (docs/ai-sdlc.md).
- **Spec amendments need owner sign-off:** engine-sound R1, R2, R10, R11, R12, the User flows table, Persistence and Out of scope; gauge-themes R10, R16, R17 and Out of scope; ui-redesign R18 and the States table; speedometer Data & API Persistence (listed at the top).
- **Sibling specs:** the chip order (R11) is the same list as `specs/precise-location/spec.md` R8 and `specs/break-reminder/spec.md` R10. The three can be built in any order; whichever ships later keeps the order in `statusText`. The older-spec rules shared with break-reminder (engine-sound R11 and its table, the ui-redesign States table, speedometer Persistence, CLAUDE.md) are noted where each is listed at the top.
- **Driving safety (App Review 1.4.4/1.4.5, not binding):** the switch lives in the sheet only and can be used while moving, like face changes (gauge-themes Flagged concerns). Nothing on the live screen needs a tap, and a Focus ending never brings up the mic prompt (R16). Clips still may play while the reading is `--` (engine-sound R6). The switch is the user's way out, and the rule itself is out of scope.
- **No security or payments impact.**
- **Unverified locally:** the simulator uses the Mac mic and cannot show the iPhone mic indicator. R5, R8–R10 and R14–R18 need the owner's device.

## Open questions
Carried from the intent (proposals accepted by the owner, 2026-10-30; unverified items stay open):
- *Where in the sheet?* **Answered (owner, 2026-10-30):** a "Sound" section under the 2×2 grid with the help line, and the title stays (R1). **Answered (simulator, 2026-10-31):** on iPhone SE at medium height, the section is reached by scrolling past both thumbnail rows; in landscape the sheet opens full height and it is one scroll down (plan.md Checks).
- *Wording?* **Answered (owner, 2026-10-30):** "Engine sounds", matching the mic chip and usage string, so the chip text is unchanged (R1, R11).
- *Mic not asked yet?* **Answered (owner, 2026-10-30):** no prompt while the switch is off, and the prompt comes when it is turned on (R6). The default stays on (R2). **Still open (distribution):** off by default, "opt-in" (Flagged concerns).
- *Mic chip while on and denied?* **Answered (owner, 2026-10-30):** kept (R11). Turning the switch off hides it (R7).
- *Focus filter (optional)?* **Answered (owner, 2026-10-30):**
  - a filter that turns clips off while a chosen Focus is on;
  - the sheet says so, and the switch applies again when the Focus ends (R15–R18);
  - App Intents in the app target, no extension, the value read whenever the app becomes active, no background mode (R17);
  - a CLAUDE.md line (R20).

  **Partly answered (2026-10-31):** `Metadata.appintents` is in the XcodeGen-built `.app` and lists the filter (gate b). The owner chose to build R15–R19 before the device check (plan.md Deviations), so the rest are checked on the device after install.

  **Still open (device checks):**
  - Does a free-team build list Xpeet under Add Filter?
  - Do Driving and Sleep list it?
  - Is `perform()` ever delivered while Xpeet is not running, and does that launch the process in the background?
  - What does `current` return or throw with no active filter?
  - How long does reading `current` take when the app becomes active? Can it hang (R17)?
  - Does the filter show up as a Shortcuts action, and can it be hidden there without also leaving Focus settings (R19)?
- *Out of scope list?* **Answered (owner, 2026-10-30):** see Out of scope.
- *Measurable targets?* **Still open (to be measured on a device):**
  - mic indicator cleared ≤ 2 s after off, back ≤ 2 s after on;
  - a 10-minute off session with no clip and no indicator (R8, R9).

Raised by this spec (defaults chosen here; the owner may change them in review):
- *Off mid-clip and the cooldown:* the cut-off clip counts as started, so turning on again within 60 s plays nothing until the cooldown ends (R5). This is today's R7 behaviour on leaving the app.
- *Spike or follow-up:* keep R15–R19 here behind the R14 spike, or move them to a follow-up amendment and ship R1–R13 now (Flagged concerns).
- *Focus value not yet known:* counts as off until the first read of a run (R17), so the mic never starts for a moment under a filtered Focus.
- *Focus ends with the mic never asked:* no prompt then. The request waits for the next start of the speed screen or the switch (R16).
- *Toggle after a listening failure:* off then on retries (R9, amends engine-sound R12).
- *Focus vs switch:* the Focus wins until it ends (intent). While overridden, the switch shows off and disabled with a note (R18), rather than showing the stored choice.
- *Focus parameter default:* false ("no change"), so the Focus ending resets it (R15). The cost is one extra tap when adding the filter.
- *Face button hint:* "Double-tap for gauge faces and engine sounds" (R13). The intent said it "may need to mention sound".
- *Help line as the VoiceOver hint* rather than a separate element (R12).
- *Storage key name:* `engineSound.enabled` (R2).

Sources (researcher, 2026-10-30):
- [SetFocusFilterIntent](https://developer.apple.com/documentation/appintents/setfocusfilterintent), [current](https://developer.apple.com/documentation/appintents/setfocusfilterintent/current), [SetFocusFilterIntentError](https://developer.apple.com/documentation/appintents/setfocusfilterintenterror)
- [Defining your app's Focus filter](https://developer.apple.com/documentation/appintents/defining-your-app-s-focus-filter), [WWDC22 10121](https://developer.apple.com/videos/play/wwdc2022/10121), [WWDC22 10032](https://developer.apple.com/videos/play/wwdc2022/10032/)
- [Forum 766761](https://developer.apple.com/forums/thread/766761), [Forum 720662](https://developer.apple.com/forums/thread/720662)
- [Apple Support 108331](https://support.apple.com/en-us/108331), [AVAudioSession setActive](https://developer.apple.com/documentation/avfaudio/avaudiosession/setactive(_:options:)), [AVAudioApplication.requestRecordPermission](https://developer.apple.com/documentation/avfaudio/avaudioapplication/requestrecordpermission(completionhandler:))
- [dictus-ios #430](https://github.com/getdictus/dictus-ios/issues/430) (third-party)
