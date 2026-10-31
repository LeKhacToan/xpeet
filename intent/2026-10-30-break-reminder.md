# Intent: Remind me to take a break on long drives

**Owner:** toanlk  **Status:** accepted

## Problem
On long drives I lose track of time. I only notice how long I have been at the wheel once I am already tired. Common road-safety advice, such as the UK Highway Code, is a break of at least 15 minutes every 2 hours.

Xpeet already counts moving and stopped time for each trip (`specs/trip-stats/spec.md` R1), but nothing tells me it is time to stop.

## Proposed outcome
- **The reminder.** After about 2 h of driving without a real rest, the status chip shows a calm line with a cup icon: "2 h driving · time for a break".
  - If I keep going, the hours count up ("3 h driving"). Nothing else escalates: no colour change, no flashing, no bigger text.
  - It uses the same chip as the other statuses and has no colour of its own: the face's chip text colour, with the icon and dot in the face's accent like every chip. Nothing about it changes with time or speed.
- **Silent and hands-free.** No sound, haptic or notification, and nothing to tap or dismiss.
- **It clears by itself** once I have rested: 15 min stopped with the app open, or more than 30 min since the last movement with the app closed in between (the rule that starts a new trip, trip-stats R6). A shorter closed gap neither adds drive time nor counts as a rest.
- **Time only.** Drive time is moving time plus short stops (lights, jams), measured as the trip measures it. Speed never changes when the reminder comes, what it says or how it looks.
- **Everywhere the chip is:** gauge and map mode, portrait and landscape, every face. A call, Control Center or a short lock does not reset the count.
- **Measurable:**
  - The reminder shows within a second of reaching 2 h of drive time, never before.
  - It goes within a second of 15 min stopped.
  - The same timeline at 30 km/h and at 120 km/h brings it at the same moment.
  - Closing and reopening the app within 30 min keeps the drive time, losing at most the last 10 s.
  - Zero sounds, haptics and taps.

## Affected users & systems
- Users: me (personal use, sideloaded).
- Screens: one new status chip message, shorter than the mic hint. In portrait the top row is reserved, so nothing moves. In landscape the gauge gives up the chip's height while it shows, as with "Weak GPS signal" (ui-redesign R7). No new screens, buttons or settings.
- Data: the current driving stretch, on the device: when it started, how much of it was driving, and when I last moved. Times only, no positions.
- Specs this changes:
  - `specs/engine-sound-clip/spec.md` R11 and User flows table, `specs/speedometer-gauge/spec.md` R6 (icons) and States table, `specs/ui-redesign/spec.md` States table: the reminder chip and its place in the chip order.
  - `specs/speedometer/spec.md` Out of scope "over-speed alerts, speed-based colours or sounds", `specs/speedometer-gauge/spec.md` R3 and `specs/gauge-themes/spec.md` R7 ("no alerts"): a note that this reminder is a time-based, silent status, not a speed alert, as the engine-sound spec did for its clip.
  - `specs/ui-redesign/spec.md` Out of scope "the AI co-pilot text": see Open questions.
  - `specs/speedometer/spec.md` and `specs/trip-stats/spec.md` Non-functional Privacy: the stretch's times are stored on the device. Trip-stats Data & API gains one key. R9 (what a trip stores) stays as is if the stretch is kept beside the trip ("New trip" below).
  - `specs/osm-map/spec.md` R25: "Delete all trips" also clears the stretch. R3 needs nothing: the map's chip already shows the same content.

## Constraints
- **Must not encourage speeding:** the reminder is about time, never speed. Its only speed input is the trip's moving/stopped line (1 km/h). No speed alerts, top speed, records or streaks, no count of breaks and no praise for resting.
- **Driving safety:** nothing to tap (no dismiss, no snooze), and no spoken reminder. It would be the first sound meant for a moving car (the engine clip is kept to when the reading is 0 or missing, engine-sound R6).
- Foreground only, as today (speedometer R20): no `UIBackgroundModes`, no notifications, no new permission. iOS 17+, Apple frameworks only, no network.
- **Honest limits:** the app measures only while it is open. Driving with the app closed is not counted, so the reminder can come late, and a short closed gap never counts as a rest. Time with no reading ("--", location off) is not counted either. It is a nudge, not a fatigue detector.
- Accessibility as for the other chips: the icon is hidden from VoiceOver, the text is read, Dynamic Type follows the chip's cap.
- Battery: no new sensors or timers.

## Decisions
The owner accepted every proposal in Open questions (2026-10-30). Items marked unverified or to be measured stay open for the spec.

## Open questions
- **Thresholds.** Proposed: 2 h of drive time, and 15 min stopped as a rest, as in the advice above.
- **What counts as driving.** Proposed: moving time plus stops shorter than a rest, so a jam still counts. Moving time alone would let a long jam push the reminder back.
- **Rest with the app closed.** Proposed: more than 30 min since the last movement (trip-stats R6), so a trip that starts on its own always comes with a fresh count. The catch: a 20 min coffee stop with the phone locked doesn't count. The app could tell only by comparing where I left with where I came back, and this intent keeps the stretch to times only. Proposed: don't compare positions for now. To have the stop count, I leave Xpeet open.
- **No reading with the app open** (tunnel, underground car park, location or Precise Location off). The trip measures nothing then (trip-stats R1), so this time is neither driving nor rest. Proposed: when a reading comes back, apply the closed-gap rule: more than 30 min since the last movement counts as a rest, and a shorter gap adds nothing.
- **Does "New trip" reset the count?** Proposed: no. A rest is about me, not the trip, so the stretch is stored beside the trip.
- **The co-pilot exclusion.** ui-redesign Out of scope lists "the AI co-pilot text" (the Stitch bubble "Slow down a bit, pilot!"), left out as an extra feature that "can be its own intent later". This reminder is not that bubble: one fixed status line, timed only, saying nothing about speed. Proposed: a note in that line that the break reminder is a status, and the co-pilot stays out.
- **Chip priority.** Only one chip shows at a time. Proposed:
  - location statuses first ("Searching for GPS…", "Weak GPS signal", location off, Precise Location off), because they say whether the number can be trusted;
  - then the reminder;
  - then the mic hint.

  `intent/2026-10-30-precise-location.md` ranks its status with the location messages, so it also comes before the reminder. The catch: a long "Weak GPS signal" stretch hides the reminder. Proposed: accept, because the drive time still counts and the reminder shows as soon as the signal recovers.
- **VoiceOver.** Proposed: no announcement. VoiceOver reads the chip when it is focused, like every other status.
- **Mascot.** Proposed: no reaction. Its sleepy face already means "stopped".
- **Off switch.** Time riding as a passenger counts as driving too. Proposed: no switch for now. Revisit with `intent/2026-10-30-engine-clip-toggle.md`, which adds the app's first on/off switch.
- **Out of scope:**
  - a spoken or sound reminder, haptics, notifications;
  - a reminder on Apple Watch, CarPlay, the Lock Screen, a Live Activity or a widget;
  - any longest-stretch or hours-without-a-break figure: the count shows only while the reminder is up, and a finished stretch is not kept;
  - a "Driving since" line in the trip sheet: it can disagree with the chip after a closed gap;
  - detecting tiredness, suggesting a place to stop, any history of breaks.
