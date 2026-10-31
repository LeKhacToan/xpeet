# Intent: Say when Precise Location is off

**Owner:** toanlk  **Status:** accepted

## Problem
iOS lets me give Xpeet my location with Precise Location off. The switch is on the first location prompt, and in Settings › Xpeet › Location. With it off, iOS sends only rough positions, far too coarse to measure speed, and as far as I can tell no speed at all. I found this by reading the code; I have not driven with Precise Location off yet (see Open questions).

The app never reads this setting, so it fails without saying why:
- The speed shows "--" and the chip says "Searching for GPS…" for the whole drive, exactly like a tunnel. I would wait for a signal that never comes.
- A fix with no speed is ignored (speed-accuracy R13), and a rough position is no use for anything else.
- The trip line freezes and nothing is measured. The trip is not even marked approximate, so afterwards it just looks shorter.
- The map shows its placeholder, or a dimmed marker at the last precise position. The trail stops growing.
- If iOS ever marks a rough fix as stationary, it is worse: the screen shows 0 and stays on 0 after I drive off.

## Proposed outcome
- When location is allowed but Precise Location is off, the speed shows "--" and the status says **"Precise Location is off"**, not "Searching for GPS…".
- The existing **"Open Settings"** button shows, with one line under it saying where to switch it on, e.g. "Turn on Precise Location under Location to see your speed".
- Rough fixes are never used. They move nothing: not the number, the trip, the trail or the map marker.
- It clears by itself. When I come back from Settings with Precise Location on, the status goes and the speed returns with the next fix, with no relaunch.
- "Location Services is off" and "Location access is off" keep their own messages. This one shows only when location is allowed.
- VoiceOver reads the status and the hint like the other location messages.
- **Measurable:**
  - Opening the app with Precise Location off shows this status within 1 s, in place of "Searching for GPS…".
  - While it shows, the trip's distance, moving time and stopped time do not change, and no route point is added.
  - With Precise Location on, the screen behaves exactly as today.

## Affected users & systems
- Users: me (personal use, sideloaded).
- Screens: the speed screen in gauge and map mode: the status chip, "Open Settings" and its hint line, and the mascot in gauge mode. No new screen.
- System: `Xpeet/Core/Location/` reads the accuracy setting next to the permission it already reads. No new permission and no new Info.plist key.
- Specs this changes:
  - `specs/speedometer/spec.md`:
    - R17: a fourth reason and third message, "Precise Location is off", with "Open Settings" (today only the denied case has the button). The states table's Unavailable row gains it.
    - R18: the screen also recovers with no restart when Precise Location comes back on.
    - Data & API: `SpeedProvider` also reports whether Precise Location is on, with changes over time.
  - `specs/speedometer-gauge/spec.md`: R6 none if it keeps the Unavailable icon `location.slash` (proposed). The States table and the portrait layout: "Open Settings" also when Precise Location is off.
  - `specs/ui-redesign/spec.md`:
    - R4: `sad` also shows while Precise Location is off (if it counts as Unavailable).
    - R17: "Open Settings" is no longer denied-only, and this case gets its own hint line.
    - States table: a new row "Unavailable, Precise Location off": chip "Precise Location is off", `--`, `sad`, Open Settings with its own hint.
  - `specs/osm-map/spec.md`: R3 and the States table: "Open Settings" also shows when Precise Location is off. R5, R9: none if this counts as Unavailable (placeholder, no marker); they change only if it counts as Acquiring.
  - `specs/trip-stats/spec.md` R1, R11: no wording change if this counts as Unavailable (see Open questions).
  - `specs/engine-sound-clip/spec.md`: none. R11 holds (location status first).
  - `specs/speed-accuracy/spec.md`: none. Rough fixes never reach the estimate.

## Constraints
- iOS 17+, Apple frameworks only, no new permission, no networking, nothing new stored.
- Foreground only, as today (speedometer R20).
- Nothing to tap while driving. The status is read-only, and "Open Settings" is for when I am parked. No sound, haptic or alert for this status.
- The chip follows the existing chip rules: Dynamic Type, contrast on every face, the reserved top row in portrait (ui-redesign R7).

## Decisions
The owner accepted every proposal in Open questions (2026-10-30). Items marked unverified or to be measured stay open for the spec.

## Open questions
- **Unavailable or Acquiring?** Proposed: Unavailable, with its own reason. Nothing can be measured until I change a setting, so it is closer to "location off" than to a tunnel: the trip line and trip sheet are hidden, nothing is measured, the map shows its placeholder, the mascot is `sad`. Acquiring would keep the trip line, the sheet, the dimmed marker and the `searching` mascot, but suggests the signal may come back on its own.
- **Ask for precise location just this once?** iOS has a prompt that grants precise location for the session, until I leave the app (`requestTemporaryFullAccuracyAuthorization`). Proposed: out of scope. It would ask on every launch, which can mean a tap while driving, and it needs its own Info.plist text. Speed-accuracy, trip-stats and osm-map all ruled out new prompts.
- **Engine clip.** Proposed: no change. engine-sound R6 already treats every Unavailable reason as stopped, so a clip may play, as with location denied. Turning clips off is `intent/2026-10-30-engine-clip-toggle.md`.
- **Chip order.** Only one chip shows at a time. Proposed: this is a location status, so it ranks with "Searching for GPS…", "Weak GPS signal" and the location-off messages: above the break reminder (`intent/2026-10-30-break-reminder.md`, which proposes location statuses first) and above the mic chip (engine-sound R11). It says the number cannot be trusted, which matters more than a break.
- **What iOS sends.** I have not recorded a drive with Precise Location off. Proposed: record one (speed-accuracy R22) to confirm the fixes carry no speed, and see how often they come. The status itself does not depend on the answer.
- **Out of scope:**
  - an onboarding screen;
  - any use of the rough positions (e.g. a rough marker on the map);
  - marking the trip approximate for time with Precise Location off; the status is the warning.
