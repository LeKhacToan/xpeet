import CoreLocation
import XCTest
@testable import Xpeet

/// The provider's pure mapping from Core Location's settings (specs/precise-location R1, R2, R10).
final class LocationAuthorizationTests: XCTestCase {
    private let allowed: [CLAuthorizationStatus] = [.authorizedWhenInUse, .authorizedAlways]

    // MARK: - R1

    func testAllowedWithFullAccuracyIsAuthorized() {
        for status in allowed {
            XCTAssertEqual(
                CoreLocationSpeedProvider.authorization(servicesEnabled: true, status: status, accuracy: .fullAccuracy),
                .authorized, "\(status.rawValue)"
            )
        }
    }

    func testAllowedWithReducedAccuracyIsApproximate() {
        for status in allowed {
            XCTAssertEqual(
                CoreLocationSpeedProvider.authorization(servicesEnabled: true, status: status, accuracy: .reducedAccuracy),
                .authorizedApproximate, "\(status.rawValue)"
            )
        }
    }

    // MARK: - R2

    func testMappingForEveryCombination() {
        let statuses: [CLAuthorizationStatus] = [.notDetermined, .restricted, .denied, .authorizedWhenInUse, .authorizedAlways]
        for servicesEnabled in [true, false] {
            for status in statuses {
                for accuracy in [CLAccuracyAuthorization.fullAccuracy, .reducedAccuracy] {
                    let expected: LocationAuthorization
                    if !servicesEnabled {
                        expected = .servicesOff
                    } else {
                        switch status {
                        case .notDetermined: expected = .notDetermined
                        case .restricted: expected = .restricted
                        case .denied: expected = .denied
                        default: expected = accuracy == .reducedAccuracy ? .authorizedApproximate : .authorized
                        }
                    }
                    XCTAssertEqual(
                        CoreLocationSpeedProvider.authorization(
                            servicesEnabled: servicesEnabled, status: status, accuracy: accuracy
                        ),
                        expected,
                        "services \(servicesEnabled), status \(status.rawValue), accuracy \(accuracy.rawValue)"
                    )
                }
            }
        }
    }

    func testNotDeterminedIgnoresAccuracy() {
        for accuracy in [CLAccuracyAuthorization.fullAccuracy, .reducedAccuracy] {
            XCTAssertEqual(
                CoreLocationSpeedProvider.authorization(servicesEnabled: true, status: .notDetermined, accuracy: accuracy),
                .notDetermined
            )
        }
    }

    // MARK: - R10

    func testFixMarkedOnlyWithReducedAccuracy() {
        let sample = SpeedSample(metersPerSecond: 10, accuracy: 0.5, isStationary: false, timestamp: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(CoreLocationSpeedProvider.update(for: sample, accuracy: .fullAccuracy), .fix(sample))
        XCTAssertEqual(CoreLocationSpeedProvider.update(for: sample, accuracy: .reducedAccuracy), .approximateFix(sample))
    }
}
