import Foundation

/// The mascot's expression. `happy` is the top of the curve: nothing rewards high speed.
enum Mood: Equatable, CaseIterable {
    /// No live reading: acquiring or unavailable.
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
}
