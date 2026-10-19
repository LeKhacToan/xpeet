import CoreLocation

/// Production `SpeedProvider`: live location updates for driving, plus a manager used only for authorization.
@MainActor
final class CoreLocationSpeedProvider: NSObject, SpeedProvider {
    private let manager = CLLocationManager()
    private var authorizationContinuations: [UUID: AsyncStream<LocationAuthorization>.Continuation] = [:]

    override init() {
        super.init()
        manager.delegate = self
    }

    func authorizationUpdates() -> AsyncStream<LocationAuthorization> {
        let (stream, continuation) = AsyncStream.makeStream(of: LocationAuthorization.self)
        let id = UUID()
        authorizationContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.authorizationContinuations[id] = nil }
        }
        Task { await publishAuthorization() }
        return stream
    }

    func speedUpdates() -> AsyncStream<SpeedSample> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    for try await update in CLLocationUpdate.liveUpdates(.automotiveNavigation) {
                        guard let location = update.location else { continue }
                        continuation.yield(SpeedSample(
                            metersPerSecond: location.speed,
                            accuracy: location.speedAccuracy,
                            isStationary: update.isDeviceStationary,
                            timestamp: location.timestamp
                        ))
                    }
                } catch {
                    // The sequence ends on error; the ViewModel falls back to Acquiring when samples go stale.
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    private func publishAuthorization() async {
        // locationServicesEnabled() blocks, so keep it off the main actor.
        let servicesEnabled = await Task.detached { CLLocationManager.locationServicesEnabled() }.value
        let authorization = servicesEnabled ? Self.authorization(from: manager.authorizationStatus) : .servicesOff
        authorizationContinuations.values.forEach { $0.yield(authorization) }
    }

    private static func authorization(from status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        @unknown default: .denied
        }
    }
}

extension CoreLocationSpeedProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in await self.publishAuthorization() }
    }
}

private protocol LegacyStationaryReporting {
    var isStationary: Bool { get }
}

// `isStationary` is deprecated in favor of `stationary`, which is iOS 18+. Reading it through
// a protocol keeps the iOS 17 path without a deprecation warning.
extension CLLocationUpdate: LegacyStationaryReporting {}

private extension CLLocationUpdate {
    var isDeviceStationary: Bool {
        if #available(iOS 18.0, *) {
            return stationary
        }
        return (self as LegacyStationaryReporting).isStationary
    }
}
