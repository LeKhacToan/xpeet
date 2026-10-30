# Spec: Map with OpenStreetMap

**Intent:** intent/2026-10-27-osm-map.md  **Status:** approved

This spec adds a **map mode** to the speed screen. It shows OpenStreetMap raster tiles under a marker that follows the car, with the speed always on screen. It also draws the **trail** of the current trip, keeps the **route** of every trip in the trip history, and lets me look at past routes and delete trips. Tiles are the app's first network use. Routes are the first positions it stores.

Design: Stitch project `2676886462094675705` ("Xpeet Anime Speedometer", design system "Nocturne Precision"). The frames are saved in `specs/osm-map/design/` and are all shown on the Minimal ring face. Where a frame and this spec differ, this spec wins.

| Frame | File | Stitch screen |
|---|---|---|
| Map mode, portrait, Live and following | `map-portrait.jpg` | `04156369adfb4480bb5c36af2788fad9` |
| Map mode, landscape, weak-signal chip at the bottom | `map-landscape-weak-signal.jpg` | `67b36536dfa246ea9f18554e3c65e284` |
| First-map notice banner (R2) | `map-notice.jpg` | `dbed019a50af475f8c77db4c673980ca` |
| Searching for GPS, not following, tiles missing, "Map offline" | `map-offline-not-following.jpg` | `8f47f82ead304994b7c1e29068a7af1a` |
| Trip sheet: rows with chevrons, one row swiped to Delete, "Delete all trips" | `trip-sheet-delete.jpg` | `0720287dc4e743d184a57175c71050b0` |
| Route view of an earlier trip, approximate, with a gap | `route-view.jpg` | `92ec0b793ff04e90bf4eb3c538bd51f0` |

What the frames settle (R3):
- **Portrait:**
  - the speed card spans the width near the bottom, with the digits leading and the unit pill trailing;
  - the trip line sits directly under the speed card;
  - the status chip is top centre, in the row with the mode button;
  - the re-centre button is bottom trailing, above the credit;
  - the credit is bottom trailing, just above Apple's "Legal".
- **Landscape:**
  - the speed card is on the leading side, vertically centred, with the unit pill under the digits;
  - the trip line sits under the speed card;
  - the status chip is centred on the bottom edge;
  - the credit is bottom trailing.
- **Notice banner:** a full-width card under the top button row, with the "OK" button trailing.

Known differences, where the spec wins:
- **Map content:** the frames draw an invented street map. The app shows real OSM tiles.
- **Fonts:**
  - in the offline frame, "--" is drawn as two bars; the app shows "--" in the face's number font;
  - the landscape frame's digits are light; the app uses the face's number font (R3).
- **Route view extras:** the "GPS SIGNAL LOST" badge and the "N" compass are not part of the design. A gap is only a break in the line (R17, R23), and Apple's "Legal" link must stay visible (R14).
- **Landscape credit:** it is faint and has no backing; the app gives it a legible backing (R14).
- **Trip sheet:**
  - the swipe action is the system "Delete", not "DELETE";
  - "Delete all trips" is cut off at the frame's bottom edge; it sits under the history (R25).
- **Gauge mode:** no frame shows the map button there. It mirrors the face button at top leading (R1). Stitch updated the gauge screen `25e56725f1184a5fbe872019cf0ed8c0`, but its screenshot was not regenerated.
- **Faces and chrome:**
  - other faces use their own theme tokens; the map itself is the light style on every face (R33);
  - the phone mock-up and the status bar are not part of the design.

Research (researcher agent, 2026-10-27):
- OSMF Tile Usage Policy, https://operations.osmfoundation.org/policies/tiles/ (last changed 2025-12-19).
- OSMF Attribution Guidelines.
- Apple's MapKit docs: `MapContent` has no tile overlay; `MKTileOverlay`, `canReplaceMapContent`; HIG Maps.
- Apple's App Privacy Details.
- App Review Guidelines 5.1.1, 5.1.2, 5.1.5.

Changes to earlier specs (each gets a note when this ships):
- `specs/speedometer/spec.md`:
  - **R1** amended: the speed screen has a map mode, and the trip sheet gets a route view. Still no tabs.
  - Data "No network": map tiles over HTTPS are the one exception (R10–R13 here).
  - Non-functional "Offline: fully offline by design": everything except the map tiles still works offline.
  - Non-functional "Location … is never stored, logged or sent anywhere": routes are stored on the device (R16–R21). Tile requests show the server the area being viewed (R11).
  - The location usage string is replaced (R28).
- `specs/ui-redesign/spec.md` R7/R8: the map-mode button sits top leading in both modes. In map mode, the face button and the mascot are hidden (R3).
- `specs/trip-stats/spec.md`:
  - **R9**: a trip also has an `id`. Its route is stored in a separate file (R20).
  - **R14**: history rows open a route view and can be deleted, and "Delete all trips" is added (R22–R25).
  - Out of scope: "Route, map or position history" and "deleting single history entries" move into scope.
- `specs/speed-accuracy/spec.md`: no change. Map data never feeds the estimate (R29).

## Requirements

### Map mode
- **R1** **Switching modes.**
  - A **mode button** switches the speed screen between gauge mode and map mode.
    - It is a 44 pt glass circle, top leading, mirroring the face button (ui-redesign R8), in both modes and both orientations.
    - Its glyph shows the mode it switches *to*: a map in gauge mode, a gauge in map mode.
  - The chosen mode is stored in the injected `UserDefaults` under `screenMode` and restored at launch.
  - The default is gauge mode, so no tile is ever fetched until I choose the map.
  - Switching changes nothing else: the reading, unit, state, trip, recording and engine sound carry on.

  *(unit: mode persistence and default; manual: button)*

- **R2** **First-map notice.**
  - The first time any map is shown (map mode or a route view, R23), a banner appears over the map: "Map tiles come from OpenStreetMap. Their servers can see the area you are viewing." with an "OK" button.
  - The map works under the banner. "OK" dismisses it for good and sets `map.noticeAccepted` in `UserDefaults`.

  *(unit: flag; manual)*

- **R3** **Map-mode layout** (frames `map-portrait`, `map-landscape-weak-signal`; placements under Design).
  - The map fills the whole screen, under the safe areas.
  - Over it:
    - a **speed card**: the current reading (digits, or "--" when not Live), the face's number font and colours, and the unit pill (ui-redesign R15), which toggles the unit as in gauge mode. The digits are the largest text on screen: at least 64 pt in portrait and 56 pt in landscape;
    - the **status chip**: same content and position rules as gauge mode (top centre in portrait, bottom edge in landscape; ui-redesign R7);
    - the **trip line** (trip-stats R11, R13), which still opens the trip sheet;
    - the mode button (R1), the re-centre button (R8), the credit and the offline label (R13–R14);
    - "Open Settings" when location is denied (speedometer R17). **Amended** by `specs/precise-location/spec.md` R5: also when Precise Location is off.
  - Not shown in map mode: the gauge, the mascot and the face button. To change face I switch back to the gauge.
  - Overlays never cover the credit, Apple's logo or the "Legal" link.

  *(manual: frames, every face, both orientations, largest text size)*

- **R4** **Contrast over any map.**
  - Overlay cards in map mode have an opaque backing in the theme's colours, so map tiles never show through behind text.
  - Speed digits reach at least 7:1 against their backing, and secondary text at least 4.5:1, on every face (gauge-themes R8 targets).

  *(unit: contrast of the theme tokens against the card fill; manual)*

### Following the car
- **R5** **Marker.**
  - The app draws the marker itself, at the position of the latest accepted fix (the same fixes that move the speed). It does not use MapKit's own user-location view, so no second location manager runs.
  - The marker is an arrow pointing along the course when the heading is known (R6), and a dot otherwise.
  - It moves to each new fix with a 1 s animation; with Reduce Motion it jumps.
  - While Acquiring after a fix, it stays at the last position at 50% opacity. It is hidden while Unavailable.

  *(unit: the marker state the ViewModel exposes; manual)*

- **R6** **Heading-up.**
  - While following, the map is centred on the marker and rotated so that the course points up.
  - A course counts only when it is valid (≥ 0, course accuracy 0–30°) and the shown estimate is at least 5 km/h. Otherwise the map keeps its last heading. Before any valid course, it is north-up.
  - Rotation is animated, except with Reduce Motion.
  - The map stays flat (no pitch). The 5 km/h and 30° limits are named constants.

  *(unit: heading rule; manual)*

- **R7** **Zoom by speed.**
  - While following, the zoom level follows the shown estimate:
    - z17 below 30 km/h;
    - z16 from 30 km/h;
    - z15 from 60 km/h;
    - z14 from 90 km/h.
  - The level changes only once the speed is 5 km/h past a boundary, so it doesn't flip back and forth at the edge.
  - Thresholds are in km/h whatever the unit, and all are named constants. Changes are animated over 1 s, except with Reduce Motion.

  *(unit: levels and hysteresis)*

- **R8** **Moving the map by hand.**
  - I can drag, pinch and rotate the map. Pitch is off.
  - Any drag, pinch, rotation or tap-zoom stops following, and a **re-centre** button appears (44 pt glass circle, location glyph).
  - **Amended in planning (owner, 2026-10-27):** this was "rotation and pitch gestures are off". MapKit ignores a camera heading when rotation is off, which would break R6. So rotation stays on and counts as moving the map by hand. The compass is hidden, so the map can't be turned north without a gesture.
  - Following resumes, with the speed's zoom and heading, when I tap re-centre or after 10 s without a gesture (a named constant).
  - Zoom is limited to z3–z19.

  *(unit: follow/pause/resume with an injected clock; manual)*

- **R9** **Before a position, and with location off.**
  - Until the first accepted fix since launch, the map area shows a placeholder: the theme background with a location glyph. No tiles are requested. The status chip says why ("Searching for GPS…").
  - While Unavailable, the same placeholder shows with the status chip and "Open Settings" (speedometer R17).
  - After the first fix, Acquiring keeps the map with the dimmed marker (R5).

  *(unit: placeholder state; manual)*

### Tiles
- **R10** **Tile source.**
  - Raster tiles come from a URL template. The default is `https://tile.openstreetmap.org/{z}/{x}/{y}.png`, with zoom 0–19 and 256 px tiles.
  - The template can be overridden without an app update through `UserDefaults` key `map.tileURLTemplate`, e.g. a launch argument `-map.tileURLTemplate <url>`. An override is ignored if it is not `https` or lacks any of `{z}`, `{x}`, `{y}`.
  - The tiles replace Apple's map content: no Apple base map, points of interest, buildings or traffic under them.

  *(unit: template validation and URL building)*

- **R11** **Requests** (OSM tile policy):
  - HTTPS only. Each request carries the User-Agent `Xpeet/<version> (+https://github.com/LeKhacToan/xpeet)`, where `<version>` is `CFBundleShortVersionString`.
  - A request never sends `Cache-Control: no-cache` or `Pragma: no-cache`.
  - Only the tiles MapKit asks for to draw the visible map are fetched. There is no prefetching of the road ahead, no background download and no "download area".
  - No request is made while the map is not on screen: gauge mode, placeholder (R9), or a route view of a trip with no route.

  *(unit: request headers via an injected transport; review: no other fetch path)*

- **R12** **Cache.**
  - Tiles go through a dedicated disk cache of 150 MB in the app's Caches folder (a named constant).
  - A tile that is fresh by its HTTP cache headers is served from the cache with no request. A stale one is revalidated with a conditional request (`If-None-Match` / `If-Modified-Since`).
  - A response with no cache headers is treated as fresh for 7 days.
  - When a request fails for lack of network (offline, timeout), the cached copy is used even if stale, with no extra request.

  *(unit: stubbed responses: fresh hit, conditional revalidation, 7-day default, offline fallback)*

- **R13** **Tile errors** (error state).
  - A tile that can't be loaded and isn't cached shows as the light land colour, or a coarser tile from memory (R34), never an error image.
  - While the most recent tile request has failed (no network, HTTP 4xx/5xx), a small "Map offline" label shows next to the credit. It goes away after the next successful tile.
  - No alert, no retry button. The marker, trail, speed and trip keep working.

  *(unit: label state from the fetcher's results; manual: Airplane Mode)*

- **R14** **Credit.**
  - "© OpenStreetMap contributors" is always visible on every map (map mode and route view). It sits bottom trailing, on a legible backing.
  - It is never hidden behind a toggle and never covered by other overlays or the Apple logo or "Legal" link.
  - Tapping it opens https://www.openstreetmap.org/copyright in the browser.

  *(manual: every face, both orientations, largest text size)*

- ~~**R15** **Night dimming.**~~ *Superseded by R33 (owner, 2026-10-28): the map stays light like Grab's on every face, so tiles are no longer darkened under dark faces.*

- **R33** **Light map style** (owner, 2026-10-28: "white like Grab, not OSM's default colours").
  - OSM's standard tiles are recoloured on the phone; the tile source, requests and cache (R10–R12) don't change.
  - The palette: near-white cool grey land; white minor and secondary roads with grey edges; pale amber motorway, trunk and primary roads; light blue water; light green parks and woods; dark slate labels. Shops, offices and buildings stay neutral grey.
  - The same style on every face, in map mode and the route view. MapKit's own background and "Legal" link use the light appearance.
  - The recolouring is one colour function in sRGB, applied to each tile through a colour cube.

  *(unit: OSM Carto colours through the palette; the recoloured image; manual: real tiles)*

- **R34** **Smooth loading.**
  - Decoded, recoloured tiles are kept in memory (40 MB per map), so a tile seen before draws at once.
  - A tile that isn't in memory yet never shows as a dark or empty square. Its area shows the land colour, then the nearest coarser tile in memory (up to 5 levels up) enlarged, then any finer tiles in memory, until its own tile arrives.
  - Loads go through the fetcher and its cache (R11, R12): newest request first, at most 6 at a time, at most 64 waiting. A queued tile two or more zoom levels away from what the map last drew is dropped before it starts, and once the map is gone nothing queued is fetched.
  - A tile that failed isn't asked for again for 15 s, doubling with each failure up to 2 min. Its area is drawn again when the wait is over, so it fills in once the network is back.
  - The tile zoom follows MapKit's drawing scale, which is twice the screen's points per map point: one level above the camera zoom of R7, so tiles are sharp and shown at half size (measured on the simulator, 2026-10-28).

  *(unit: tile grid; the renderer's stand-ins, north-up drawing and requests; queue order, limit, dropping, stopping and retry delays; manual: pinch in and out on the device)*

### Trail and routes
- **R16** **Recording points.**
  - While the screen is running, every accepted fix is a route candidate when all of these hold:
    - the trip has started (trip-stats R5);
    - the state is Live;
    - horizontal accuracy is valid and at most 30 m.
  - A candidate is kept if it is at least 10 m from the last kept point of the current segment. The first point of a segment is always kept.
  - Only latitude and longitude are stored, rounded to 5 decimals (about 1 m). No time, speed, course or accuracy.
  - Recording runs in both modes.
  - The 30 m and 10 m limits are named constants.

  *(unit: synthetic fixes)*

- **R17** **Segments.**
  - A new segment starts whenever the trip's measuring chain breaks:
    - more than 5 s between Live updates;
    - Acquiring;
    - Unavailable;
    - the end of a run (trip-stats R1, R2).
  - Segments are never joined, so a gap shows as a break, never a straight jump.

  *(unit)*

- **R18** **Trail.**
  - In map mode, the current trip's segments are drawn as a line in the theme's accent colour, 5 pt wide. The last segment continues to the marker.
  - The line is the same colour everywhere, never coloured by speed. It has an edge, 1.5 pt each side, so every face's accent shows on the light map (R33): dark under a light accent, white under a dark one. It sits above the tiles, under the marker.
  - "New trip" and "Delete all trips" clear the trail.

  *(unit: trail data; manual)*

- **R19** **Routes belong to trips.**
  - Each trip gets a stable `id`. The current trip's route becomes that trip's route when the trip is finished.
  - A route is kept only while its trip is the current trip or in the history. A route whose trip is dropped is deleted at once. A trip is dropped when it is shorter than 100 m, falls past the 10th place, or is deleted (trip-stats R8, R24–R25).
  - Trips stored before this feature get an `id` when loaded and have no route. They are not lost.

  *(unit)*

- **R20** **Route storage.**
  - **Files:** one file per trip, in `Application Support/Routes/`, named by trip `id`.
  - **Protection:**
    - files are written with complete file protection, so they can't be read while the phone is locked;
    - the folder is excluded from device backups.
  - **When saved:** routes are saved with the trip, at the same times (trip-stats R10).
  - **Failures:**
    - a save that fails (e.g. the phone just locked) is retried at the next save;
    - an unreadable file is treated as "no route" and deleted;
    - none of this ever crashes.

  *(unit: round trip; the write requests complete protection; the backup-exclusion attribute; corrupt file; pruning. Device: the file's protection reads back as complete. **Clarified in planning:** the Simulator doesn't enforce or report data protection, so the unit test checks the request and the device check confirms it.)*

- **R21** **Size.** A synthetic hour at 50 km/h with one fix per second stores under 200 KB of route. *(unit)*

### Trip sheet
- **R22** **Rows open routes.**
  - Each "Earlier trips" row (trip-stats R14) becomes a button with a chevron. Tapping it opens that trip's route view (R23).
  - VoiceOver hint: "Double-tap to show the route".

  *(manual)*

- **R23** **Route view** (frame `route-view`).
  - It replaces the sheet's content, and the sheet grows to the large detent.
  - **Top:** a back control "Trips", the trip's day and start time as the title, and "Done".
  - **Map:**
    - north-up, fitted to the whole route with padding;
    - drag and pinch work, but there is no rotation;
    - the route's segments are drawn in the accent colour, with a hollow start dot and a filled end dot;
    - credit (R14) and the light style (R33) apply, and the notice (R2) appears if it hasn't been accepted yet;
    - no live marker.
  - **Below the map:** distance, moving time and average speed, plus the "Approximate" tag when it applies. They use the same values and spoken strings as the row.
  - A trip with no route shows "No route saved for this trip" in place of the map, and no tiles are requested.

  *(manual: frames; unit: the route view's data)*

- **R24** **Delete one trip.**
  - Swiping left on an earlier-trip row reveals "Delete". Tapping it, or swiping all the way, deletes that trip and its route at once, with no confirmation.
  - VoiceOver: a "Delete" action on the row.
  - The deletion is saved immediately.

  *(unit: delete by id; manual)*

- **R25** **Delete all trips.** **Amended** by `specs/break-reminder/spec.md` R7: confirming also clears the driving stretch; the dialog text and the button's enable rule are unchanged.
  - A "Delete all trips" button (destructive) sits under the history. It asks once: "Delete all trips?", with the message "All trips and their routes will be deleted from this iPhone. This can't be undone." and the buttons "Delete All Trips" and "Cancel".
  - Confirming deletes:
    - the history;
    - the current trip's totals and route;
    - the tile cache.
    A new empty trip begins.
  - The button is disabled when the history is empty and the current trip is empty.

  *(unit; manual)*

### Accessibility
- **R26** **VoiceOver and text size.**
  - **Map mode:**
    - the speed card reads as in gauge mode (same label as the gauge), with the unit pill unchanged;
    - the map is one element, "Map", with the value "Following your position" or "Not following". The marker and trail are not separate elements;
    - buttons: "Show map" / "Show gauge", "Re-centre map";
    - the credit is a link, and "Map offline" is read.
  - **Route view:**
    - the map is one element, "Route map";
    - the totals are spoken in full (trip-stats R17);
    - "Delete" is an action (R24).
  - **Dynamic Type:** chip, trip line, credit, labels and buttons follow Dynamic Type up to `accessibility2`. Speed digits keep the gauge's fixed sizing.
  - **Reduce Motion:** no camera or marker animation.

  *(manual: Accessibility Inspector; unit: label strings)*

### Privacy, accuracy and repo
- **R27** **Nothing else leaves the phone.**
  - Tile requests (R11) are the only network traffic. No analytics, no upload, no other URL.
  - Routes and trips are never sent, shared or exported.

  *(review: `URLSession` appears only in the tile fetcher)*

- **R28** **Location usage string.** `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` becomes: "Xpeet uses your location to show your speed, trip totals, and your position and routes on the map. Routes stay on your device. Map tiles are downloaded from OpenStreetMap, which sees the area you are in." *(review)*

- **R29** **Speed is untouched.**
  - Nothing in the map or route code feeds `SpeedEstimator` or changes when a fix is accepted.
  - The existing speed, trip and accuracy tests pass unchanged, and `evals/run.sh` stays within its band.

  *(review; unit: existing suite)*

- **R30** **Route accuracy.**
  - A synthetic drive along a straight line and a 90° curve gives a route length within 1% of the true path.
  - On recorded drives of at least 5 km (`build/drives/`), the route length is within **2%** of the trip distance over the same stretch.
  - A recorded gap leaves a break.

  *(unit: synthetic; manual analysis on recorded drives, added to `specs/speed-accuracy/results.md`)*

- **R31** **Data use.** A test drive of at least 30 min in map mode measures mobile data per hour (Settings → Mobile Data, or Xcode's network report). The result goes in `specs/osm-map/results.md`. Target: at most 20 MB/h. *(manual)*

- **R32** **Repo.**
  - CLAUDE.md:
    - "no networking" becomes "networking only for map tiles";
    - Architecture gains lines for `Core/Map/` and `Features/Speedometer/Map/` (see Data & API).
  - Supersede notes go into the specs listed above.
  - Then `evals/run.sh` and `scripts/check-bands.sh` are re-run (docs/ai-sdlc.md).

  *(review)*

## User flows & UI

**Turning the map on.** On the gauge screen, tap the map button (top leading). The map appears centred on the car, heading-up, with the speed card, the trip line and the status chip. The first time, the OpenStreetMap notice shows until "OK". Next launch opens in map mode. Tap the gauge button to go back.

**Driving in map mode.** The marker and trail move with each fix. Zoom widens on faster roads. In a tunnel, the marker dims and the chip says "Searching for GPS…". After the tunnel, the trail starts a new segment. Without signal, seen tiles still show, and new areas show the plain light land colour with "Map offline".

**Looking around.** Drag or pinch → following stops, and re-centre appears. Tap it, or wait 10 s → back to following.

**Past routes.** Trip line → trip sheet → tap an earlier trip → its route, fitted to the screen, with its totals. "Trips" goes back and "Done" closes. In the list, swipe a trip to delete it. "Delete all trips" asks once, then clears everything.

| State | Map mode | Route view |
|---|---|---|
| **Notice pending** | map with the OSM banner until "OK" | same |
| **Waiting for first fix** (loading) | placeholder, chip "Searching for GPS…", no tiles requested | n/a |
| **Live, following** | tiles, marker arrow, trail, zoom by speed, heading-up | n/a |
| **Not following** (after a gesture) | map where I left it, re-centre button | n/a |
| **Acquiring after a fix** | map kept, marker dimmed, trail breaks | n/a |
| **Unavailable** (location off) | placeholder, chip, "Open Settings" if denied or Precise Location is off | sheet not reachable (trip-stats) |
| **Tiles failing** (error) | land colour where uncached, "Map offline" | same |
| **Trip with no route** (empty) | n/a | "No route saved for this trip", no tiles |
| **No earlier trips** (empty) | n/a | not reachable; list shows "No earlier trips", "Delete all trips" still deletes the current trip |

**Accessibility.** See R26. There are no new colour-only signals: "Map offline" is text, and the dimmed marker also has the status chip.

## Data & API
- **`Xpeet/Core/Map/`** is the only code that imports MapKit and the only code that uses `URLSession`, following the `Core/Audio` pattern:
  - `TileSource`: the URL template (default plus `UserDefaults` override, R10), validation, tile URL building and the User-Agent (R11). Foundation only.
  - `TileFetcher` protocol, plus:
    - `URLSessionTileFetcher` (production): its own `URLSession` with `URLCache` off, plus the app's `TileCache` (R12), the User-Agent, offline fallback, and the last-result status for "Map offline";
    - `FakeTileFetcher` (`#if DEBUG`).
  - `OSMTileOverlay`: an `MKTileOverlay` subclass that marks the layer, with `canReplaceMapContent = true`, z 0–19 and 256 px tiles, above labels.
  - `TileRenderer` (`MKOverlayRenderer`): draws the layer from `TileImages`, with stand-in tiles while loading (R34). `TileGrid`: tile maths in map points.
  - `TileImages`: one map's decoded tiles in memory, the load queue, and the recolouring through Core Image (R33, R34). `TilePalette`: the colour function and cube, Foundation only.
  - `MapCanvas`: a `UIViewRepresentable` around `MKMapView`.
    - It draws a `MapScene` value: camera target, heading, zoom, marker, segments and interaction mode.
    - It reports drags and pinches back.
    - The SwiftUI `Map` can't show custom tiles (research), so this is the app's first UIKit view wrapper.
- **`Xpeet/Features/Speedometer/Map/`**: pure logic with no MapKit import (plain latitude/longitude doubles), plus views:
  - `RoutePoint`, `Route` (segments of points).
  - `RouteRecorder`: the R16–R17 rules, fed beside `TripTracker`.
  - `MapFollower`: the R6–R8 rules (zoom level with hysteresis, heading, follow/pause/resume with an injected clock).
  - `RouteStore`: files, protection, backup exclusion and pruning (R19–R20), under an injected base folder for tests.
  - Views: `MapModeView` (the overlays of R3) and `RouteView` (R23), each with a `#Preview` that uses `FakeTileFetcher`.
- **`SpeedometerViewModel`:**
  - owns `RouteRecorder` and `MapFollower` (`@ObservationIgnored`), feeds them from `handle(sample:)`, `tick()` and `becomeUnavailable`, and saves routes with the trip;
  - exposes observed `screenMode`, `showsMapNotice`, and a `MapScene` snapshot that is assigned only when it changes;
  - new actions: `toggleScreenMode()`, `acceptMapNotice()`, `recentreMap()`, `mapWasMovedByHand()`, `deleteTrip(id:)`, `deleteAllTrips()`;
  - if the file grows past lint limits, map and route glue moves to `SpeedometerViewModel+Map.swift` (the plan decides).
- **`Trip`** gains `id: UUID`. It is decoded with a fresh `id` when missing (R19).
- **`TripTracker`** gains `delete(id:)` and `deleteAll()` and keeps R8 unchanged. `TripStore` is unchanged apart from the `id`.
- **`UserDefaults`** keys:
  - new: `screenMode`, `map.noticeAccepted`, `map.tileURLTemplate` (override only);
  - unchanged: `speedUnit`, `gaugeFace`, `trip.current`, `trip.history`.
- **Route file format:** JSON `{"segments": [[[lat, lon], …], …]}` with 5-decimal numbers. Nothing else.
- **Network:** HTTPS to the tile host only. No App Transport Security exceptions.
- **Offline:** speed, trip, trail and route history work fully offline. Tiles show from cache, otherwise the land colour (R12–R13).

## Non-functional
- **Performance:**
  - The camera and marker update once per accepted fix, not on the 2 Hz tick.
  - The trail appends to the last segment instead of redrawing the whole route. An hour has at most about 3,600 points.
  - The speed reading's latency doesn't change with the map on (R29).
- **Battery and data:**
  - Map mode costs map drawing plus tile fetches (target ≤ 20 MB/h, R31).
  - Gauge mode adds only route recording (one distance check per fix) and a small file write every 10 s.
- **Memory:** decoded tiles take up to 40 MB in memory per map (R34); the tile cache holds 150 MB on disk.
- **Privacy:**
  - **Stored on the device:** trip routes (R16–R20), protected while locked and kept out of backups, plus a tile cache that shows which areas were viewed. "Delete all trips" clears both (R25). **Amended** by `specs/break-reminder/spec.md` R7: it also clears the driving stretch.
  - **Sent off the device:** tile requests to tile.openstreetmap.org (OSMF and its CDN). They reveal the IP address and the tiles being viewed, about 300 m across at z17. OSMF logs them (OSMF Privacy Policy). Nothing else is sent.
  - **Usage string:** R28.
- **Localization:** new strings:
  - "Map", "Show map", "Show gauge", "Re-centre map";
  - "Following your position", "Not following";
  - "Map tiles come from OpenStreetMap. Their servers can see the area you are viewing.", "OK";
  - "© OpenStreetMap contributors", "Map offline";
  - "Trips", "Route map", "No route saved for this trip", "Double-tap to show the route";
  - "Delete", "Delete all trips", "Delete all trips?", "All trips and their routes will be deleted from this iPhone. This can't be undone.", "Delete All Trips", "Cancel".

## Out of scope
- Turn-by-turn navigation, routing, search, addresses, places (intent).
- Speed limits from OSM, and speed-based colours on the map or route (speedometer Out of scope; trip-stats R16).
- Downloading map areas for offline use, and any prefetching (OSM policy, intent).
- Exporting or sharing routes (GPX and the like); showing all routes at once; heatmaps (intent).
- Times, speeds or a top speed along a route (intent, trip-stats R16).
- A route view for the current trip (its trail is on the live map); deleting from inside the route view.
- Vector tiles, MapLibre, other tile providers, and map styles other than R33 (such as a dark map at night). The tile URL override (R10) leaves the door open.
- A settings screen for the tile address.
- Placing the marker below centre ("look-ahead"), 3D or pitched maps.
- CarPlay, background recording, Live Activity (intent).

## Flagged concerns
- **Privacy, positions stored (owner):** routes are the first positions the app keeps. They can reveal home, work and routines. This reverses trip-stats R9 ("no coordinates") and the speedometer's "never stored", as the owner decided in the intent. The mitigations are:
  - only rounded latitude and longitude, with no times;
  - complete file protection;
  - no backups;
  - per-trip and full delete;
  - pruning with the history.

  Recording starts for every trip after the update, in gauge mode too, with no separate opt-in (intent Decisions).
- **Privacy, first network use (owner):**
  - Tile requests send the IP address and the area being viewed to OSMF and its CDN, which logs them with no stated retention.
  - Mitigations: map mode is off by default (R1), a one-time notice (R2), and the new usage string (R28), which the owner approved in the intent.
  - **Spec addition:** "Delete all trips" also clears the tile cache (R25), because the cache shows where I looked. The owner should confirm this.
- **OSM Tile Usage Policy:**
  - R10–R14 follow it: User-Agent, attribution, caching, no prefetching, switchable URL.
  - The service has no SLA and can block heavy users without notice.
  - The User-Agent uses the GitHub repo as its contact. The owner should confirm the repo is public, or give a contact email instead.
- **Apple MapKit:**
  - Apple's logo and "Legal" link stay visible over OSM tiles (HIG).
  - Whether `MKMapView` still contacts Apple servers with `canReplaceMapContent` is unverified. *2026-10-28:* with the tiles not drawn, the simulator showed only MapKit's empty grid, with no Apple map or labels; below the label level, Apple's road names do show, so the tiles stay above labels.
  - Raster tiles rotate with heading-up, so labels can appear upside down when heading south. This is a known limitation, accepted.
- **Unverified here:**
  - the tile server's real `Cache-Control` (tile.openstreetmap.org was unreachable from this machine);
  - data use per hour (R31);
  - how sharp 256 px tiles look on 3× screens. *2026-10-28:* MapKit draws at twice the point scale, so tiles come one level above the camera zoom, shown at half size (R34).

  The first two get checked on the device during build.
- **App Store (not binding while sideloaded):** if Xpeet is ever distributed, it needs:
  - a privacy label (likely "Coarse Location, app functionality, not linked");
  - a privacy policy naming OSMF (5.1.1, 5.1.2);
  - consent before sending location (5.1.5), which R1 and R2 cover;
  - `PrivacyInfo.xcprivacy` (UserDefaults and file timestamp APIs).

  Driving safety (1.4.4/1.4.5): the map follows on its own and can be moved by hand, but needs no tap.
- **Spec amendments and repo:**
  - the speedometer, ui-redesign and trip-stats amendments listed at the top need owner sign-off;
  - R32 changes CLAUDE.md, which needs owner approval and an eval re-run;
  - the night dimming (R15) was a spec addition for driving at night; the owner replaced it with the light style (R33), so a bright map at night is accepted.

## Open questions
Carried from the intent (all answered by the owner, 2026-10-27):
- *Tile source and engine?* **Answered:** Apple's map view with tile.openstreetmap.org raster tiles, no new library, URL switchable (R10).
- *Where does the map live?* **Answered:** a separate map mode (R1, R3).
- *On by default?* **Answered:** off until I tap the map button, with a one-time notice (R1, R2).
- *Orientation?* **Answered:** heading-up while moving; keeps the last heading when stopped (R6).
- *Trail and route history?* **Answered:** yes, with delete (R16–R25).
- *How many routes?* **Answered:** the same last 10 trips (R19).
- *Viewing?* **Answered:** one trip at a time from the trip sheet, and no past routes on the live map (R23).
- *Deleting?* **Answered:** swipe or VoiceOver action for one trip without confirmation; "Delete all trips" with one confirmation, including the current trip (R24, R25).
- *Gaps?* **Answered:** breaks, never joined (R17).
- *Storage?* **Answered:**
  - thinned to about 10 m;
  - points with poor accuracy skipped;
  - kept out of backups;
  - protected while locked (R16, R20).
- *Usage string?* **Answered:** the intent's text (R28).
- *Distribution?* **Deferred:** privacy label and policy only if distributed (Flagged concerns).

Raised by this spec (defaults chosen here; the owner may change them in review):
- *Thresholds:*
  - zoom z17/z16/z15/z14 at 30/60/90 km/h with 5 km/h hysteresis (R7);
  - heading-up from 5 km/h with course accuracy ≤ 30° (R6);
  - follow resumes after 10 s (R8);
  - route points need accuracy ≤ 30 m and 10 m spacing (R16);
  - tile cache 150 MB (R12);
  - ~~night dimming 35% (R15)~~ replaced by the light style (R33).
- *"The first point of a segment is always kept":* the 10 m spacing only applies within a segment (R16).
- *Times not stored:* the intent said "positions with times". Nothing on screen needs times, so routes store positions only. That is less data with the same features (R16).
- *Delete all also clears the tile cache* (R25, Flagged concerns).
- *Mode button top leading, face button hidden in map mode* (R1, R3). The frames confirm this.
- *Route view inside the sheet* with a "Trips" back control, not a new screen (R23). Frame `route-view` confirms it.
- *User-Agent contact:* the GitHub repo URL (R11).
