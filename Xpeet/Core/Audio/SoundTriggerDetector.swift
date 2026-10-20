import Foundation

enum MicAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    /// Denied or restricted: iOS reports both the same way for the microphone.
    case denied
}

/// One analysis window from the sound classifier: the best-scoring trigger label, even when its confidence is low,
/// so the consumer can tell when a streak of qualifying windows is broken.
struct SoundTriggerEvent: Equatable, Sendable {
    var label: String
    /// 0...1.
    var confidence: Double
    var timestamp: Date
}

/// Listens to the microphone and classifies sounds. The only abstraction over AVFoundation/SoundAnalysis
/// that features see (specs/engine-sound-clip).
@MainActor
protocol SoundTriggerDetector: AnyObject {
    /// Yields the current authorization first, then every change.
    func authorizationUpdates() -> AsyncStream<MicAuthorization>
    func requestAuthorization()
    /// One event per analysis window while iterated. Cancelling stops listening.
    /// The stream finishing on its own means listening failed (R12).
    func events() -> AsyncStream<SoundTriggerEvent>
    /// Drop audio without stopping the engine, e.g. while a sound plays (R8).
    func pause()
    func resume()
}
