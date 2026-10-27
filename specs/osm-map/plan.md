# Plan: Map with OpenStreetMap

**Spec:** specs/osm-map/spec.md
<!-- Produced in Claude Code plan mode. Update in the same commit when implementation diverges. -->

## Context
- **Why:** Xpeet shows speed and trip totals, but not where I am or where I drove.
- **Approved so far:**
  - intent `intent/2026-10-27-osm-map.md` (accepted);
  - spec `specs/osm-map/spec.md` (approved 2026-10-27, flagged concerns included);
  - Stitch frames in `specs/osm-map/design/`.
- **Outcome:**
  - a **map mode** on the speed screen: OSM raster tiles via `MKMapView` + `MKTileOverlay`, heading-up, zooming with speed, the speed card always on top;
  - the current trip's **trail**;
  - the **route** of every kept trip stored on the device;
  - a route view and delete (one or all) in the trip sheet.
- **What is new for the repo:** the first network use (tiles only) and the first stored positions.
- **Branch:** one PR on `feat/osm-map`, which already holds the intent, spec and frames (uncommitted).

## Files that change

### New: `Xpeet/Core/Map/`
The only code that imports MapKit or uses `URLSession`, like `Core/Audio`.
- **`TileSource.swift`** (Foundation only):
  - the default template `https://tile.openstreetmap.org/{z}/{x}/{y}.png`, z 0–19;
  - `init(defaults:)`, which reads the override from `map.tileURLTemplate` and accepts it only if it is `https` and has `{z}`, `{x}` and `{y}` (R10);
  - `url(z:x:y:)`;
  - `userAgent(version:)` → `Xpeet/<version> (+https://github.com/LeKhacToan/xpeet)` (R11).
- **`TileCache.swift`**: an `actor`, a small HTTP-aware disk cache.
  - Files live flat in `Caches/Tiles` as `z-x-y.tile`, each with a `z-x-y.meta` sidecar: ETag, Last-Modified, expiry.
  - The base folder is injected. Freshness uses the fetcher's injected clock; last-use times use the file dates.
  - Freshness:
    - from `Cache-Control: max-age` or `Expires`;
    - with neither, 7 days (R12).
  - Size: 150 MB, evicting the least recently used tiles. `removeAll()` backs R25.
- **`TileFetcher.swift`**:
  - the `protocol TileFetcher: Sendable` with:
    - `func tile(_ key: TileKey) async throws -> Data`;
    - `func statusUpdates() -> AsyncStream<TileStatus>`, where `TileStatus` is `.ok` or `.offline`;
    - `func clearCache() async`.
  - **`URLSessionTileFetcher`**, the production implementation:
    - an ephemeral `URLSession` with `URLCache` off, the User-Agent header, and no `no-cache` headers;
    - a fresh cached tile is returned with no request;
    - a stale one is revalidated with a conditional request (`If-None-Match` / `If-Modified-Since`), and a 304 refreshes its expiry;
    - a network error or HTTP 4xx/5xx returns the stale copy if there is one, otherwise it throws;
    - it publishes `.offline` / `.ok` (R11–R13);
    - duplicate in-flight requests for the same tile are merged, since MapKit can't cancel loads;
    - the transport (`(URLRequest) async throws -> (Data, HTTPURLResponse)`) is injected, so tests need no network.
  - **`FakeTileFetcher`** (`#if DEBUG`): a flat-colour PNG, with a switchable failure. Previews and tests use it.
- **`OSMTileOverlay.swift`**:
  - a nonisolated `MKTileOverlay` subclass: `canReplaceMapContent = true`, `maximumZ = 19`, `tileSize` 256;
  - it overrides only the async `loadTile(at:) async throws -> Data` (the SDK form; MapKit calls it on background queues) and calls `TileFetcher` (R10, R11);
  - no main-actor hop inside.
- **`DimOverlay`** (in `OSMTileOverlay.swift`, with `CameraMath`): an `MKPolygon` covering `MKMapRect.world`. An `MKPolygonRenderer` draws it with fill black at `MapStyle.dimOpacity` (0.35). It is inserted just above the tiles and below the trail, and added or removed when the face changes (R15). This is the pattern from Apple's overlay sample; a renderer subclass or alpha was avoided (research).
- **`MapCanvas.swift`**: the `UIViewRepresentable` around `MKMapView` (R5–R8, R14, R18, R23).
  - **Settings:**
    - POIs off, buildings off, pitch off, compass hidden;
    - **rotation on**, because MapKit ignores a camera heading when `isRotateEnabled` is false (research, spec R8 amended);
    - zoom range z3–z19.
  - **Input:** one `MapScene` value:
    - the camera (centre, zoom, heading), or nil when not following;
    - the marker (coordinate, heading, dimmed);
    - the segments;
    - the dimming;
    - a fit-to-route mode;
    - Reduce Motion.
  - **Coordinator:** applies only what changed.
    - Camera moves are animated over 1 s, or not at all with Reduce Motion.
    - The marker is a custom annotation view, an arrow or a dot.
    - Trail segments are polylines in chunks of up to 200 points. Only the last chunk is replaced on each fix.
    - It adds its own recognisers alongside MapKit's: pan, pinch, rotation, double-tap and two-finger tap, all set to `cancelsTouchesInView = false`. Each one calls `onUserGesture` when it begins, so a rotation by hand counts as moving the map (R8 amended).
    - The camera is set with `setCamera(MKMapCamera(lookingAtCenter:fromDistance:pitch: 0, heading:))`.
    - `CameraMath.distance(zoom:latitude:viewHeight:metersPerPointCalibration:)` gives the camera distance. Metres per point at zoom z is `MKMetersPerMapPointAtLatitude(lat) · 2^(20−z)`. The ratio of distance to visible height is measured from the live map (two points via `convert(_:toCoordinateFrom:)`) and measured again when the view size changes.
    - It skips work when the `MapScene` hasn't changed, because the route view inside the sheet updates at 2 Hz.

### New: `Xpeet/Features/Speedometer/Map/`
Pure logic plus views, with no MapKit import. Coordinates are plain doubles.
- **`Route.swift`:**
  - `struct RoutePoint: Codable, Equatable { latitude, longitude }`, rounded to 5 decimals;
  - `struct Route: Codable, Equatable { segments: [[RoutePoint]] }`, with `length` (reusing `SpeedEstimator`'s sphere distance) and `bounds`.
- **`RouteRecorder.swift`** (R16, R17):
  - `mutating func add(latitude:longitude:horizontalAccuracy:)`: it skips invalid fixes or accuracy above 30 m, and keeps a point at least 10 m from the last kept point of the segment;
  - `breakSegment()`;
  - `reset()`;
  - constants as named statics.
- **`MapFollower.swift`** (R6–R8), a pure value type with an injected time:
  - zoom level with 5 km/h hysteresis (z17 / 16 / 15 / 14 at 30 / 60 / 90 km/h);
  - heading from a valid course (accuracy 0–30° and at least 5 km/h), otherwise the last one;
  - `userMoved(at:)` pauses following, `recentre()` resumes it, and `tick(at:)` resumes it after 10 s.
- **`RouteStore.swift`** (R19, R20):
  - one JSON file per trip id in an injected folder (default `Application Support/Routes`);
  - written with `[.atomic, .completeFileProtection]` through an injected writer, so tests can check the options requested (the Simulator doesn't report file protection); the folder is marked `isExcludedFromBackup`;
  - `load(id:)`, `save(_:id:)`, `prune(keeping:)`, `removeAll()`;
  - an unreadable file is deleted and counts as no route;
  - a write that fails is reported, so the ViewModel retries at the next save.
- **`MapStyle.swift`**: the dimming per face (dark faces only), the card fill, the trail width (5 pt), and the dimmed marker opacity (0.5).
- **`MapModeView.swift`** (R3, R9, R13, R14, R2 banner): the map-mode layout from the frames.
  - The placeholder shows until the first fix (no `MapCanvas`, so no tiles are requested).
  - Portrait:
    - the speed card full width at the bottom, with the trip line under it;
    - the chip in the top row;
    - re-centre bottom trailing;
    - the credit and "Map offline" bottom trailing.
  - Landscape:
    - the speed card leading and vertically centred, with the trip line under it;
    - the chip on the bottom edge.
  - `#Preview` for each frame state (`FakeTileFetcher`).
- **`SpeedCard.swift`**: the digits in the face's number font, at least 64 pt in portrait and 56 pt in landscape, on an opaque themed card (R3, R4). It includes the existing `UnitPill`.
- **`RouteView.swift`** (R23):
  - the header with "‹ Trips", the title and "Done";
  - a north-up `MapCanvas` fitted to the route, with start and end dots;
  - a totals card;
  - "No route saved for this trip" when there is no route;
  - `#Preview`.
- **`MapNotice.swift`** (R2): the banner card with "OK".

### Modified
- **`Trip.swift`:**
  - add `var id: UUID?`. It is nil while the trip is empty, so `Trip() == Trip()` still holds, and it is set when the trip starts (R19);
  - `init(from:)` gives a fresh id to a stored trip that has started but has no id.
- **`TripTracker.swift`:** add `delete(id:)` and `deleteAll()` (the latter also resets the current trip). Set `current.id` at the first moving update. R8 is unchanged.
- **`TripDisplay.swift` / `TripFormatter.swift`:** `Row.id` becomes the trip's `UUID`, and `Row` gains a `routeHint`.
- **`TripSheet.swift`** (R22–R25):
  - the body becomes a `List` styled as today: clear rows, hidden separators, card insets;
  - history rows become buttons with a chevron and `.swipeActions` → "Delete";
  - a "Delete all trips" button with a `confirmationDialog`;
  - `@State selectedTrip: UUID?` swaps in `RouteView`;
  - while a route is shown, the detents are `[.large]` with `interactiveDismissDisabled()`, so dragging the map doesn't drag the sheet;
  - new inputs: `onDelete`, `onDeleteAll`, `route`, `isMapNoticePending`, `isMapOffline`, `onAcceptNotice`, `tileFetcher`.
- **`SpeedometerViewModel.swift`:**
  - **New stored properties:**
    - `screenMode`, `isMapNoticePending`, `mapScene` (all observed);
    - `isMapOffline`, `hasPosition` (observed);
    - `@ObservationIgnored`: `routeRecorder`, `mapFollower`, `routeStore`, `tileFetcher`, `lastTripUpdate`.
  - **Init:** new parameters `routeStore: RouteStore = .standard` and `tileFetcher: TileFetcher? = nil` (production `URLSessionTileFetcher`).
  - **`run()`:**
    - one more group task feeds `tileFetcher.statusUpdates()` into `handle(tileStatus:)`;
    - `beginRun` / `endRun` also call `breakSegment()`.
  - The ViewModel is 507 lines, so the map glue goes in an extension (below).
- **New `SpeedometerViewModel+Map.swift`** (extension; stored properties stay in the class):
  - `toggleScreenMode()`, `acceptMapNotice()`, `recentreMap()`, `mapWasMovedByHand()`, `handle(tileStatus:)`;
  - `deleteTrip(id:)` and `deleteAllTrips()` (the latter also calls `routeStore.removeAll()` and `tileFetcher.clearCache()`);
  - `route(for:)`;
  - private `updateMap(sample:)` / `breakRoute()` / `saveRoute()` / `pruneRoutes()`.
  - It is called from `handle(sample:)` on the accepted path, from `tick()` (follow resume; a break on stale), from `becomeUnavailable`, and from `saveTrip()`.
- **`SpeedometerView.swift`:**
  - the body switches on `viewModel.screenMode`;
  - a new `modeButton` goes top leading, in the portrait top row and the landscape overlay (R1);
  - `unitButton`, `statusChip`, `openSettings` and `tripButton` lose `private` so that `SpeedometerView+Map.swift` can reuse them;
  - the sheet passes the new trip-sheet inputs;
  - previews gain map mode.
- **New `SpeedometerView+Map.swift`:** wires `MapModeView` with the shared pieces.
- **`project.yml`:** the location usage string becomes R28's text. No new key, entitlement or ATS exception. `xcodegen generate` is needed for the new files.
- **`CLAUDE.md`** (R32):
  - "no networking" → "networking only for map tiles (`Core/Map/`)";
  - Architecture lines for `Core/Map/` (the only MapKit and `URLSession` code) and `Features/Speedometer/Map/`.
- **Supersede notes:**
  - `specs/speedometer/spec.md`: R1, the network line, Offline, the location string and "never stored";
  - `specs/ui-redesign/spec.md`: R7 and R8;
  - `specs/trip-stats/spec.md`: R9, R14, Out of scope;
  - `intent/2026-10-26-trip-stats.md`: a one-line note.
- **`XpeetTests/Accuracy/DriveReplay.swift`** and the preview helper in `SpeedometerView.swift`: inject a temp `RouteStore` and a `FakeTileFetcher`.

### Tests
- **New files:**
  - `TileSourceTests` (R10, R11 User-Agent);
  - `TileFetcherTests` (R11 headers, R12 fresh / revalidate / 7-day / offline stale, R13 status), using a fake transport, a temp folder and an injected clock;
  - `RouteRecorderTests` (R16, R17, R21 size);
  - `RouteStoreTests` (R19 prune, R20 round trip, protection and backup attributes, corrupt file);
  - `MapFollowerTests` (R6–R8);
  - `SpeedometerViewModelTests+Map.swift`, which reuses `makeViewModel`, `TestClock`, `sample` and `waitUntil`.
- **Changed files:**
  - `makeViewModel` always injects a temp `RouteStore` and a `FakeTileFetcher`;
  - `TripTrackerTests` + `delete(id:)`, `deleteAll`, and the id being set at start;
  - `TripStoreTests`: "id" joins the allowed keys (spec R9 amendment), and a legacy JSON without an id still loads;
  - `GaugeFaceTests` + the map-card contrast;
  - `AccuracyReportTests` + `testRouteLengthAgainstTripDistance` (recorded drives, skipping without drives); the synthetic straight + 90° curve check is `RouteRecorderTests.testRouteLengthOnStraightAndCurve`.

## Order of work
Each step: `xcodegen generate` when files are added, then `scripts/verify.sh` (sandbox off, `SIM_DEVICE="iPhone 15 Pro"`), then a commit.
0. Amend the spec (owner decision and research, 2026-10-27):
   - **R8:** rotation by hand is allowed and counts as moving the map; pitch stays off.
   - **R20:** the protection check is "the write requests complete protection" in unit tests, plus a check on the device.
   - **R15 note:** the dimming is an overlay above the tiles.

   Then commit the intent, spec, frames and this plan as `specs/osm-map/plan.md`.
1. `Trip.id` + `TripTracker.delete/deleteAll` + test updates (no UI).
2. `Route`, `RouteRecorder`, `RouteStore` + tests.
3. `MapFollower` + tests.
4. `TileSource`, `TileCache`, `TileFetcher` (production + fake) + tests.
5. ViewModel map glue (`+Map.swift`) + `SpeedometerViewModelTests+Map.swift`, covering:
   - mode persistence and its default;
   - the notice;
   - placeholder/fix;
   - the marker state;
   - trail and breaks;
   - saving and pruning;
   - delete one / all;
   - tile status → "Map offline";
   - follow pause/resume.
6. `OSMTileOverlay`, `DimOverlay`, `MapCanvas`, `CameraMath`. A manual check in the simulator:
   - tiles load with the User-Agent;
   - heading-up rotation works with rotation enabled;
   - zoom levels look right;
   - log `path.z` against the zoom we asked for (the Retina risk).
7. `SpeedCard`, `MapNotice`, `MapModeView`, the mode button and `SpeedometerView+Map.swift`, with previews. Compare against the frames.
8. `TripSheet` as a `List` with swipe delete and "Delete all trips", plus `RouteView`.
9. The route accuracy test, the map-card contrast test, the R28 string, the CLAUDE.md lines and the supersede notes.
10. `scripts/verify.sh`, `evals/run.sh` + `scripts/check-bands.sh`, the `reviewer` and `verifier` agents, the PR text, then `scripts/install-device.sh` for a test drive (R31: data per hour → `specs/osm-map/results.md`).

## Deviations
- **View files:**
  - `MapModeView.swift` holds the map-mode pieces: `MapCardBackground`, `SpeedCard`, `MapNotice`, `MapCredit`, `RecentreButton`, `MapPlaceholder`.
  - The layout lives in `SpeedometerView+Map.swift`, which reuses the speed screen's chip, unit pill, trip line and Open Settings.
  - So `SpeedometerView.viewModel`, `theme`, `showsTrip` and those pieces lost `private`; `StatusChip` is internal.
- **`MapScene.swift`** (new, not in the file list): `ScreenMode`, `MapCoordinate`, `MapScene` and `MapStyle`, which keep MapKit out of `Features/`.
- **`MapCanvas`** gets its size from a small `MKMapView` subclass that reports layout. Until the map has a size, the camera and route fitting wait for it.
- **`SpeedEstimator.distance(fromLatitude:longitude:toLatitude:longitude:)`**: the same formula, now also taking plain coordinates. The sample overload calls it, so estimation is unchanged (R29).
- **Map ViewModel state:** it is internal `var`s rather than `private(set)`, because the extension in another file sets them.
- **R30 tests:**
  - the synthetic straight + curve check is `RouteRecorderTests.testRouteLengthOnStraightAndCurve`;
  - the recorded-drive check is `AccuracyReportTests.testRouteLengthAgainstTripDistance`, through `AccuracyReport.routeLength` over the same stretches as the trip check. It skips without drives.
- **R4 card colour:**
  - `MapStyle.cardColor(for:)` uses the theme background plus the chip tint, unless the tint would break a contrast target. Then it drops the tint: Analog sport's "--" came to 6.86:1 with it.
  - Tested in `GaugeFaceTests.testMapCardContrastForEveryFace`.
- **Review and verifier fixes (step 10):**
  - **R4:** in map mode the status chip and the trip line use the opaque map card (`isOpaque`), not glass.
  - **R8:** `MapCanvas` sets `cameraZoomRange` from `CameraMath.distanceRange` (z3-z19). It is recomputed when the view size changes or the latitude moves by over a degree, and the route view uses the route's latitude. Gestures report their start, their end and about once a second in between, so following resumes 10 s after the last touch.
  - **R26:** `modeButtonLabel` and `mapAccessibilityValue` now come from the ViewModel and are unit-tested. "Route map" stays in the view (manual).
  - The tile log line no longer includes x/y.
  - **`TileCache`:** it trims on the first store of each launch, and counts the `.meta` sidecars.
  - **Route writes:** an unchanged route isn't rewritten on the 10 s save (`lastSavedRoute`, `testUnchangedRouteIsNotRewritten`).
  - **New tests** for:
    - the R16 gates;
    - the R17 run-end and stall breaks;
    - R13 HTTP refusal;
    - R25 deleting the current route.
- **Other files:**
  - `FakeTileFetcher.swift` is its own file;
  - `CameraMathTests.swift` is new;
  - `DriveReplayTests.swift` injects the fakes;
  - `AccuracyReport.swift` shares its stretches with `routeLength`.
- **No in-memory tile cache:** MapKit keeps its own cache of drawn tiles, so the spec's "20 MB in memory" is MapKit's, not ours.
- **Simulator check (step 6–7):**
  - This Mac's network resolves `tile.openstreetmap.org` to 127.0.0.1, so tiles fail here and "Map offline" shows, which is R13 working. Tiles are checked on the device.
  - The Simulator reports `speedAccuracy = -1`, which the estimator rightly ignores, so simulated drives never go Live. The visual check used a throwaway local patch, which was reverted and never committed.

## Risks
- **Own tile cache instead of `URLCache`** (choice): `URLCache` doesn't expose the 7-day default or a deterministic offline fallback, and its disk writes are asynchronous, which makes tests flaky. A small actor cache with an injected clock makes R12 testable. The cost is about 150 lines; eviction is by last access.
- **Zoom ↔ camera distance:** MapKit doesn't document its field of view; one measurement puts it near 30°. `CameraMath` works the ratio out from the live map instead of hard-coding it. The zoom levels are approximate, which the spec accepts.
- **Retina tile zoom:** MapKit may request z+1 tiles on 2×/3× screens (reported, not confirmed). That would double the data and show z18 tiles at our z17. In step 6, log `path.z` and the request count on the simulator, then on the device. If confirmed, lower the R7 levels by one so the tiles shown match the spec, and record it under Deviations.
- **Rotation (decided 2026-10-27):** rotation stays enabled so heading-up works, and a rotation by hand pauses following like a drag (R8 amended). The compass is hidden, because tapping it would turn the map north with no drag or pinch.
- **Gesture coverage:** our recognisers cover pan, pinch, rotation and both tap-zooms. Any MapKit gesture they miss only means following resumes late; it never breaks anything.
- **Tile loads can't be cancelled:** merging duplicate in-flight requests limits waste. Tiles are fetched only while a `MapCanvas` exists.
- **Upside-down labels heading south:** a raster limitation, accepted in the spec.
- **`MKMapView` cost:** the map is created only in map mode or the route view. The trail replaces only its last chunk of at most 200 points. Camera updates come once per fix, not every tick.
- **`List` in the trip sheet:** switching from `ScrollView` + `VStack` may shift the look. Keep the card styling via row background and insets, and compare with trip-stats' frames. `.swipeActions` should show up as a VoiceOver action; if not, add `.accessibilityAction(named: "Delete")`.
- **File protection in the Simulator:** the Simulator doesn't enforce or report data protection (research). So unit tests assert the requested write options through the injected writer, and backup exclusion is read back. On the device, `.protectionKey` is checked once with a debug build.
- **Lint and size:** the map glue lives in the ViewModel extension. `SpeedometerView` shares pieces through `+Map.swift`. SwiftLint isn't installed locally.
- **Contrast of the map card:** the card is the theme background plus the chip tint, and is opaque. If any face misses 7:1 or 4.5:1, the card drops the tint for that face.
- **Real tile server:** this machine couldn't reach tile.openstreetmap.org. Check `Cache-Control`, the User-Agent acceptance and data use on the device (R31).
- **Eval coupling:** keep `guard metersPerSecond >= Self.zeroClampMetersPerSecond else` and "Weak GPS signal" unchanged.

## Proof
| Req | Proof |
|---|---|
| R1 | `SpeedometerViewModelTests.testScreenModeDefaultsToGaugeAndPersists`; manual: button in both modes and orientations |
| R2 | `testMapNoticeShowsUntilAccepted`; manual: frame `map-notice` |
| R3 | manual: frames `map-portrait`, `map-landscape-weak-signal`, every face, largest text |
| R4 | `GaugeFaceTests.testMapCardContrastForEveryFace`; the chip and trip line use the same opaque card in map mode |
| R5 | `testMarkerFollowsAcceptedFixes`, `testMarkerDimsWhileAcquiringAndHidesWhenUnavailable` |
| R6 | `MapFollowerTests.testHeadingFollowsValidCourse`, `testHeadingHeldWhenSlowOrInaccurate` |
| R7 | `MapFollowerTests.testZoomLevelsByShownSpeed`, `testZoomHysteresis` |
| R8 | `MapFollowerTests.testGesturePausesFollowing`, `testFollowResumesAfterTenSeconds`, `testRecentreResumesAtOnce`; `SpeedometerViewModelTests.testGesturePausesFollowingAndResumes`; `CameraMathTests.testZoomLimitsSpanThreeToNineteen`; manual: drag, pinch, rotate and tap-zoom all show re-centre, zoom stops at z3/z19 |
| R9 | `testPlaceholderUntilFirstFix`; manual |
| R10 | `TileSourceTests.testDefaultTemplate`, `testOverrideNeedsHTTPSAndPlaceholders`; review: `OSMTileOverlay` replaces Apple's content, z0-19, 256 px |
| R11 | `TileFetcherTests.testRequestsCarryUserAgentAndNoNoCache`; review: no other fetch path, no prefetch |
| R12 | `TileFetcherTests.testFreshTileServedWithoutRequest`, `testStaleTileRevalidatesConditionally`, `testNoHeadersFreshForSevenDays`, `testOfflineServesStaleCopy`, `testCacheEvictsOverLimit` |
| R13 | `TileFetcherTests.testStatusOfflineThenOk`, `testRefusedWithCopyServesStaleAndGoesOffline`; `testMapOfflineLabelFollowsTileStatus`; manual: Airplane Mode |
| R14 | manual: credit visible and tappable on every map |
| R15 | `GaugeFaceTests.testDimmingOnlyOnDarkFaces`; manual: trail and marker not dimmed |
| R16 | `RouteRecorderTests.testSkipsInaccurateFixes`, `testKeepsPointsTenMetresApart`, `testFirstPointOfSegmentAlwaysKept`, `testStoresOnlyRoundedCoordinates`; `SpeedometerViewModelTests.testNoPointsBeforeTheTripStartsOrWhileUnavailable` |
| R17 | `RouteRecorderTests.testBreakStartsNewSegment`; `testRouteBreaksOnAcquiringAndUnavailable`, `testRouteBreaksAtRunEnd`, `testRouteBreaksAfterAStallWithoutTicks` |
| R18 | `testTrailIsCurrentTripAndClearsOnNewTrip`; manual |
| R19 | `RouteStoreTests.testPruneKeepsOnlyKnownTrips`; `TripTrackerTests.testIdSetWhenTripStarts`; `TripStoreTests.testLegacyTripWithoutIdLoads`; `testDroppedTripLosesRoute` |
| R20 | `RouteStoreTests.testRoundTrip`, `testWritesRequestCompleteProtection`, `testFolderExcludedFromBackup`, `testCorruptFileIsNoRoute`, `testFailedWriteRetriesAtNextSave`; `testRouteSavedWithTrip`; device: `.protectionKey` is `.complete` |
| R21 | `RouteRecorderTests.testHourAtFiftyIsUnder200KB` |
| R22 | manual: rows open the route view |
| R23 | `testRouteSavedWithTrip` (`route(for:)` loads the stored route); manual: frame `route-view`, no-route state |
| R24 | `TripTrackerTests.testDeleteById`; `testDeleteTripRemovesRoute`; manual: swipe + VoiceOver action |
| R25 | `TripTrackerTests.testDeleteAll`; `testDeleteAllClearsTripsRoutesAndTileCache` (including the current trip's route file); manual: dialog |
| R26 | `SpeedometerViewModelTests.testMapAccessibilityStrings`; manual: Accessibility Inspector |
| R27 | review: `URLSession` only in `URLSessionTileFetcher` (grep) |
| R28 | review `project.yml` |
| R29 | existing suite unchanged; `evals/run.sh` + `scripts/check-bands.sh` |
| R30 | `RouteRecorderTests.testRouteLengthOnStraightAndCurve` (synthetic); `AccuracyReportTests.testRouteLengthAgainstTripDistance` on recorded drives (manual, skips without drives) |
| R31 | manual test drive → `specs/osm-map/results.md` |
| R32 | review CLAUDE.md, supersede notes; evals re-run |

## Verification
- After every step: `SIM_DEVICE="iPhone 15 Pro" scripts/verify.sh` with the Bash sandbox off; paste the tail (`** TEST SUCCEEDED **`).
- In the simulator (step 6–8):
  - run the app with a Freeway Drive location;
  - switch to map mode and check that tiles load, the view is heading-up, zoom changes with speed, the trail is drawn and re-centre works;
  - Airplane Mode → "Map offline" while cached tiles still show;
  - the trip sheet's swipe delete, "Delete all trips" and route view;
  - the Accessibility Inspector.
- On the device: `scripts/install-device.sh`. Then a test drive in map mode: data per hour, real `Cache-Control`, how sharp the tiles are on a 3× screen.
