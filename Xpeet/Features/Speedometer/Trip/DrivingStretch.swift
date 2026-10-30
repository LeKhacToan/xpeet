import Foundation

/// The time at the wheel since the last real rest (specs/break-reminder R13). Times only: no positions or speeds.
struct DrivingStretch: Codable, Equatable {
    /// The first moving update of the stretch; nil while it is empty.
    var startedAt: Date?
    /// Moving time plus stops shorter than a rest, s.
    var drivingTime: TimeInterval = 0
    var lastMovementAt: Date?

    var isEmpty: Bool { startedAt == nil }
}
