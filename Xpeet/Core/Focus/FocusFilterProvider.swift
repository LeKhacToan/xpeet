import Foundation

/// Delivers the "Engine sounds" Focus filter's override (specs/engine-clip-toggle R15–R17): true while a Focus whose
/// Xpeet filter has "Turn off engine sounds" on is active.
@MainActor
protocol FocusFilterProvider: AnyObject {
    /// The current override first, then each change, until cancelled. Nothing is stored.
    func updates() -> AsyncStream<Bool>
}

/// Maps a read of the filter's current value to the override (R17).
enum FocusFilterOverride {
    /// A value gives that value. A read that throws (e.g. no filter is set) or that timed out (`nil`) gives no override.
    static func from(_ read: Result<Bool, Error>?) -> Bool {
        guard case .success(let turnOff) = read else { return false }
        return turnOff
    }
}
