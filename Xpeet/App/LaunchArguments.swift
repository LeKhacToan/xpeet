import Foundation

/// Debug switches passed at launch, e.g. `-XpeetRecordDrives YES`. Read from the argument domain only, so a value
/// that ended up in the app's saved settings can never turn one on.
enum LaunchArguments {
    static var current: [String: Any] {
        UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
    }

    static func bool(_ key: String, in arguments: [String: Any] = current) -> Bool {
        switch arguments[key] {
        case let value as String: (value as NSString).boolValue
        case let value as NSNumber: value.boolValue
        default: false
        }
    }
}
