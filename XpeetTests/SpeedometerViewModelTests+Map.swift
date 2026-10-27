import XCTest
@testable import Xpeet

/// Map mode, trail and routes in `SpeedometerViewModel` (specs/osm-map). Shares the main test file's helpers.
extension SpeedometerViewModelTests {
    /// Metres per degree of latitude on the sphere `SpeedEstimator.distance` uses.
    private var metresPerDegree: Double { 6_371_000.0 * .pi / 180 }

    /// A fix `north` metres up a synthetic meridian, with a valid position and course.
    private func fix(kmh: Double, north: Double, at clock: TestClock, course: Double = 0) -> SpeedSample {
        SpeedSample(
            metersPerSecond: kmh / 3.6, accuracy: 0.5, isStationary: false, timestamp: clock.now,
            latitude: 45 + north / metresPerDegree, longitude: 120, horizontalAccuracy: 5,
            course: course, courseAccuracy: 5
        )
    }

    /// One fix a second, ticking between them as the live app does. Returns where it stopped, metres north.
    @discardableResult
    private func driveNorth(_ viewModel: SpeedometerViewModel, clock: TestClock, seconds: Int, kmh: Double = 50,
                            from start: Double = 0) -> Double {
        var north = start
        for _ in 0..<seconds {
            viewModel.handle(sample: fix(kmh: kmh, north: north, at: clock))
            clock.advance(by: 0.5)
            viewModel.tick()
            clock.advance(by: 0.5)
            viewModel.tick()
            north += kmh / 3.6
        }
        return north
    }

    /// `waitUntil` for conditions that read an actor.
    private func waitUntilAsync(timeout: TimeInterval = 2, _ condition: () async -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while await !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// No fixes for `seconds`: past 5 s the state falls back to Acquiring.
    private func silence(_ viewModel: SpeedometerViewModel, clock: TestClock, seconds: Int) {
        for _ in 0..<(seconds * 2) {
            clock.advance(by: 0.5)
            viewModel.tick()
        }
    }

    // MARK: - specs/osm-map R1, R2

    func testScreenModeDefaultsToGaugeAndPersists() {
        let defaults = makeDefaults()
        let viewModel = makeViewModel(defaults: defaults)
        XCTAssertEqual(viewModel.screenMode, .gauge)

        viewModel.toggleScreenMode()

        XCTAssertEqual(viewModel.screenMode, .map)
        XCTAssertEqual(makeViewModel(defaults: defaults).screenMode, .map, "restored at launch")
    }

    func testMapNoticeShowsUntilAccepted() {
        let defaults = makeDefaults()
        let viewModel = makeViewModel(defaults: defaults)
        XCTAssertTrue(viewModel.isMapNoticePending)

        viewModel.acceptMapNotice()

        XCTAssertFalse(viewModel.isMapNoticePending)
        XCTAssertFalse(makeViewModel(defaults: defaults).isMapNoticePending, "accepted for good")
    }

    // MARK: - R5, R9

    func testPlaceholderUntilFirstFix() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        XCTAssertTrue(viewModel.showsMapPlaceholder)

        viewModel.handle(sample: fix(kmh: 30, north: 0, at: clock))
        XCTAssertFalse(viewModel.showsMapPlaceholder)

        viewModel.handle(authorization: .denied)
        XCTAssertTrue(viewModel.showsMapPlaceholder, "location off shows the placeholder again")
    }

    func testMarkerFollowsAcceptedFixes() throws {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)

        let end = driveNorth(viewModel, clock: clock, seconds: 10)

        let marker = try XCTUnwrap(viewModel.mapScene.marker)
        XCTAssertEqual(marker.coordinate.latitude, 45 + (end - 50 / 3.6) / metresPerDegree, accuracy: 1e-9)
        XCTAssertEqual(marker.heading, 0, "a valid course makes an arrow")
        XCTAssertFalse(marker.isDimmed)
        let camera = try XCTUnwrap(viewModel.mapScene.camera)
        XCTAssertEqual(camera.center, marker.coordinate)
        XCTAssertEqual(camera.zoom, 16, "50 km/h")
    }

    func testMarkerDimsWhileAcquiringAndHidesWhenUnavailable() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        driveNorth(viewModel, clock: clock, seconds: 5)

        silence(viewModel, clock: clock, seconds: 6)
        XCTAssertEqual(viewModel.state, .acquiring)
        XCTAssertEqual(viewModel.mapScene.marker?.isDimmed, true)

        viewModel.handle(authorization: .denied)
        XCTAssertNil(viewModel.mapScene.marker)
    }

    // MARK: - R8

    func testGesturePausesFollowingAndResumes() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        var north = driveNorth(viewModel, clock: clock, seconds: 3)

        viewModel.mapWasMovedByHand()
        XCTAssertNil(viewModel.mapScene.camera)

        north = driveNorth(viewModel, clock: clock, seconds: 9, from: north)
        XCTAssertNil(viewModel.mapScene.camera, "still within 10 s")
        driveNorth(viewModel, clock: clock, seconds: 2, from: north)
        XCTAssertNotNil(viewModel.mapScene.camera)

        viewModel.mapWasMovedByHand()
        viewModel.recentreMap()
        XCTAssertNotNil(viewModel.mapScene.camera)
    }

    // MARK: - R26

    func testMapAccessibilityStrings() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        XCTAssertEqual(viewModel.modeButtonLabel, "Show map")
        viewModel.toggleScreenMode()
        XCTAssertEqual(viewModel.modeButtonLabel, "Show gauge")

        driveNorth(viewModel, clock: clock, seconds: 2)
        XCTAssertEqual(viewModel.mapAccessibilityValue, "Following your position")
        viewModel.mapWasMovedByHand()
        XCTAssertEqual(viewModel.mapAccessibilityValue, "Not following")
    }

    // MARK: - R13

    func testMapOfflineLabelFollowsTileStatus() async {
        let tiles = FakeTileFetcher()
        let viewModel = makeViewModel(tileFetcher: tiles)
        let task = Task { await viewModel.run() }
        await waitUntilAsync { await tiles.subscriberCount > 0 }

        await tiles.send(.offline)
        await waitUntil { viewModel.isMapOffline }
        await tiles.send(.ok)
        await waitUntil { !viewModel.isMapOffline }

        task.cancel()
    }

    // MARK: - R16-R18

    func testTrailIsCurrentTripAndClearsOnNewTrip() throws {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)

        driveNorth(viewModel, clock: clock, seconds: 30)

        XCTAssertEqual(viewModel.mapScene.trail.count, 1)
        let segment = try XCTUnwrap(viewModel.mapScene.trail.first)
        XCTAssertGreaterThan(segment.count, 20)
        XCTAssertEqual(segment.last, viewModel.mapScene.marker?.coordinate, "the trail reaches the marker")

        viewModel.startNewTrip()

        XCTAssertEqual(viewModel.mapScene.trail, [])
    }

    func testRouteBreaksOnAcquiringAndUnavailable() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        var north = driveNorth(viewModel, clock: clock, seconds: 20)

        silence(viewModel, clock: clock, seconds: 6)
        north = driveNorth(viewModel, clock: clock, seconds: 20, from: north + 200)
        viewModel.handle(authorization: .denied)
        viewModel.handle(authorization: .authorized)
        driveNorth(viewModel, clock: clock, seconds: 20, from: north + 200)

        XCTAssertEqual(viewModel.routeRecorder.route.segments.count, 3, "Acquiring and Unavailable each break the route")
    }

    func testRouteBreaksAtRunEnd() async {
        let clock = TestClock()
        let provider = FakeSpeedProvider()
        let viewModel = makeViewModel(provider: provider, clock: clock)
        var north = 0.0
        func send(count: Int) async {
            for _ in 0..<count {
                let points = viewModel.routeRecorder.route.segments.joined().count
                provider.send(fix(kmh: 50, north: north, at: clock))
                await waitUntil { viewModel.routeRecorder.route.segments.joined().count == points + 1 }
                north += 50 / 3.6
                clock.advance(by: 1)
            }
        }

        let first = Task { await viewModel.run() }
        await waitUntil { provider.speedSubscriberCount > 0 }
        provider.send(.authorized)
        await send(count: 3)
        first.cancel()
        await first.value

        let second = Task { await viewModel.run() }
        await waitUntil { provider.speedSubscriberCount > 0 }
        await send(count: 2)
        second.cancel()
        await second.value

        XCTAssertEqual(viewModel.routeRecorder.route.segments.map(\.count), [3, 2], "each run starts a new segment")
    }

    func testRouteBreaksAfterAStallWithoutTicks() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        let north = driveNorth(viewModel, clock: clock, seconds: 5)

        clock.advance(by: 6)
        driveNorth(viewModel, clock: clock, seconds: 3, from: north + 80)

        XCTAssertEqual(viewModel.routeRecorder.route.segments.count, 2, "more than 5 s between updates breaks the route")
    }

    func testNoPointsBeforeTheTripStartsOrWhileUnavailable() {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)

        driveNorth(viewModel, clock: clock, seconds: 5, kmh: 0)
        XCTAssertTrue(viewModel.routeRecorder.route.isEmpty, "the trip hasn't started")

        viewModel.handle(authorization: .denied)
        viewModel.handle(sample: fix(kmh: 50, north: 0, at: clock))
        XCTAssertTrue(viewModel.routeRecorder.route.isEmpty, "nothing while location is off")

        viewModel.handle(authorization: .authorized)
        driveNorth(viewModel, clock: clock, seconds: 5)
        XCTAssertFalse(viewModel.routeRecorder.route.isEmpty)
    }

    // MARK: - R19, R20

    func testRouteSavedWithTrip() throws {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        driveNorth(viewModel, clock: clock, seconds: 30)

        viewModel.startNewTrip()

        let row = try XCTUnwrap(viewModel.trip.history.first)
        let route = try XCTUnwrap(viewModel.route(for: row.id))
        XCTAssertGreaterThan(route.length, 350, "about 400 m at 50 km/h")
    }

    func testDroppedTripLosesRoute() throws {
        let clock = TestClock()
        let store = makeRouteStore()
        let viewModel = makeViewModel(clock: clock, routeStore: store)
        viewModel.handle(authorization: .authorized)
        let north = driveNorth(viewModel, clock: clock, seconds: 20)
        let kept = try XCTUnwrap(viewModel.tripTracker.current.id)
        XCTAssertNotNil(store.load(id: kept), "saved while running")
        viewModel.startNewTrip()

        driveNorth(viewModel, clock: clock, seconds: 5, from: north)
        let short = try XCTUnwrap(viewModel.tripTracker.current.id)
        viewModel.startNewTrip()

        XCTAssertNil(store.load(id: short), "a trip under 100 m is dropped with its route")
        XCTAssertNotNil(store.load(id: kept))
    }

    func testDeleteTripRemovesRoute() throws {
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock)
        viewModel.handle(authorization: .authorized)
        driveNorth(viewModel, clock: clock, seconds: 30)
        viewModel.startNewTrip()
        driveNorth(viewModel, clock: clock, seconds: 30, from: 2_000)
        viewModel.startNewTrip()
        let older = try XCTUnwrap(viewModel.trip.history.last?.id)

        viewModel.deleteTrip(id: older)

        XCTAssertEqual(viewModel.trip.history.count, 1)
        XCTAssertNil(viewModel.route(for: older))
    }

    func testDeleteAllClearsTripsRoutesAndTileCache() async throws {
        let clock = TestClock()
        let tiles = FakeTileFetcher()
        let store = makeRouteStore()
        let viewModel = makeViewModel(clock: clock, routeStore: store, tileFetcher: tiles)
        viewModel.handle(authorization: .authorized)
        driveNorth(viewModel, clock: clock, seconds: 30)
        viewModel.startNewTrip()
        driveNorth(viewModel, clock: clock, seconds: 30, from: 2_000)
        let earlier = try XCTUnwrap(viewModel.trip.history.first?.id)
        let current = try XCTUnwrap(viewModel.tripTracker.current.id)
        XCTAssertNotNil(store.load(id: current))

        viewModel.deleteAllTrips()

        XCTAssertNil(store.load(id: current), "the current trip's route goes too")

        XCTAssertEqual(viewModel.trip.history, [])
        XCTAssertTrue(viewModel.trip.isEmpty, "the current trip goes too")
        XCTAssertNil(viewModel.route(for: earlier))
        XCTAssertEqual(viewModel.mapScene.trail, [])
        await waitUntilAsync { await tiles.clearCount == 1 }
    }

    func testFailedWriteRetriesAtNextSave() throws {
        final class FlakyDisk {
            var attempts = 0
        }
        let disk = FlakyDisk()
        let folder = FileManager.default.temporaryDirectory.appending(path: "Routes-\(UUID().uuidString)")
        let store = RouteStore(folder: folder) { data, url, options in
            disk.attempts += 1
            if disk.attempts == 1 { throw CocoaError(.fileWriteNoPermission) }
            try data.write(to: url, options: options)
        }
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock, routeStore: store)
        viewModel.handle(authorization: .authorized)

        driveNorth(viewModel, clock: clock, seconds: 25)

        let id = try XCTUnwrap(viewModel.tripTracker.current.id)
        XCTAssertGreaterThan(disk.attempts, 1)
        XCTAssertNotNil(store.load(id: id), "the next save wrote the whole route")
    }

    func testUnchangedRouteIsNotRewritten() {
        final class Disk {
            var writes = 0
        }
        let disk = Disk()
        let folder = FileManager.default.temporaryDirectory.appending(path: "Routes-\(UUID().uuidString)")
        let store = RouteStore(folder: folder) { data, url, options in
            disk.writes += 1
            try data.write(to: url, options: options)
        }
        let clock = TestClock()
        let viewModel = makeViewModel(clock: clock, routeStore: store)
        viewModel.handle(authorization: .authorized)
        let north = driveNorth(viewModel, clock: clock, seconds: 15)
        // Stopped at a light. The first save after stopping still writes the last few points.
        let stop = north - 50 / 3.6
        driveNorth(viewModel, clock: clock, seconds: 12, kmh: 0, from: stop)
        let writes = disk.writes
        XCTAssertGreaterThan(writes, 0)

        // The trip keeps saving every 10 s, but the route has no new point.
        driveNorth(viewModel, clock: clock, seconds: 30, kmh: 0, from: stop)

        XCTAssertEqual(disk.writes, writes)
    }

    func testRouteContinuesAfterRelaunch() throws {
        let clock = TestClock()
        let defaults = makeDefaults()
        let store = makeRouteStore()
        let first = makeViewModel(defaults: defaults, clock: clock, routeStore: store)
        first.handle(authorization: .authorized)
        driveNorth(first, clock: clock, seconds: 30)
        silence(first, clock: clock, seconds: 6)

        let second = makeViewModel(defaults: defaults, clock: clock, routeStore: store)
        second.handle(authorization: .authorized)
        driveNorth(second, clock: clock, seconds: 10, from: 1_000)

        XCTAssertEqual(second.routeRecorder.route.segments.count, 2, "the stored route continues in a new segment")
    }
}
