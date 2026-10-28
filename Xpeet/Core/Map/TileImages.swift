import CoreImage
import CoreImage.CIFilterBuiltins
import os

/// One map's tiles, decoded and recoloured into the light style, in memory (specs/osm-map R33, R34), so they draw at
/// once and can stand in for each other while another zoom loads.
/// - Loads go through `TileFetcher` and so its disk cache: newest request first, `concurrentLoads` at a time.
/// - A queued tile two or more zoom levels away from what the map last drew is dropped before it starts.
/// - A tile that failed isn't asked for again for `retryDelay`, so a refusing server isn't asked on every redraw.
final class TileImages: @unchecked Sendable {
    static let memoryLimit = 40 * 1_024 * 1_024
    static let concurrentLoads = 6
    static let retryDelay: TimeInterval = 15

    private struct Request {
        var key: TileKey
        var loaded: @Sendable () -> Void
    }

    private struct State {
        var queued: [Request] = []
        var pending: Set<TileKey> = []
        var running = 0
        var drawnZoom = 0
        var retryAfter: [TileKey: TimeInterval] = [:]
    }

    private let fetcher: TileFetcher
    private let now: @Sendable () -> TimeInterval
    private let images = NSCache<NSNumber, CGImage>()
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(fetcher: TileFetcher, now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.fetcher = fetcher
        self.now = now
        images.totalCostLimit = Self.memoryLimit
    }

    func image(_ key: TileKey) -> CGImage? {
        images.object(forKey: Self.id(key))
    }

    /// Queues a tile that isn't in memory, for a map drawing at `drawnZoom`; `loaded` runs once it is in memory.
    func request(_ key: TileKey, drawnZoom: Int, loaded: @escaping @Sendable () -> Void) {
        guard image(key) == nil else { return }
        let time = now()
        let isNew = state.withLock { state in
            state.drawnZoom = drawnZoom
            guard !state.pending.contains(key), state.retryAfter[key].map({ $0 <= time }) ?? true else { return false }
            state.pending.insert(key)
            state.queued.append(Request(key: key, loaded: loaded))
            return true
        }
        if isNew { startLoads() }
    }

    /// Whether any tile is queued or loading.
    var isBusy: Bool {
        state.withLock { !$0.pending.isEmpty }
    }

    // MARK: Private

    private func startLoads() {
        let starting = state.withLock { state in
            var starting: [Request] = []
            while state.running < Self.concurrentLoads, let next = state.queued.popLast() {
                if abs(next.key.z - state.drawnZoom) >= 2 {
                    state.pending.remove(next.key)
                    continue
                }
                state.running += 1
                starting.append(next)
            }
            return starting
        }
        for request in starting {
            Task.detached(priority: .userInitiated) { await self.load(request) }
        }
    }

    private func load(_ request: Request) async {
        let image = try? await Self.recoloured(fetcher.tile(request.key))
        if let image {
            images.setObject(image, forKey: Self.id(request.key), cost: image.bytesPerRow * image.height)
        }
        let time = now()
        state.withLock { state in
            state.pending.remove(request.key)
            state.running -= 1
            if image == nil {
                if state.retryAfter.count > 256 { state.retryAfter = state.retryAfter.filter { $0.value > time } }
                state.retryAfter[request.key] = time + Self.retryDelay
            } else {
                state.retryAfter[request.key] = nil
            }
        }
        if image != nil { request.loaded() }
        startLoads()
    }

    private static func id(_ key: TileKey) -> NSNumber {
        NSNumber(value: key.z << 40 | key.x << 20 | key.y)
    }

    // MARK: Recolouring

    private static let context = CIContext(options: [.cacheIntermediates: false])
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
