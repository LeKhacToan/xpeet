import Foundation

/// One raster tile: zoom, column and row in the usual slippy-map scheme.
struct TileKey: Hashable, Sendable {
    var z: Int
    var x: Int
    var y: Int
}

/// Where map tiles come from (specs/osm-map R10-R11). The address can be changed without an app update, through
/// `UserDefaults` (e.g. the launch argument `-map.tileURLTemplate <url>`).
struct TileSource: Equatable, Sendable {
    static let defaultTemplate = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
    static let overrideKey = "map.tileURLTemplate"
    static let zoomRange = 0...19
    /// Contact for the tile server's operators, as the OSM tile policy asks.
    static let contact = "https://github.com/LeKhacToan/xpeet"

    let template: String

    init(defaults: UserDefaults = .standard) {
        let override = defaults.string(forKey: Self.overrideKey)
        template = override.flatMap { Self.isValid($0) ? $0 : nil } ?? Self.defaultTemplate
    }

    /// HTTPS only, with all three placeholders (R10).
    static func isValid(_ template: String) -> Bool {
        guard template.lowercased().hasPrefix("https://"),
              ["{z}", "{x}", "{y}"].allSatisfy(template.contains) else { return false }
        return fill(template, TileKey(z: 0, x: 0, y: 0)) != nil
    }

    func url(for key: TileKey) -> URL? {
        Self.fill(template, key)
    }

    /// "Xpeet/1.0.0 (+https://github.com/LeKhacToan/xpeet)": names the app, as the OSM tile policy requires (R11).
    static func userAgent(version: String) -> String {
        "Xpeet/\(version) (+\(contact))"
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private static func fill(_ template: String, _ key: TileKey) -> URL? {
        URL(string: template
            .replacingOccurrences(of: "{z}", with: "\(key.z)")
            .replacingOccurrences(of: "{x}", with: "\(key.x)")
            .replacingOccurrences(of: "{y}", with: "\(key.y)"))
    }
}
