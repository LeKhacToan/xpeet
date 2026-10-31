import AVFoundation
import SoundAnalysis

/// Production `SoundTriggerDetector`: the microphone through `AVAudioEngine` into Apple's built-in, on-device
/// sound classifier. Audio lives only in memory: nothing is recorded, stored or sent (specs/engine-sound-clip R4).
@MainActor
final class SoundAnalysisTriggerDetector: SoundTriggerDetector {
    private let labels: Set<String>
    private var authorizationContinuations: [UUID: AsyncStream<MicAuthorization>.Continuation] = [:]
    private var pipeline: AnalysisPipeline?
    /// The latest listening task. A new one waits for it to finish, so an old teardown never deactivates the session
    /// under a new engine (specs/engine-clip-toggle, off then on quickly).
    private var listening: Task<Void, Never>?

    /// Only `labels` are scored; the decision to fire lives in `EngineSoundViewModel`.
    init(labels: Set<String>) {
        self.labels = labels
    }

    func authorizationUpdates() -> AsyncStream<MicAuthorization> {
        let (stream, continuation) = AsyncStream.makeStream(of: MicAuthorization.self)
        let id = UUID()
        authorizationContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.authorizationContinuations[id] = nil }
        }
        continuation.yield(Self.currentAuthorization)
        return stream
    }

    func requestAuthorization() {
        Task {
            _ = await AVAudioApplication.requestRecordPermission()
            let authorization = Self.currentAuthorization
            authorizationContinuations.values.forEach { $0.yield(authorization) }
        }
    }

    func events() -> AsyncStream<SoundTriggerEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            let previous = listening
            let task = Task { @MainActor in
                await previous?.value
                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }
                let pipeline = AnalysisPipeline(labels: self.labels, continuation: continuation)
                self.pipeline = pipeline
                defer {
                    pipeline.stop()
                    if self.pipeline === pipeline {
                        AudioSession.deactivate()
                        self.pipeline = nil
                    }
                    continuation.finish()
                }
                do {
                    try AudioSession.activate()
                    try pipeline.start()
                } catch {
                    return
                }
                // Runs until cancelled: by the consumer, or by `continuation.finish()` when the pipeline fails.
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        let center = NotificationCenter.default
                        for await note in center.notifications(named: AVAudioSession.interruptionNotification) {
                            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                            let began = type == AVAudioSession.InterruptionType.began.rawValue
                            await MainActor.run { pipeline.interruption(began: began) }
                        }
                    }
                    group.addTask {
                        // Route changes (e.g. Bluetooth connects) stop the engine and change the input format.
                        let center = NotificationCenter.default
                        for await _ in center.notifications(named: .AVAudioEngineConfigurationChange, object: pipeline.engine) {
                            await MainActor.run { pipeline.restart() }
                        }
                    }
                    group.addTask {
                        for await _ in NotificationCenter.default.notifications(named: AVAudioSession.mediaServicesWereResetNotification) {
                            pipeline.fail()
                        }
                    }
                }
            }
            listening = task
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func pause() { pipeline?.setPaused(true) }
    func resume() { pipeline?.setPaused(false) }

    private static var currentAuthorization: MicAuthorization {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .authorized
        case .denied: .denied
        default: .notDetermined
        }
    }
}

private enum DetectorError: Error {
    case noInput
}

/// Engine, tap and analyzer. Engine control runs on the main actor; analysis and every mutable analysis
/// field are confined to `queue`, which is also where SoundAnalysis delivers results.
private final class AnalysisPipeline: NSObject, SNResultsObserving, @unchecked Sendable {
    /// About one result every 0.75 s: 1.5 s windows with 50% overlap.
    private static let windowSeconds = 1.5
    private static let overlap = 0.5

    let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "app.plouton.xpeet.sound-analysis")
    private let labels: Set<String>
    private let continuation: AsyncStream<SoundTriggerEvent>.Continuation
    private var analyzer: SNAudioStreamAnalyzer?
    /// The live request. Callbacks for a removed one (after `stop()` or a restart) are ignored, so a deliberate
    /// teardown never reads as a failure.
    private var request: SNRequest?
    private var isPaused = false

    init(labels: Set<String>, continuation: AsyncStream<SoundTriggerEvent>.Continuation) {
        self.labels = labels
        self.continuation = continuation
    }

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw DetectorError.noInput }

        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        let window = CMTime(seconds: Self.windowSeconds, preferredTimescale: 48_000)
        // 1.5 s if allowed, else the nearest allowed window.
        switch request.windowDurationConstraint {
        case let .durationRange(range):
            if CMTimeRangeContainsTime(range, time: window) { request.windowDuration = window }
        case let .enumeratedDurations(durations):
            if let nearest = durations.min(by: { abs($0.seconds - Self.windowSeconds) < abs($1.seconds - Self.windowSeconds) }) {
                request.windowDuration = nearest
            }
        @unknown default:
            break
        }
        request.overlapFactor = Self.overlap

        let analyzer = SNAudioStreamAnalyzer(format: format)
        try analyzer.add(request, withObserver: self)
        queue.sync {
            self.analyzer = analyzer
            self.request = request
        }

        input.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak self] buffer, time in
            guard let self else { return }
            self.queue.async {
                guard !self.isPaused, let analyzer = self.analyzer else { return }
                analyzer.analyze(buffer, atAudioFramePosition: time.sampleTime)
            }
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        queue.sync {
            request = nil
            analyzer?.removeAllRequests()
            analyzer = nil
        }
    }

    /// New input format after a route change: rebuild the analyzer for it.
    func restart() {
        stop()
        do {
            try AudioSession.activate()
            try start()
        } catch {
            fail()
        }
    }

    func interruption(began: Bool) {
        if began {
            engine.pause()
        } else {
            do {
                try AudioSession.activate()
                try engine.start()
            } catch {
                fail()
            }
        }
    }

    func setPaused(_ paused: Bool) {
        queue.async { self.isPaused = paused }
    }

    func fail() {
        continuation.finish()
    }

    // MARK: SNResultsObserving (on `queue`)

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard request === self.request, let result = result as? SNClassificationResult else { return }
        let best = labels.compactMap { result.classification(forIdentifier: $0) }.max { $0.confidence < $1.confidence }
        continuation.yield(SoundTriggerEvent(label: best?.identifier ?? "", confidence: best?.confidence ?? 0, timestamp: Date()))
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        if request === self.request { continuation.finish() }
    }

    func requestDidComplete(_ request: SNRequest) {
        if request === self.request { continuation.finish() }
    }
}
