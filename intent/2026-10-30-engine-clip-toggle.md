# Intent: Turn the engine-start clip on or off

**Owner:** toanlk  **Status:** accepted

## Problem
The engine-start clip cannot be turned off. When I start or rev the engine with the app open, "おはよう、おにいちゃん！" or "Vroom vroom! Let's go!" plays through the phone speaker or the car audio. With passengers that is awkward. The ring/silent switch does not silence it. My only ways out are turning the volume down, which also mutes my music, or denying the microphone in iOS Settings. Then the chip "Microphone off: enable it in Settings to hear engine sounds" shows whenever there is no location status.

With location off, or once a tunnel drops the speed to "--", the clip can even play while I drive. Engine-sound R6 counts that as stopped.

The mic also runs the whole time the speed screen is open and active, in both modes and with sheets open. iOS shows the orange mic indicator all that time, and I pay the battery cost of the mic and the sound classifier even when I don't want clips.

Every earlier doc deferred the switch, and none rejected it: the engine-sound intent and spec (R1, Out of scope, Open questions) and gauge-themes Out of scope. The engine-sound spec even wants "an opt-in toggle" before any distribution.

## Proposed outcome
- **One switch:** "Engine sounds" (wording: Open questions) in the gauge style sheet that the face button opens. It is on by default, so nothing changes until I turn it off.
- **Off means off:**
  - no clip plays, and a clip already playing stops at once;
  - the app does not listen at all: the microphone and the sound classifier stop, and the orange mic indicator goes away, as it does when I leave the app;
  - no mic chip, even if the mic is denied.
- **On again:** listening resumes at once, without relaunching the app or closing the sheet. Today's rules apply again: clips only while the speed shows 0 or no reading (R6), 60 s cooldown, no self-trigger.
- **Remembered:** the choice survives a relaunch.
- **Nothing else changes:** the switch never touches the speed, unit, face, map mode, trip or location chips.
- **Accessible:** a standard switch that VoiceOver reads by name and state ("Engine sounds, off"). It follows Dynamic Type like the rest of the sheet.
- **Measurable:**
  - With the switch off, a 10-minute session with engine starts and revs plays no clip and never shows the mic indicator.
  - Switching off clears the mic indicator within 2 s. Switching on (mic allowed) brings it back within 2 s, and a start while the speed shows 0 plays a clip.
  - With the mic denied, the mic chip disappears as soon as the switch is off.

## Affected users & systems
- Users: me (personal use, sideloaded).
- Screens:
  - the gauge style sheet (`Features/Speedometer/Faces/`) gets one switch. No new screen, and still no settings screen;
  - the speed screen: the mic chip shows only while the switch is on. It stays last in the chip order (engine-sound R11), as the break reminder and Precise Location intents also propose;
  - map mode hides the face button (osm-map R3), so I reach the switch from gauge mode. Clips follow it in both modes.
- Data: one more on-device setting, so engine-sound "Persistence: none" changes.
- System: no new permission, and the mic usage string stays. The optional Focus filter would add an "Xpeet" choice under Settings › Focus › (a Focus) › Focus Filters › Add Filter.
- Specs this changes:
  - `specs/engine-sound-clip/spec.md`:
    - R1 (listening also needs the switch on; "no toggle" goes), R11 (chip only while on), and R2 only if the prompt waits for the switch;
    - User flows table: a new "Clips off" row. Out of scope: "an on/off toggle" goes;
    - Localization: the switch strings, if the plan puts them here.
  - `specs/gauge-themes/spec.md`:
    - R10 (sheet contents), R16 (VoiceOver) and R17 (sheet Dynamic Type) gain the switch and its help line. The face button hint "Double-tap to choose a gauge face" may need to mention sound;
    - Localization gains their strings;
    - Out of scope: "engine-sound settings in the sheet" moves into scope.
  - `specs/ui-redesign/spec.md`: R18 (sheet layout) gains the switch. In the States table, the "Live, mic denied" row applies only while clips are on.
  - `specs/speedometer/spec.md`: none. R20 (foreground only) and "no settings screen" stay.

## Constraints
- iOS 17+, SwiftUI, Apple frameworks only, no networking.
- Foreground only: no `UIBackgroundModes` (speedometer R20, engine-sound R1), for the Focus filter too.
- Driving safety: nothing on the live screen needs a tap. The switch lives in the sheet only, with no new button or indicator on the speed screen. Like face changes (gauge-themes R11), it works in every state, including while moving. It is not locked.
- Must not encourage speeding: the switch has nothing to do with speed. No speed sounds, alerts or haptics. R6 (no clip while the displayed speed is above 0) stays.
- Permission: no prompt beyond today's single mic prompt (R2). iOS never asks again once I answer, so switching on with the mic denied only brings the chip back.
- Privacy unchanged: audio is analysed in memory only (R4), and the setting stays on the device.

## Decisions
The owner accepted every proposal in Open questions (2026-10-30). Items marked unverified or to be measured stay open for the spec.

## Open questions
- **Where in the sheet?** Proposed: a "Sound" section under the 2×2 grid with one help line: "Plays a short clip when the engine starts. Off stops the microphone." The title stays. At medium height the grid may fill the sheet, so check on iPhone SE how much scrolling that needs. The alternative is renaming the sheet, e.g. "Style & sound".
- **Wording.** The mic chip and the mic usage string say "engine sounds". Proposed: name the switch "Engine sounds" to match. With "Engine clips", the R11 chip text would change to "…to hear engine clips".
- **Mic not asked yet.** The mic prompt comes automatically at first launch, right after location (R2), before I can open the sheet. Proposed: if the switch is ever off while the mic is still "not determined", there is no prompt until I turn it on. The default stays on, so first launch is unchanged. Off by default (the spec's "opt-in") is a question for distribution, not now.
- **Mic chip while on and denied.** Proposed: keep it, since I want clips and they can't work. Turning the switch off is now the way to hide it.
- **Focus filter (optional).** Proposed: an Xpeet Focus filter that turns clips off while a Focus I choose is on (e.g. a custom "Passenger" Focus). The sheet says so. When the Focus ends, my switch applies again.
  - Feasibility: App Intents (`SetFocusFilterIntent`, iOS 16+) in the app target. With no extension, the app hears of a Focus change only while running, so it also reads the filter whenever it becomes active. No background mode. It would be the app's first use of App Intents, so CLAUDE.md Architecture needs a one-line update (owner approval plus an eval re-run, docs/ai-sdlc.md).
  - Unverified: whether the built-in Driving Focus offers Focus filters (custom Focuses do), and whether a build signed with a free account shows the filter. Check on the device before the spec.
- **Out of scope:** volume; importing clips; switching single clips on or off; a Siri/Shortcuts action, Control Center or Lock Screen control; detecting passengers, the car, Bluetooth or CarPlay; turning clips off by speed.
