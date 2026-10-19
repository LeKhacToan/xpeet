import Foundation

/// One speed reading from the location source. Negative `metersPerSecond` or `accuracy` means invalid.
struct SpeedSample: Equatable, Sendable {
    var metersPerSecond: Double
    var accuracy: Double
    var isStationary: Bool
    var timestamp: Date
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
    func speedUpdates() -> AsyncStream<SpeedSample>
    func requestAuthorization()
}
