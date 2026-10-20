import Foundation

/// Pure geometry shared by the faces. Angles are in degrees, clockwise from 12 o'clock.
enum GaugeGeometry {
    /// The dial runs 270°, from the lower left (−135°) to the lower right (+135°), open at the bottom.
    static let startAngle = -135.0
    static let sweepAngle = 270.0
    static let segmentCount = 20

    struct Tick: Equatable {
        var value: Int
        var isMajor: Bool
        /// Shown next to major ticks only.
        var label: String? { isMajor ? String(value) : nil }
    }

    /// Needle angle for a gauge fraction; the fraction is clamped to 0...1.
    static func needleAngle(fraction: Double) -> Double {
        startAngle + sweepAngle * min(max(fraction, 0), 1)
    }

    /// Angle of a scale value on a dial whose full value is `maximum`.
    static func angle(for value: Int, maximum: Int) -> Double {
        needleAngle(fraction: Double(value) / Double(maximum))
    }

    /// Minor ticks every 10, major ticks with labels every 20, plus a major tick at the maximum
    /// (130 mph is not a multiple of 20).
    static func ticks(for unit: SpeedUnit) -> [Tick] {
        let maximum = unit.gaugeMaximum
        return stride(from: 0, through: maximum, by: 10).map { value in
            Tick(value: value, isMajor: value % 20 == 0 || value == maximum)
        }
    }

    /// First value of a dial's static red zone: 160 km/h or 100 mph (specs/ui-redesign R11, R13).
    static func redZoneStart(for unit: SpeedUnit) -> Int {
        switch unit {
        case .kmh: 160
        case .mph: 100
        }
    }

    /// Where the red zone starts along the sweep, 0...1.
    static func redZoneStartFraction(for unit: SpeedUnit) -> Double {
        Double(redZoneStart(for: unit)) / Double(unit.gaugeMaximum)
    }

    /// How many of `count` segments are lit for a gauge fraction.
    static func litSegments(fraction: Double, count: Int = segmentCount) -> Int {
        Int((min(max(fraction, 0), 1) * Double(count)).rounded())
    }
}
