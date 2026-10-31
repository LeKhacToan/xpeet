import CoreLocation

/// Production `SpeedProvider`: live location updates for driving, plus a manager used only for authorization.
@MainActor
final class CoreLocationSpeedProvider: NSObject, SpeedProvider {
    /// Created on first use, so a provider that is built but never run costs nothing.
    private lazy var manager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        return manager
    }()
    private var authorizationContinuations: [UUID: AsyncStream<LocationAuthorization>.Continuation] = [:]

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

    func speedUpdates() -> AsyncStream<LocationUpdate> {
        AsyncStream { continuation in
            let manager = manager
            let task = Task {
                // Not reset on restart: a replayed fix after a restart is still a duplicate.
                var last: (timestamp: Date, isStationary: Bool)?
                // Restart the sequence if it ends or throws, so a transient error doesn't stop updates until relaunch.
                while !Task.isCancelled {
                    do {
                        for try await update in CLLocationUpdate.liveUpdates(.automotiveNavigation) {
                            // Before the location check: iOS may send "unavailable" along with the last known location.
                            if update.isLocationUnavailable { continuation.yield(.unavailable) }
                            guard let location = update.location else { continue }
                            // iOS repeats the last fix (e.g. while paused); a repeat is not a new measurement. It still
                            // passes when only the stationary flag changed: that is how a stop arrives.
                            let isStationary = update.isDeviceStationary
                            if let last, location.timestamp <= last.timestamp, isStationary == last.isStationary { continue }
                            last = (location.timestamp, isStationary)
                            let sample = SpeedSample(
                                metersPerSecond: location.speed,
                                accuracy: location.speedAccuracy,
                                isStationary: isStationary,
                                timestamp: location.timestamp,
                                latitude: location.coordinate.latitude,
                                longitude: location.coordinate.longitude,
                                horizontalAccuracy: location.horizontalAccuracy,
                                course: location.course,
                                courseAccuracy: location.courseAccuracy
                            )
                            // Marked with the setting as it is now, so a rough fix is never used, even one that
                            // arrives before the first authorization value (specs/precise-location R10).
                            continuation.yield(Self.update(for: sample, accuracy: manager.accuracyAuthorization))
                        }
                    } catch {
                        // Meanwhile the ViewModel falls back to Acquiring once the last fix goes stale.
                    }
                    try? await Task.sleep(for: .seconds(1))
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
        let authorization = Self.authorization(
            servicesEnabled: servicesEnabled,
            status: manager.authorizationStatus,
            accuracy: manager.accuracyAuthorization
        )
        authorizationContinuations.values.forEach { $0.yield(authorization) }
    }

    /// Precise Location matters only once location is allowed (specs/precise-location R2).
    nonisolated static func authorization(
        servicesEnabled: Bool,
        status: CLAuthorizationStatus,
        accuracy: CLAccuracyAuthorization
    ) -> LocationAuthorization {
        guard servicesEnabled else { return .servicesOff }
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorizedAlways, .authorizedWhenInUse:
            return accuracy == .reducedAccuracy ? .authorizedApproximate : .authorized
        @unknown default: return .denied
        }
    }

    /// A fix passed on with Precise Location off is marked rough (specs/precise-location R10).
    nonisolated static func update(for sample: SpeedSample, accuracy: CLAccuracyAuthorization) -> LocationUpdate {
        accuracy == .reducedAccuracy ? .approximateFix(sample) : .fix(sample)
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

    /// iOS 18+ only. On iOS 17 a gap is detected from time since the last fix (specs/speed-accuracy R17).
    var isLocationUnavailable: Bool {
        if #available(iOS 18.0, *) {
            return locationUnavailable
        }
        return false
    }
}
