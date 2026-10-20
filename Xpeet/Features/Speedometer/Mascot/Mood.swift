import Foundation

/// The mascot's expression. `happy` is the top of the curve: nothing rewards high speed.
enum Mood: Equatable, CaseIterable {
    /// No live reading yet: acquiring.
    case searching
    /// Stopped for a while.
    case sleepy
    /// Slow, or just stopped.
    case calm
    /// Moderate cruise.
    case happy
    /// Very fast: concern, not excitement.
    case worried
    /// Hard braking, for a moment.
    case startled
    /// Location is unavailable: denied, restricted or Location Services off (specs/ui-redesign R4).
    case sad
}
