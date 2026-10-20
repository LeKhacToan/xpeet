import Foundation
import Observation

/// Plays a short bundled sound when the microphone hears an engine start or rev while the vehicle is stopped
/// (specs/engine-sound-clip). Owned by `SpeedometerViewModel`, which shares its lifecycle and says when it moves.
@Observable
@MainActor
final class EngineSoundViewModel {
    // MARK: Rules (R3, R7, R8)

    static let triggerLabels: Set<String> = ["engine_starting", "engine_accelerating_revving", "motorcycle"]
    static let confidenceThreshold = 0.6
    /// Consecutive qualifying analysis windows needed to fire.
    static let requiredConsecutiveWindows = 2
    /// Windows arrive about every 0.75 s; a longer gap breaks the streak.
    static let maxWindowGap: TimeInterval = 1.5
    static let cooldown: TimeInterval = 60
    /// Events this soon after a sound ends are ignored, so the sound never triggers itself.
    static let playbackTail: TimeInterval = 0.5

    enum Phase: Equatable {
        case idle, listening, playing, failed
    }

    private(set) var micAuthorization: MicAuthorization?
    private(set) var phase: Phase = .idle
    /// True while the vehicle moves; set by the owner. Read only when a detection fires.
    var isMoving: @MainActor () -> Bool = { false }

    private let detector: SoundTriggerDetector
    private let player: SoundPlayer
    private let now: () -> Date
    private let random: () -> Double

    /// Counts `run()` calls, so the end of an older run cannot reset a newer one.
    private var runCount = 0
    private var locationResolved = false
    private var hasRequestedMic = false
    private var streak = 0
    private var lastWindowAt: Date?
    private var playStartedAt: Date?
    /// Start of the last sound that played; the cooldown runs from here. Failed sounds never set it.
    private var lastPlayStartedAt: Date?
    private var lastPlayEndedAt: Date?

    init(
        detector: SoundTriggerDetector? = nil,
        player: SoundPlayer? = nil,
        now: @escaping () -> Date = Date.init,
        random: @escaping () -> Double = { Double.random(in: 0..<1) }
    ) {
        self.detector = detector ?? SoundAnalysisTriggerDetector(labels: Self.triggerLabels)
        self.player = player ?? AVAudioPlayerSoundPlayer()
        self.now = now
        self.random = random
    }

    // MARK: - Output

    /// Shown in the status chip when there is no location status (R11).
    var chipText: String? {
        micAuthorization == .denied ? String(localized: "Microphone off: enable it in Settings to hear engine sounds") : nil
    }

    var chipSymbol: String? { chipText == nil ? nil : "mic.slash" }

    // MARK: - Input

    /// Waits for microphone access, then listens and plays until cancelled.
    func run() async {
        runCount += 1
        let thisRun = runCount
        if phase == .failed { phase = .idle }
        for await authorization in detector.authorizationUpdates() {
            handle(micAuthorization: authorization)
            if authorization != .notDetermined { break }
        }
        guard micAuthorization == .authorized, !Task.isCancelled else { return }

        handleListeningStarted()
        let events = detector.events()
        let (plays, playQueue) = AsyncStream.makeStream(of: SoundFile.self)
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await event in events {
                    if let file = await self.handle(event: event) { playQueue.yield(file) }
                }
                playQueue.finish()
                await self.listeningEnded(cancelled: Task.isCancelled, run: thisRun)
            }
            // Playback runs beside the events loop, so events keep arriving (and being dropped) while a sound plays.
            group.addTask {
                for await file in plays {
                    await self.play(file)
                }
            }
        }
    }

    /// Location permission has been answered; the mic prompt may follow without stacking on it (R2).
    func handle(locationAuthorizationResolved resolved: Bool) {
        if resolved { locationResolved = true }
        requestMicIfReady()
    }

    func handle(micAuthorization: MicAuthorization) {
        self.micAuthorization = micAuthorization
        requestMicIfReady()
    }

    func handleListeningStarted() {
        phase = .listening
        streak = 0
        lastWindowAt = nil
    }

    /// One analysis window. Returns the sound to play when the rules fire, and pauses the detector for it.
    func handle(event: SoundTriggerEvent) -> SoundFile? {
        guard phase == .listening else { return nil }

        if let last = lastWindowAt, event.timestamp.timeIntervalSince(last) > Self.maxWindowGap {
            streak = 0
        }
        lastWindowAt = event.timestamp
        let qualifies = Self.triggerLabels.contains(event.label) && event.confidence >= Self.confidenceThreshold
        streak = qualifies ? streak + 1 : 0
        guard streak >= Self.requiredConsecutiveWindows else { return nil }
        streak = 0

        // Gates: a detection that fails one is dropped, never queued (R6–R8).
        let time = now()
        if isMoving() { return nil }
        if let started = lastPlayStartedAt, time.timeIntervalSince(started) < Self.cooldown { return nil }
        if let ended = lastPlayEndedAt, time.timeIntervalSince(ended) < Self.playbackTail { return nil }

        let files = SoundFile.allCases
        let file = files[min(Int(random() * Double(files.count)), files.count - 1)]
        phase = .playing
        playStartedAt = time
        detector.pause()
        return file
    }

    func handlePlaybackFinished() {
        lastPlayStartedAt = playStartedAt
        lastPlayEndedAt = now()
        resumeListening()
    }

    /// A sound that could not play starts no cooldown, but the tail still applies.
    func handlePlaybackFailed() {
        lastPlayEndedAt = now()
        resumeListening()
    }

    /// The events stream ended: cancelled with the screen, or the detector failed (R12, silent).
    func handleListeningEnded(cancelled: Bool) {
        phase = cancelled ? .idle : .failed
    }

    // MARK: - Private

    private func requestMicIfReady() {
        guard micAuthorization == .notDetermined, locationResolved, !hasRequestedMic else { return }
        hasRequestedMic = true
        detector.requestAuthorization()
    }

    private func listeningEnded(cancelled: Bool, run: Int) {
        guard run == runCount else { return }
        handleListeningEnded(cancelled: cancelled)
    }

    private func play(_ file: SoundFile) async {
        do {
            try await player.play(file)
            handlePlaybackFinished()
        } catch is CancellationError {
            // Cut off because the screen went away: the sound did start, so the cooldown applies (R7).
            handlePlaybackFinished()
        } catch {
            handlePlaybackFailed()
        }
    }

    private func resumeListening() {
        playStartedAt = nil
        guard phase == .playing else { return }
        phase = .listening
        streak = 0
        lastWindowAt = nil
        detector.resume()
    }
}
