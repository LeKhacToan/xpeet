import Foundation

/// Keeps one route file per trip (specs/osm-map R19-R20). Files can't be read while the phone is locked and the
/// folder stays out of device backups. Nothing here ever crashes: a bad file is no route.
struct RouteStore {
    typealias Writer = (Data, URL, Data.WritingOptions) throws -> Void

    /// Complete protection: unreadable while the phone is locked (R20).
    static let writingOptions: Data.WritingOptions = [.atomic, .completeFileProtection]

    let folder: URL
    private let write: Writer

    /// `write` is a seam for tests: the Simulator neither enforces nor reports file protection.
    init(folder: URL, write: @escaping Writer = { data, url, options in try data.write(to: url, options: options) }) {
        self.folder = folder
        self.write = write
    }

    /// `Application Support/Routes`.
    static var standard: RouteStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return RouteStore(folder: base.appending(path: "Routes", directoryHint: .isDirectory))
    }

    /// The stored route, or nil. An unreadable file is deleted.
    func load(id: UUID) -> Route? {
        let url = fileURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let route = try? JSONDecoder().decode(Route.self, from: data) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return route
    }

    /// False when the write failed (e.g. the phone just locked); the next save tries again.
    @discardableResult
    func save(_ route: Route, id: UUID) -> Bool {
        do {
            try prepareFolder()
            try write(try JSONEncoder().encode(route), fileURL(for: id), Self.writingOptions)
            return true
        } catch {
            return false
        }
    }

    /// Deletes every route whose trip is gone (R19).
    func prune(keeping ids: Set<UUID>) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where UUID(uuidString: file.deletingPathExtension().lastPathComponent).map(ids.contains) != true {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// "Delete all trips" (R25).
    func removeAll() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func fileURL(for id: UUID) -> URL {
        folder.appending(path: "\(id.uuidString).json", directoryHint: .notDirectory)
    }

    private func prepareFolder() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var folder = folder
        try folder.setResourceValues(values)
    }
}
