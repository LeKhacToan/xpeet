import CoreMotion

/// Production `MotionProvider`: device motion at 50 Hz, delivered in batches of 5 (about 10 per second), so the
/// main actor is touched 10 times a second, not 50 (specs/speed-accuracy R2).
@MainActor
final class CoreMotionProvider: MotionProvider {
    static let sampleRate = 50.0
    static let batchSize = 5

    /// Apple: create only one motion manager per app. Created on first use.
    private lazy var manager = CMMotionManager()

    func motionUpdates() -> AsyncStream<[MotionSample]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            guard manager.isDeviceMotionAvailable else {
                continuation.finish()
                return
            }
            let pipeline = MotionPipeline(batchSize: Self.batchSize, continuation: continuation)
            manager.deviceMotionUpdateInterval = 1 / Self.sampleRate
            // Z vertical, X arbitrary: no compass, and no extra CPU for magnetometer correction.
            manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: pipeline.queue) { motion, error in
                if error != nil {
                    continuation.finish()
                    return
                }
                guard let motion else { return }
                pipeline.append(MotionSample(motion))
            }
            let manager = manager
            continuation.onTermination = { _ in
                Task { @MainActor in manager.stopDeviceMotionUpdates() }
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

    func append(_ sample: MotionSample) {
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
