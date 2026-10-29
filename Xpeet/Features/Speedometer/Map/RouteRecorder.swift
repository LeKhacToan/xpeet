import Foundation

/// Builds the current trip's route from accepted fixes (specs/osm-map R16-R17). Pure value type, owned by
/// `SpeedometerViewModel`, which also tells it where the trip's measuring chain breaks.
struct RouteRecorder: Equatable {
    /// A fix less accurate than this is skipped, m.
    static let maxAccuracy = 30.0
    /// A point closer than this to the last kept point of its segment is skipped, m.
    static let minimumSpacing = 10.0

    private(set) var route: Route
    /// False after a break: the next point starts a new segment.
    private(set) var isSegmentOpen = false

    /// A stored route continues in a new segment: the run that recorded it has ended.
    init(route: Route = Route()) {
        self.route = route
    }

    /// Returns true when the point was kept.
    @discardableResult
    mutating func add(latitude: Double, longitude: Double, horizontalAccuracy: Double) -> Bool {
        guard horizontalAccuracy >= 0, horizontalAccuracy <= Self.maxAccuracy else { return false }
        let point = RoutePoint(latitude: latitude, longitude: longitude)
        guard isSegmentOpen, let last = route.segments.last?.last else {
            route.segments.append([point])
            isSegmentOpen = true
            return true
        }
        guard point.distance(to: last) >= Self.minimumSpacing else { return false }
        route.segments[route.segments.count - 1].append(point)
        return true
    }

    mutating func breakSegment() {
        isSegmentOpen = false
    }

    /// A new trip: nothing recorded yet.
    mutating func reset(to route: Route = Route()) {
        self.route = route
        isSegmentOpen = false
    }
}
