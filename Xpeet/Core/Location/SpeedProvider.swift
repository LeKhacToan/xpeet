import Foundation

/// One fix from the location source. Negative `metersPerSecond` or any negative accuracy means that value is invalid.
struct SpeedSample: Equatable, Codable, Sendable {
    var metersPerSecond: Double
    /// Speed accuracy, ± m/s.
    var accuracy: Double
    var isStationary: Bool
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    /// Position accuracy radius, m.
    var horizontalAccuracy: Double
    /// Direction of travel, degrees from true north.
    var course: Double
    /// Course accuracy, ± degrees.
    var courseAccuracy: Double

    init(
        metersPerSecond: Double,
        accuracy: Double,
        isStationary: Bool,
        timestamp: Date,
        latitude: Double = 0,
        longitude: Double = 0,
        horizontalAccuracy: Double = -1,
        course: Double = -1,
        courseAccuracy: Double = -1
    ) {
        self.metersPerSecond = metersPerSecond
        self.accuracy = accuracy
        self.isStationary = isStationary
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.course = course
        self.courseAccuracy = courseAccuracy
    }
}

/// What the location source reports: a fix, or (iOS 18+) that location is currently unavailable.
enum LocationUpdate: Equatable, Sendable {
    case fix(SpeedSample)
    case unavailable
}

enum LocationAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case servicesOff
}

/// Source of speed readings. The only abstraction over CoreLocation that features see.
@MainActor
protocol SpeedProvider: AnyObject {
    /// Yields the current authorization first, then every change.
    func authorizationUpdates() -> AsyncStream<LocationAuthorization>
    func speedUpdates() -> AsyncStream<LocationUpdate>
    func requestAuthorization()
}
