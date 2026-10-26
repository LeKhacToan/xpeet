import Foundation

/// A 3D vector in device coordinates. Foundation-only, so the estimator can do motion maths without Core Motion.
struct Vector3: Equatable, Codable, Sendable {
    var x: Double
    var y: Double
    var z: Double

    static let zero = Vector3(x: 0, y: 0, z: 0)

    var length: Double { (x * x + y * y + z * z).squareRoot() }

    func dot(_ other: Vector3) -> Double { x * other.x + y * other.y + z * other.z }

    func cross(_ other: Vector3) -> Vector3 {
        Vector3(x: y * other.z - z * other.y, y: z * other.x - x * other.z, z: x * other.y - y * other.x)
    }

    static func + (lhs: Vector3, rhs: Vector3) -> Vector3 { Vector3(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z) }
    static func - (lhs: Vector3, rhs: Vector3) -> Vector3 { Vector3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z) }
    static func * (lhs: Vector3, rhs: Double) -> Vector3 { Vector3(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs) }
}

/// One device-motion reading (specs/speed-accuracy R2). All vectors are in device coordinates.
struct MotionSample: Equatable, Codable, Sendable {
    /// Seconds since boot, as Core Motion stamps it. Map to wall-clock time with `MotionClock`.
    var timestamp: TimeInterval
    /// Acceleration without gravity, m/s².
    var userAcceleration: Vector3
    /// Direction of gravity, unit length.
    var gravity: Vector3
    /// rad/s.
    var rotationRate: Vector3
}

/// Source of device motion. The only abstraction over Core Motion that features see.
@MainActor
protocol MotionProvider: AnyObject {
    /// Batches of samples while subscribed. Finishes at once when the device has no motion sensors (e.g. Simulator).
    func motionUpdates() -> AsyncStream<[MotionSample]>
}
