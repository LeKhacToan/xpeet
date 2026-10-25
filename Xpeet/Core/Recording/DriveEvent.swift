import Foundation

/// One line of a recorded drive (specs/speed-accuracy R22). Compiled in every build so the ViewModel can hold a
/// recorder; only `DriveRecorder`, which writes files, is Debug-only.
enum DriveEvent: Equatable, Sendable {
    case header(DriveHeader)
    case fix(SpeedSample, arrival: Date)
    case unavailable(arrival: Date)
    case motion(MotionSample, arrival: Date)
    case shown(DriveShown)
}

struct DriveHeader: Equatable, Codable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion = Self.currentFormatVersion
    var startedAt: Date
    /// Hardware model, e.g. "iPhone16,1".
    var device: String
    var system: String
    var constants: [String: Double]

    /// Header for this device, now.
    static func current(startedAt: Date, constants: [String: Double]) -> DriveHeader {
        var systemInfo = utsname()
        uname(&systemInfo)
        let model = withUnsafeBytes(of: &systemInfo.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return DriveHeader(
            startedAt: startedAt,
            device: model,
            system: ProcessInfo.processInfo.operatingSystemVersionString,
            constants: constants
        )
    }
}

/// What the screen showed at one moment, with both estimates behind it.
struct DriveShown: Equatable, Codable, Sendable {
    var time: Date
    /// Whole units in `unit`; nil for "--".
    var displayed: Int?
    var unit: String
    /// "acquiring", "live", "liveWeak" or "unavailable".
    var state: String
    var source: SpeedEstimator.Source?
    var gpsOnly: SpeedEstimator.Estimate?
    var fused: SpeedEstimator.Estimate?
    var inGap: Bool
}

/// Receives drive events. Must never block or fail the caller (R23).
protocol DriveLogging: Sendable {
    func record(_ event: DriveEvent)
    /// Ends the recording; later events are dropped.
    func finish()
}

enum DriveLog {
    /// A new recorder for one run of the speed screen, or nil when recording is off. Always nil in Release.
    static func makeRecorder() -> DriveLogging? {
        #if DEBUG
        DriveRecorder.startIfEnabled()
        #else
        nil
        #endif
    }
}

// MARK: - JSON Lines encoding

extension DriveEvent: Codable {
    private enum Kind: String, Codable {
        case header, fix, unavailable, motion, shown
    }

    private enum CodingKeys: String, CodingKey {
        case type, arrival, header, fix, motion, shown
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .header:
            self = .header(try container.decode(DriveHeader.self, forKey: .header))
        case .fix:
            self = .fix(try container.decode(SpeedSample.self, forKey: .fix), arrival: try container.decode(Date.self, forKey: .arrival))
        case .unavailable:
            self = .unavailable(arrival: try container.decode(Date.self, forKey: .arrival))
        case .motion:
            self = .motion(
                try container.decode(MotionSample.self, forKey: .motion),
                arrival: try container.decode(Date.self, forKey: .arrival)
            )
        case .shown:
            self = .shown(try container.decode(DriveShown.self, forKey: .shown))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .header(let header):
            try container.encode(Kind.header, forKey: .type)
            try container.encode(header, forKey: .header)
        case let .fix(sample, arrival):
            try container.encode(Kind.fix, forKey: .type)
            try container.encode(sample, forKey: .fix)
            try container.encode(arrival, forKey: .arrival)
        case .unavailable(let arrival):
            try container.encode(Kind.unavailable, forKey: .type)
            try container.encode(arrival, forKey: .arrival)
        case let .motion(sample, arrival):
            try container.encode(Kind.motion, forKey: .type)
            try container.encode(sample, forKey: .motion)
            try container.encode(arrival, forKey: .arrival)
        case .shown(let shown):
            try container.encode(Kind.shown, forKey: .type)
            try container.encode(shown, forKey: .shown)
        }
    }

    /// Dates as seconds since 1970, so lines stay short and easy to read in other tools.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
