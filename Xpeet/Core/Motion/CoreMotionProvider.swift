import CoreMotion

/// Production `MotionProvider`: device motion at 50 Hz, delivered in batches of 5 (about 10 per second), so the
/// main actor is touched 10 times a second, not 50 (specs/speed-accuracy R2).
@MainActor
final class CoreMotionProvider: MotionProvider {
    static let sampleRate = 50.0
    static let batchSize = 5

    /// Apple: create only one motion manager per app. Created on first use.
    private lazy var manager = CMMotionManager()
    /// The newest stream. An older stream ending (after a quick background/foreground) must not stop the manager
    /// the newer one is using.
    private var generation = 0

    func motionUpdates() -> AsyncStream<[MotionSample]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            guard manager.isDeviceMotionAvailable else {
                continuation.finish()
                return
            }
            generation += 1
            let current = generation
            let pipeline = MotionPipeline(batchSize: Self.batchSize, continuation: continuation)
            manager.deviceMotionUpdateInterval = 1 / Self.sampleRate
            // Z vertical, X arbitrary: no compass, and no extra CPU for magnetometer correction.
            manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: pipeline.queue, withHandler: pipeline.handler)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == current else { return }
                    self.manager.stopDeviceMotionUpdates()
                }
            }
        }
    }
}

/// Collects samples into batches. Every mutable field is confined to `queue`, where Core Motion calls back.
private final class MotionPipeline: @unchecked Sendable {
    let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "app.plouton.xpeet.motion"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let batchSize: Int
    private let continuation: AsyncStream<[MotionSample]>.Continuation
    private var batch: [MotionSample] = []

    init(batchSize: Int, continuation: AsyncStream<[MotionSample]>.Continuation) {
        self.batchSize = batchSize
        self.continuation = continuation
        batch.reserveCapacity(batchSize)
    }

    /// Built here, outside the main actor, because Core Motion calls it on `queue`.
    var handler: CMDeviceMotionHandler {
        { [self] motion, error in
            if error != nil {
                continuation.finish()
                return
            }
            guard let motion else { return }
            append(MotionSample(motion))
        }
    }

    private func append(_ sample: MotionSample) {
        batch.append(sample)
        guard batch.count >= batchSize else { return }
        continuation.yield(batch)
        batch.removeAll(keepingCapacity: true)
    }
}

private extension MotionSample {
    /// Copies out of the non-Sendable `CMDeviceMotion` at once, on the motion queue.
    init(_ motion: CMDeviceMotion) {
        let standardGravity = 9.80665
        let acceleration = motion.userAcceleration
        let gravity = motion.gravity
        let rotation = motion.rotationRate
        self.init(
            timestamp: motion.timestamp,
            userAcceleration: Vector3(x: acceleration.x, y: acceleration.y, z: acceleration.z) * standardGravity,
            gravity: Vector3(x: gravity.x, y: gravity.y, z: gravity.z),
            rotationRate: Vector3(x: rotation.x, y: rotation.y, z: rotation.z)
        )
    }
}
