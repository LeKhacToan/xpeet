import Foundation

/// How the live map follows the car (specs/osm-map R6-R8): zoom by speed, heading-up, and pausing while the map is
/// moved by hand. Pure value type; times are passed in.
struct MapFollower: Equatable {
    /// Speed boundaries, km/h: below the first the zoom is `zoomLevels[0]`, from the last it is `zoomLevels.last`.
    static let zoomBoundariesKmh = [30.0, 60, 90]
    static let zoomLevels = [17, 16, 15, 14]
    /// The zoom changes only once the speed is this far past a boundary, km/h (R7).
    static let zoomHysteresisKmh = 5.0
    /// Below this the course is unreliable and the heading holds, km/h (R6).
    static let headingMinimumKmh = 5.0
    /// A course less accurate than this is ignored, degrees (R6).
    static let headingMaxCourseAccuracy = 30.0
    /// Following resumes this long after the last gesture (R8).
    static let resumeAfter: TimeInterval = 10

    private(set) var zoom = zoomLevels[0]
    /// Degrees from true north; north-up until the first valid course.
    private(set) var heading = 0.0
    /// A valid course has been seen: the marker can be an arrow (R5).
    private(set) var hasHeading = false
    private(set) var isFollowing = true
    private var lastGesture: Date?

    /// An accepted fix: `metersPerSecond` is the shown estimate; course values as in `SpeedSample`.
    mutating func update(metersPerSecond: Double, course: Double, courseAccuracy: Double) {
        let kmh = metersPerSecond * 3.6
        updateZoom(kmh: kmh)
        if course >= 0, courseAccuracy >= 0, courseAccuracy <= Self.headingMaxCourseAccuracy, kmh >= Self.headingMinimumKmh {
            heading = course
            hasHeading = true
        }
    }

    /// A drag, pinch, rotation or tap-zoom by hand.
    mutating func userMoved(at time: Date) {
        isFollowing = false
        lastGesture = time
    }

    mutating func recentre() {
        isFollowing = true
        lastGesture = nil
    }

    /// Resumes following once no gesture has come for `resumeAfter`. Returns true when it resumed.
    @discardableResult
    mutating func tick(at time: Date) -> Bool {
        guard !isFollowing, let lastGesture, time.timeIntervalSince(lastGesture) >= Self.resumeAfter else { return false }
        recentre()
        return true
    }

    private mutating func updateZoom(kmh: Double) {
        let boundaries = Self.zoomBoundariesKmh
        var index = Self.zoomLevels.firstIndex(of: zoom) ?? 0
        while index < boundaries.count, kmh >= boundaries[index] + Self.zoomHysteresisKmh {
            index += 1
        }
        while index > 0, kmh < boundaries[index - 1] - Self.zoomHysteresisKmh {
            index -= 1
        }
        zoom = Self.zoomLevels[index]
    }
}
