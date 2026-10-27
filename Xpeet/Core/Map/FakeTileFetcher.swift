#if DEBUG
import UIKit

/// In-memory `TileFetcher` for previews and unit tests: plain tiles, never the network.
actor FakeTileFetcher: TileFetcher {
    /// One 256 px tile in a muted map colour.
    static let tileData: Data = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).pngData { context in
        UIColor(red: 0.85, green: 0.82, blue: 0.76, alpha: 1).setFill()
        context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
    }

    private(set) var requested: [TileKey] = []
    private(set) var clearCount = 0
    private var isFailing = false
    private var continuations: [UUID: AsyncStream<TileStatus>.Continuation] = [:]

    init(isFailing: Bool = false) {
        self.isFailing = isFailing
    }

    func tile(_ key: TileKey) async throws -> Data {
        requested.append(key)
        if isFailing { throw URLError(.notConnectedToInternet) }
        return Self.tileData
    }

    func statusUpdates() -> AsyncStream<TileStatus> {
        let (stream, continuation) = AsyncStream.makeStream(of: TileStatus.self)
        continuations[UUID()] = continuation
        return stream
    }

    func clearCache() {
        clearCount += 1
    }

    func send(_ status: TileStatus) {
        continuations.values.forEach { $0.yield(status) }
    }

    var subscriberCount: Int { continuations.count }
}
#endif
