import Foundation

/// Whether the latest tile request reached the tile server (specs/osm-map R13).
enum TileStatus: Equatable, Sendable {
    case ok
    case offline
}

/// Loads map tiles. Called from MapKit's background queues, so it is `Sendable` and not tied to the main actor.
protocol TileFetcher: Sendable {
    func tile(_ key: TileKey) async throws -> Data
    func statusUpdates() async -> AsyncStream<TileStatus>
    /// "Delete all trips" also clears the tiles, which show where I looked (R25).
    func clearCache() async
}

enum TileError: Error, Equatable {
    case badURL
    case http(Int)
}

/// Production `TileFetcher` (specs/osm-map R10-R13), and the only code that uses the network.
/// - Every request names the app in its User-Agent and never asks to bypass caches.
/// - A tile that is still fresh is served from `TileCache` with no request; a stale one is revalidated.
/// - Without network, or when the server refuses, a stale copy is served and the status turns `.offline`.
/// - Requests for the same tile share one download: MapKit can't cancel loads.
actor URLSessionTileFetcher: TileFetcher {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    /// Used when a response has no cache headers (R12; the OSM tile policy's minimum).
    static let defaultFreshness: TimeInterval = 7 * 24 * 3_600

    private let source: TileSource
    private let cache: TileCache
    private let transport: Transport
    private let userAgent: String
    private let now: @Sendable () -> Date
    private var inFlight: [TileKey: Task<Data, Error>] = [:]
    private var status: TileStatus?
    private var continuations: [UUID: AsyncStream<TileStatus>.Continuation] = [:]

    init(
        source: TileSource = TileSource(),
        cache: TileCache = .standard,
        transport: @escaping Transport = URLSessionTileFetcher.sessionTransport(),
        version: String = TileSource.appVersion,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.cache = cache
        self.transport = transport
        self.userAgent = TileSource.userAgent(version: version)
        self.now = now
    }

    func tile(_ key: TileKey) async throws -> Data {
        if let running = inFlight[key] { return try await running.value }
        let task = Task { try await load(key) }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }

    func statusUpdates() -> AsyncStream<TileStatus> {
        let (stream, continuation) = AsyncStream.makeStream(of: TileStatus.self)
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { _ in Task { await self.removeContinuation(id) } }
        if let status { continuation.yield(status) }
        return stream
    }

    func clearCache() async {
        await cache.removeAll()
    }

    // MARK: Private

    private func load(_ key: TileKey) async throws -> Data {
        let cached = await cache.cached(key)
        if let cached, cached.entry.expires > now() { return cached.data }
        guard let url = source.url(for: key) else { throw TileError.badURL }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let etag = cached?.entry.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified = cached?.entry.lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            publish(.offline)
            if let cached { return cached.data }
            throw error
        }

        switch response.statusCode {
        case 200..<300:
            await cache.store(data, entry: Self.entry(for: response, previous: nil, now: now()), for: key)
            publish(.ok)
            return data
        case 304 where cached != nil:
            guard let cached else { break }
            await cache.refresh(Self.entry(for: response, previous: cached.entry, now: now()), for: key)
            publish(.ok)
            return cached.data
        default:
            break
        }
        publish(.offline)
        if let cached { return cached.data }
        throw TileError.http(response.statusCode)
    }

    private func publish(_ next: TileStatus) {
        guard next != status else { return }
        status = next
        continuations.values.forEach { $0.yield(next) }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    /// Expiry from `Cache-Control: max-age` (less `Age`), else `Expires`, else `defaultFreshness`. A 304 keeps the
    /// validators it doesn't repeat.
    static func entry(for response: HTTPURLResponse, previous: TileCache.Entry?, now: Date) -> TileCache.Entry {
        let etag = response.value(forHTTPHeaderField: "ETag") ?? previous?.etag
        let lastModified = response.value(forHTTPHeaderField: "Last-Modified") ?? previous?.lastModified
        return TileCache.Entry(expires: expiry(for: response, now: now), etag: etag, lastModified: lastModified)
    }

    private static func expiry(for response: HTTPURLResponse, now: Date) -> Date {
        if let cacheControl = response.value(forHTTPHeaderField: "Cache-Control")?.lowercased() {
            let directives = cacheControl.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if directives.contains("no-store") || directives.contains("no-cache") { return now }
            if let maxAge = directives.lazy.compactMap({ $0.hasPrefix("max-age=") ? TimeInterval($0.dropFirst(8)) : nil }).first {
                let age = response.value(forHTTPHeaderField: "Age").flatMap(TimeInterval.init) ?? 0
                return now.addingTimeInterval(max(0, maxAge - age))
            }
        }
        if let expires = response.value(forHTTPHeaderField: "Expires"), let date = httpDate.date(from: expires) {
            return date
        }
        return now.addingTimeInterval(defaultFreshness)
    }

    private static let httpDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    /// An ephemeral session with no `URLCache`: `TileCache` decides what is fresh. It adds no cache headers.
    static func sessionTransport() -> Transport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: configuration)
        return { request in
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            return (data, http)
        }
    }
}
