# Intent: Trip statistics

**Owner:** toanlk  **Status:** accepted

## Problem
The app shows only the speed right now. After a drive I want to know how far I went, how long I was moving, how long I sat in traffic, and my average speed. Today I have to read the car's trip meter, reset it myself, and work out the rest by hand.

Every earlier spec deferred this:
- `specs/speedometer/spec.md` Out of scope lists "trip statistics (max, average, distance, time)".
- `specs/ui-redesign/spec.md` lists "trip distance, peak or top speed".
- `specs/speed-accuracy/spec.md` lists "trip statistics".

Since speed-accuracy shipped, the speed estimate is good enough to build on.

## Proposed outcome
- **Live, at a glance:** while driving, the screen shows a small line with the current trip's **distance** and **moving time**, e.g. "12.4 km · 18 min". It is smaller than the speed and never competes with it.
- **Details:** tapping that line opens a trip sheet with:
  - distance;
  - moving time and stopped time (traffic lights, jams);
  - total time;
  - average moving speed (distance / moving time);
  - when the trip started.
- **Units:** distance follows the speed unit: km with km/h, mi with mph. Switching unit converts at once.
- **New trip:**
  - a "New trip" button in the sheet starts a new trip at any time;
  - a new trip also starts on its own when I open the app after a long break (proposed: 30 min with no movement).
- **Survives interruptions:** a call, Control Center or locking the phone briefly does not end the trip. While the app is closed, nothing is measured; the trip pauses and resumes.
- **History:** the last few trips (proposed: 10) are kept as totals only: date, distance, times and average speed. No route and no coordinates.
- **Measurable:**
  - On my recorded drives (specs/speed-accuracy), the trip distance is within **2%** of the distance from GPS positions over the same stretch, for any drive of at least 5 km.
  - Moving time and stopped time add up to the time the app was measuring, within 1 s.

## Affected users & systems
- Users: me (personal use, sideloaded).
- Screens:
  - the speed screen gets one new small line;
  - one new modal sheet for trip details and history;
  - still no navigation and no tabs.
- Data: a small local store for the current trip and the trip history (totals only).
- Specs this changes:
  - `specs/speedometer/spec.md`:
    - R1 ("no other screen", already amended for the face picker): a second modal sheet is allowed.
    - Out of scope "trip statistics": now in scope, except top speed (see Constraints).
    - Non-functional "location ... never stored": trip totals are stored, but never positions.
  - `specs/ui-redesign/spec.md`: the layout must make room for the trip line in portrait and landscape, without shrinking the gauge below what "199" needs, and without moving the mascot or status chip rules.
  - `specs/speed-accuracy/spec.md`: none. Trips reuse its estimate and its recorded drives for testing.

## Constraints
- iOS 17+, native SwiftUI, Apple frameworks only, no networking, no new permissions.
- Foreground only, as today (speedometer R20). No background location just to keep counting distance.
- Privacy: no route, no coordinates and no addresses are stored, only totals. Nothing leaves the phone. *(Superseded by `intent/2026-10-27-osm-map.md`: routes are stored on the device, and map tiles are fetched from OpenStreetMap.)*
- **Must not encourage speeding:**
  - no top or peak speed;
  - no records, streaks or "fastest trip";
  - no speed-based colours;
  - average speed is shown as a plain number, never ranked or praised.
- Driving safety: nothing needs a tap while driving. The trip line is read-only on the main screen. Resetting happens in the sheet.
- The trip line follows Dynamic Type and VoiceOver ("Trip: 12.4 kilometres, 18 minutes moving") and every face's contrast rules.
- Battery: no extra sensors, and no work beyond adding up the speed the app already has.

## Decisions
The owner accepted the proposed answers (2026-10-26).
- **Top speed:** left out (see Constraints).
- **Trip end:** a new trip starts on opening the app after 30 min with no movement, or on "New trip".
- **GPS gaps:** while the reading is still shown with "Weak GPS signal", the shown speed counts toward distance. Once it is "--", nothing counts. The trip is marked "approximate" if more than a set share of its moving time was lost this way.
- **History:** the last 10 trips, totals only, in the trip sheet.
- **Landscape:** the trip line stays visible, to the right of the gauge, mirroring the mascot on the left. The gauge keeps the size "199" needs. (Changed 2026-10-26: the Stitch design showed there is no room for both the status chip and the trip line at the bottom edge.)
- **Mascot:** no reaction to trips.

## Open questions
- Out of scope for now:
  - exporting trips;
  - fuel or cost estimates;
  - odometer calibration against the car;
  - Live Activity (needs background location);
  - CarPlay.
