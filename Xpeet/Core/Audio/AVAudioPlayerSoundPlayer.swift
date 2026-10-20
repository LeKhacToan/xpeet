import AVFoundation

/// Production `SoundPlayer`: plays a bundled file on the shared session and returns when it ends.
@MainActor
final class AVAudioPlayerSoundPlayer: NSObject, SoundPlayer, AVAudioPlayerDelegate {
    /// Held while playing; AVAudioPlayer stops when released.
    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Error>?

    func play(_ file: SoundFile) async throws {
        guard let url = file.url else { throw SoundPlayerError.missingFile }
        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        player.prepareToPlay()
        guard player.play() else { throw SoundPlayerError.couldNotPlay }
        self.player = player
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        } onCancel: {
            Task { @MainActor in self.stop() }
        }
    }

    private func stop() {
        // `stop()` does not call the delegate, so finish by hand.
        player?.stop()
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<Void, Error>) {
        player = nil
        continuation?.resume(with: result)
        continuation = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finish(flag ? .success(()) : .failure(SoundPlayerError.couldNotPlay)) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.finish(.failure(error ?? SoundPlayerError.couldNotPlay)) }
    }
}
