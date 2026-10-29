import Foundation

/// One stored route point: latitude and longitude only, rounded to 5 decimals, about 1 m (specs/osm-map R16).
/// Encoded as a two-number array to keep route files small (R21).
struct RoutePoint: Codable, Equatable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = Self.rounded(latitude)
        self.longitude = Self.rounded(longitude)
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.init(latitude: try container.decode(Double.self), longitude: try container.decode(Double.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(latitude)
        try container.encode(longitude)
    }

    /// Metres, on the same sphere as the speed estimate.
    func distance(to other: RoutePoint) -> Double {
        SpeedEstimator.distance(fromLatitude: latitude, longitude: longitude, toLatitude: other.latitude, longitude: other.longitude)
    }

    private static func rounded(_ degrees: Double) -> Double {
        (degrees * 100_000).rounded() / 100_000
    }
}

/// A trip's route. Segments are never joined, so a gap shows as a break (R17).
struct Route: Codable, Equatable {
    var segments: [[RoutePoint]] = []

    var isEmpty: Bool { segments.allSatisfy(\.isEmpty) }

    /// Metres along the segments; gaps between segments don't count.
    var length: Double {
        segments.reduce(0) { total, segment in
            total + zip(segment, segment.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        }
    }
}
