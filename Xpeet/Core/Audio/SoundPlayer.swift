import Foundation

/// The bundled sound files (specs/engine-sound-clip R5). The raw value is the resource name, `.m4a`.
enum SoundFile: String, CaseIterable, Sendable {
    case ohayo
    case vroom

    static let fileExtension = "m4a"

    var url: URL? { Bundle.main.url(forResource: rawValue, withExtension: Self.fileExtension) }
}

enum SoundPlayerError: Error {
    case missingFile
    case couldNotPlay
}

@MainActor
protocol SoundPlayer: AnyObject {
    /// Plays the file and returns when it has finished. Throws if it cannot play.
    func play(_ file: SoundFile) async throws
}
