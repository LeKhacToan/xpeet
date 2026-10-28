import CoreImage
import CoreImage.CIFilterBuiltins
import os

/// One map's tiles, decoded and recoloured into the light style, in memory (specs/osm-map R33, R34), so they draw at
/// once and can stand in for each other while another zoom loads.
/// - Loads go through `TileFetcher` and so its disk cache: newest request first, `concurrentLoads` at a time, and at
///   most `queueLimit` waiting.
/// - A queued tile two or more zoom levels away from what the map last drew is dropped before it starts.
/// - A tile that failed isn't asked for again for `retryDelay`, doubling with each failure up to `longestRetryDelay`,
///   so a refusing server isn't asked on every redraw.
/// - `stop()` when the map is gone: nothing queued starts after it (R11).
final class TileImages: @unchecked Sendable {
    static let memoryLimit = 40 * 1_024 * 1_024
    static let concurrentLoads = 6
    static let queueLimit = 64
    static let retryDelay: TimeInterval = 15
    static let longestRetryDelay: TimeInterval = 120

    enum Event: Equatable, Sendable {
        case loaded(TileKey)
        /// The tile may be asked for again after `retryIn` seconds.
        case failed(TileKey, retryIn: TimeInterval)
    }

    private struct Failure {
        var retryAt: TimeInterval
        var count: Int
    }

    private struct State {
        var queued: [TileKey] = []
        var pending: Set<TileKey> = []
        var running = 0
        var drawnZoom = 0
        var isStopped = false
        var failures: [TileKey: Failure] = [:]
    }

    /// Each finished load, so the map can redraw that tile's area.
    let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private let fetcher: TileFetcher
    private let now: @Sendable () -> TimeInterval
    private let images = NSCache<NSNumber, CGImage>()
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(fetcher: TileFetcher, now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.fetcher = fetcher
        self.now = now
        (events, continuation) = AsyncStream.makeStream(of: Event.self)
        images.totalCostLimit = Self.memoryLimit
    }

    func image(_ key: TileKey) -> CGImage? {
        images.object(forKey: Self.id(key))
    }

    /// The zoom the map is drawing now.
    func noteDrawn(zoom: Int) {
        state.withLock { $0.drawnZoom = zoom }
    }

    /// Queues a tile that isn't in memory; `events` reports how its load ends.
    func request(_ key: TileKey) {
        let time = now()
        let isNew = state.withLock { state in
            guard !state.isStopped, !state.pending.contains(key), image(key) == nil,
                  state.failures[key].map({ $0.retryAt <= time }) ?? true else { return false }
            state.pending.insert(key)
            state.queued.append(key)
            if state.queued.count > Self.queueLimit { state.pending.remove(state.queued.removeFirst()) }
            return true
        }
        if isNew { startLoads() }
    }

    /// The map is gone: queued tiles are dropped and no new ones are taken. Loads already running finish.
    func stop() {
        state.withLock { state in
            state.isStopped = true
            state.queued.forEach { state.pending.remove($0) }
            state.queued.removeAll()
        }
        continuation.finish()
    }

    /// Whether any tile is queued or loading.
    var isBusy: Bool {
        state.withLock { !$0.pending.isEmpty }
    }

    // MARK: Private

    private func startLoads() {
        let starting = state.withLock { state in
            var starting: [TileKey] = []
            while !state.isStopped, state.running < Self.concurrentLoads, let next = state.queued.popLast() {
                if abs(next.z - state.drawnZoom) >= 2 {
                    state.pending.remove(next)
                    continue
                }
                state.running += 1
                starting.append(next)
            }
            return starting
        }
        for key in starting {
            Task.detached(priority: .userInitiated) { await self.load(key) }
        }
    }

    private func load(_ key: TileKey) async {
        let image = try? await Self.recoloured(fetcher.tile(key))
        if let image {
            images.setObject(image, forKey: Self.id(key), cost: image.bytesPerRow * image.height)
        }
        let time = now()
        let retryIn: TimeInterval? = state.withLock { state in
            state.pending.remove(key)
            state.running -= 1
            guard image == nil else {
                state.failures[key] = nil
                return nil
            }
            if state.failures.count > 256 { state.failures = state.failures.filter { $0.value.retryAt > time } }
            let count = (state.failures[key]?.count ?? 0) + 1
            let delay = min(Self.retryDelay * pow(2, Double(count - 1)), Self.longestRetryDelay)
            state.failures[key] = Failure(retryAt: time + delay, count: count)
            return delay
        }
        continuation.yield(retryIn.map { .failed(key, retryIn: $0) } ?? .loaded(key))
        startLoads()
    }

    private static func id(_ key: TileKey) -> NSNumber {
        NSNumber(value: key.z << 40 | key.x << 20 | key.y)
    }

    // MARK: Recolouring

    /// On the CPU: a 256 px colour cube is cheap, and the GPU isn't available once the app is in the background.
    private static let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
    private static let cube = TilePalette.cube().withUnsafeBufferPointer { Data(buffer: $0) }
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)

    /// A tile in the light style (R33), or nil if `data` isn't an image.
    static func recoloured(_ data: Data) -> CGImage? {
        guard let input = CIImage(data: data) else { return nil }
        let filter = CIFilter.colorCubeWithColorSpace()
        filter.inputImage = input
        filter.cubeDimension = Float(TilePalette.cubeSize)
        filter.cubeData = cube
        filter.colorSpace = sRGB
        guard let output = filter.outputImage else { return nil }
        return context.createCGImage(output, from: input.extent)
    }
}
