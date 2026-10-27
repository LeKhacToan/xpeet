import Foundation

/// A small disk cache for map tiles (specs/osm-map R12), kept by `URLSessionTileFetcher`. Each tile is stored with
/// when it expires and its validators, so a stale tile can be revalidated and still served while offline.
/// Least recently used tiles go first once it holds more than `capacity` bytes.
actor TileCache {
    struct Entry: Codable, Equatable, Sendable {
        var expires: Date
        var etag: String?
        var lastModified: String?
    }

    struct Cached: Sendable {
        var data: Data
        var entry: Entry
    }

    static let capacity = 150 * 1_024 * 1_024
    /// Trimming walks the folder, so it runs only after this many new bytes.
    static let trimEvery = 8 * 1_024 * 1_024

    private let folder: URL
    private let capacity: Int
    private var bytesSinceTrim = 0

    init(folder: URL, capacity: Int = TileCache.capacity) {
        self.folder = folder
        self.capacity = capacity
    }

    /// `Caches/Tiles`: the system may purge it, and it is never backed up.
    static var standard: TileCache {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return TileCache(folder: caches.appending(path: "Tiles", directoryHint: .isDirectory))
    }

    func cached(_ key: TileKey) -> Cached? {
        guard let data = try? Data(contentsOf: dataURL(key)),
              let meta = try? Data(contentsOf: metaURL(key)),
              let entry = try? JSONDecoder().decode(Entry.self, from: meta) else { return nil }
        touch(key)
        return Cached(data: data, entry: entry)
    }

    func store(_ data: Data, entry: Entry, for key: TileKey) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: dataURL(key), options: .atomic)
            try JSONEncoder().encode(entry).write(to: metaURL(key), options: .atomic)
        } catch {
            return
        }
        bytesSinceTrim += data.count
        if bytesSinceTrim >= Self.trimEvery { trim() }
    }

    /// A 304: same tile, new expiry.
    func refresh(_ entry: Entry, for key: TileKey) {
        try? JSONEncoder().encode(entry).write(to: metaURL(key), options: .atomic)
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: folder)
        bytesSinceTrim = 0
    }

    /// Deletes the least recently used tiles until the cache is under 90% of `capacity`.
    func trim() {
        bytesSinceTrim = 0
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        let tiles = files.filter { $0.pathExtension == "tile" }.compactMap { url -> (url: URL, size: Int, used: Date)? in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return (url, values?.fileSize ?? 0, values?.contentModificationDate ?? .distantPast)
        }
        var total = tiles.reduce(0) { $0 + $1.size }
        guard total > capacity else { return }
        for tile in tiles.sorted(by: { $0.used < $1.used }) where total > capacity * 9 / 10 {
            try? FileManager.default.removeItem(at: tile.url)
            try? FileManager.default.removeItem(at: tile.url.deletingPathExtension().appendingPathExtension("meta"))
            total -= tile.size
        }
    }

    private func touch(_ key: TileKey) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: dataURL(key).path)
    }

    private func dataURL(_ key: TileKey) -> URL {
        folder.appending(path: "\(key.z)-\(key.x)-\(key.y).tile", directoryHint: .notDirectory)
    }

    private func metaURL(_ key: TileKey) -> URL {
        folder.appending(path: "\(key.z)-\(key.x)-\(key.y).meta", directoryHint: .notDirectory)
    }
}
