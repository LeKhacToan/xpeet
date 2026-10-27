import Foundation

/// Map mode, the trail and trip routes (specs/osm-map). Stored properties live in the class; this file holds the
/// logic so the ViewModel stays readable.
extension SpeedometerViewModel {
    /// The map area shows a placeholder, and requests no tiles, until there is a position and while location is
    /// off (R9).
    var showsMapPlaceholder: Bool {
        isLocationOff || !hasPosition
    }

    var isLocationOff: Bool {
        if case .unavailable = state { return true }
        return false
    }

    /// VoiceOver label of the mode button (R26).
    var modeButtonLabel: String {
        screenMode == .gauge ? String(localized: "Show map") : String(localized: "Show gauge")
    }

    /// VoiceOver value of the live map, which is one element (R26).
    var mapAccessibilityValue: String {
        mapScene.isFollowing ? String(localized: "Following your position") : String(localized: "Not following")
    }

    // MARK: Actions

    /// The mode button (R1).
    func toggleScreenMode() {
        screenMode = screenMode == .gauge ? .map : .gauge
        defaults.set(screenMode.rawValue, forKey: Self.screenModeDefaultsKey)
    }

    /// "OK" on the OpenStreetMap notice (R2).
    func acceptMapNotice() {
        isMapNoticePending = false
        defaults.set(true, forKey: Self.mapNoticeDefaultsKey)
    }

    /// The re-centre button (R8).
    func recentreMap() {
        mapFollower.recentre()
        refreshMapScene()
    }

    /// A drag, pinch, rotation or tap-zoom on the live map (R8).
    func mapWasMovedByHand() {
        mapFollower.userMoved(at: now())
        refreshMapScene()
    }

    func handle(tileStatus: TileStatus) {
        let offline = tileStatus == .offline
        if offline != isMapOffline { isMapOffline = offline }
    }

    /// Swipe to delete one earlier trip and its route (R24).
    func deleteTrip(id: UUID) {
        tripTracker.delete(id: id)
        saveTrip()
        refreshTrip()
    }

    /// "Delete all trips": every trip, every route and the tile cache; a new empty trip begins (R25).
    func deleteAllTrips() {
        tripTracker.deleteAll()
        routeStore.removeAll()
        lastSavedRoute = nil
        routeRecorder.reset()
        routeTripID = nil
        saveTrip()
        refreshTrip()
        refreshMapScene()
        let tileFetcher = tileFetcher
        Task { await tileFetcher.clearCache() }
    }

    /// An earlier trip's stored route, for the route view (R23).
    func route(for id: UUID) -> Route? {
        routeStore.load(id: id)
    }

    // MARK: Feeding (called from SpeedometerViewModel.swift)

    /// An accepted fix: the route, the follower and the marker (R5-R7, R16).
    func updateMap(with sample: SpeedSample) {
        syncRouteTrip()
        // Accepted fixes are Live; points count only once the trip has started (R16).
        if tripTracker.current.id != nil {
            routeRecorder.add(latitude: sample.latitude, longitude: sample.longitude, horizontalAccuracy: sample.horizontalAccuracy)
        }
        mapFollower.update(
            metersPerSecond: estimator.shown?.estimate.metersPerSecond ?? 0,
            course: sample.course,
            courseAccuracy: sample.courseAccuracy
        )
        if sample.horizontalAccuracy >= 0 {
            lastPosition = MapCoordinate(latitude: sample.latitude, longitude: sample.longitude)
            if !hasPosition { hasPosition = true }
        }
        refreshMapScene()
    }

    /// Resumes following 10 s after the last gesture (R8).
    func tickMap() {
        if mapFollower.tick(at: now()) { refreshMapScene() }
    }

    /// Saves the current trip's route under its id and deletes routes whose trip is gone (R19, R20).
    /// An unchanged route isn't written again. A failed write needs nothing: the next save writes the whole route.
    func saveRoute() {
        syncRouteTrip()
        let route = routeRecorder.route
        if let id = routeTripID, !route.isEmpty, lastSavedRoute.map({ $0.id != id || $0.route != route }) ?? true,
           routeStore.save(route, id: id) {
            lastSavedRoute = (id, route)
        }
        routeStore.prune(keeping: tripTracker.tripIDs)
    }

    func refreshMapScene() {
        var marker: MapScene.Marker?
        if let lastPosition {
            switch state {
            case .live:
                marker = MapScene.Marker(coordinate: lastPosition, heading: markerHeading, isDimmed: false)
            case .acquiring:
                marker = MapScene.Marker(coordinate: lastPosition, heading: markerHeading, isDimmed: true)
            case .unavailable:
                marker = nil
            }
        }
        var trail = routeRecorder.route.segments.map { segment in
            segment.map { MapCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
        }
        // The last segment reaches the live marker (R18).
        if let marker, !marker.isDimmed, routeRecorder.isSegmentOpen, !trail.isEmpty {
            trail[trail.count - 1].append(marker.coordinate)
        }
        let camera = mapFollower.isFollowing ? lastPosition.map {
            MapScene.Camera(center: $0, zoom: mapFollower.zoom, heading: mapFollower.heading)
        } : nil
        let next = MapScene(marker: marker, camera: camera, trail: trail, dimsTiles: MapStyle.dimsTiles(for: face))
        if next != mapScene { mapScene = next }
    }

    // MARK: Private

    private var markerHeading: Double? {
        mapFollower.hasHeading ? mapFollower.heading : nil
    }

    /// A new, finished or deleted trip: the recorder follows the current trip (R19).
    private func syncRouteTrip() {
        let id = tripTracker.current.id
        guard id != routeTripID else { return }
        routeTripID = id
        routeRecorder.reset(to: id.flatMap(routeStore.load(id:)) ?? Route())
    }
}
