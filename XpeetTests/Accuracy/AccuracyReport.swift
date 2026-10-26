import Foundation
@testable import Xpeet

/// Measurements from one recorded drive, for `specs/speed-accuracy/results.md` (R29, R30).
struct AccuracyReport {
    struct Gap: Equatable {
        var start: Date
        var duration: TimeInterval
        /// iOS 18+ said "location unavailable" during the gap.
        var reportedUnavailable: Bool
        /// Horizontal accuracy of the first fix after the gap, m.
        var accuracyAfter: Double
    }

    /// A steady stretch for the distance-over-time check (R29).
    struct Stretch: Equatable {
        var start: Date
        var end: Date
        var distance: Double
        /// Distance / time, m/s.
        var distanceSpeed: Double
        /// Time-averaged raw Doppler speed, and the estimate behind the shown number, over the same stretch, m/s.
        var meanDoppler: Double
        var meanShownEstimate: Double?
    }

    static let steadyMinimumSpeed = 50 / 3.6
    /// Speeds within this fraction of the stretch mean count as steady.
    static let steadyTolerance = 0.05
    static let stretchMinimumDistance = 3_000.0
    /// Distance is summed over straight lines between fixes about this far apart (R29).
    static let chordInterval: TimeInterval = 10

    let drive: DriveFile

    /// Fixes with a usable Doppler speed, in time order.
    private var validFixes: [(sample: SpeedSample, arrival: Date)] {
        drive.fixes.filter { $0.sample.metersPerSecond >= 0 && $0.sample.accuracy >= 0 }
    }

    // MARK: R30

    /// Median and 95th percentile of the time between fix timestamps, s.
    var fixInterval: (median: Double, p95: Double)? {
        let times = drive.fixes.map(\.sample.timestamp)
        let intervals = zip(times.dropFirst(), times).map { $0.timeIntervalSince($1) }.filter { $0 > 0 }
        return Self.percentiles(intervals)
    }

    /// How long fixes take to reach the app after their timestamp, s.
    var arrivalLatency: (median: Double, p95: Double)? {
        Self.percentiles(drive.fixes.map { $0.arrival.timeIntervalSince($0.sample.timestamp) })
    }

    /// Fixes without Doppler speed, and how many of those position-derived speed (R13) could have used.
    var missingSpeed: (count: Int, usable: Int, total: Int) {
        var usable = 0
        var goodPositions: [SpeedSample] = []
        var count = 0
        for (sample, _) in drive.fixes {
            let goodPosition = sample.horizontalAccuracy >= 0 && sample.horizontalAccuracy <= SpeedEstimator.positionSpeedMaxAccuracy
            if sample.metersPerSecond < 0 {
                count += 1
                let hasPartner = goodPositions.contains {
                    SpeedEstimator.positionSpeedInterval.contains(sample.timestamp.timeIntervalSince($0.timestamp))
                }
                if goodPosition, hasPartner { usable += 1 }
            }
            if goodPosition { goodPositions.append(sample) }
        }
        return (count, usable, drive.fixes.count)
    }

    var speedAccuracy: (median: Double, p95: Double)? {
        Self.percentiles(validFixes.map(\.sample.accuracy))
    }

    /// σ of the GPS-only estimate while Live, and the share above the weak-signal limit (R20).
    var liveSigma: (median: Double, p95: Double, weakShare: Double)? {
        let sigmas = drive.shown.filter { $0.state.hasPrefix("live") }.compactMap(\.gpsOnly?.sigma)
        guard let spread = Self.percentiles(sigmas) else { return nil }
        let weak = Double(sigmas.filter { $0 > SpeedEstimator.weakSignalSigma }.count) / Double(sigmas.count)
        return (spread.median, spread.p95, weak)
    }

    /// Silences longer than the gap-start interval while moving (R17).
    var gaps: [Gap] {
        let fixes = validFixes
        return zip(fixes, fixes.dropFirst()).compactMap { before, after in
            let duration = after.arrival.timeIntervalSince(before.arrival)
            guard duration > SpeedEstimator.gapStartInterval, before.sample.metersPerSecond > 1,
                  !before.sample.isStationary else { return nil }
            let unavailable = drive.unavailableArrivals.contains { $0 > before.arrival && $0 < after.arrival }
            return Gap(start: before.arrival, duration: duration, reportedUnavailable: unavailable,
                       accuracyAfter: after.sample.horizontalAccuracy)
        }
    }

    /// Mean normalised innovation of the GPS-only filter with k_R = 1, and the k_R that would make the reported
    /// speed accuracy match the innovations seen.
    var speedAccuracyScale: (meanNIS: Double, suggestedScale: Double)? {
        var filter: GPSOnlyFilter?
        var nis: [Double] = []
        var excess = 0.0
        var reported = 0.0
        for (sample, _) in validFixes where !sample.isStationary {
            let measurementVariance = pow(max(sample.accuracy, SpeedEstimator.minimumSpeedAccuracy), 2)
            if var current = filter {
                let prediction = current.predicted(at: sample.timestamp)
                let innovation = sample.metersPerSecond - prediction.speed
                nis.append(innovation * innovation / (prediction.variance + measurementVariance))
                excess += max(0, innovation * innovation - prediction.variance)
                reported += measurementVariance
                _ = current.update(speed: sample.metersPerSecond, variance: measurementVariance, at: sample.timestamp)
                filter = current
            } else {
                filter = GPSOnlyFilter(speed: sample.metersPerSecond, variance: measurementVariance, at: sample.timestamp)
            }
        }
        guard !nis.isEmpty, reported > 0 else { return nil }
        return (nis.reduce(0, +) / Double(nis.count), (excess / reported).squareRoot())
    }

    /// The lag τ that best lines up horizontal acceleration from motion with the change in GPS speed, s. Uses
    /// magnitudes, so turns add noise; the signed forward-axis version comes with fusion (PR 2).
    var reportingDelay: (tau: Double, correlation: Double)? {
        let motion = drive.motion
        guard let offset = motion.map({ $0.arrival.timeIntervalSince1970 - $0.sample.timestamp }).min() else { return nil }
        let horizontal: [(time: Double, magnitude: Double)] = motion.map { sample, _ in
            let gravity = sample.gravity
            let acceleration = sample.userAcceleration
            let vertical = gravity * acceleration.dot(gravity)
            return (sample.timestamp + offset, (acceleration - vertical).length)
        }
        let fixes = validFixes
        let steps: [(start: Double, end: Double, magnitude: Double)] = zip(fixes, fixes.dropFirst()).compactMap { a, b in
            let interval = b.sample.timestamp.timeIntervalSince(a.sample.timestamp)
            guard (0.5...1.5).contains(interval) else { return nil }
            return (a.sample.timestamp.timeIntervalSince1970, b.sample.timestamp.timeIntervalSince1970,
                    abs(b.sample.metersPerSecond - a.sample.metersPerSecond) / interval)
        }
        guard steps.count >= 30 else { return nil }

        var best: (tau: Double, correlation: Double)?
        for tenths in -10...20 {
            let tau = Double(tenths) / 10
            var pairs: [(Double, Double)] = []
            var cursor = 0
            for step in steps {
                let from = step.start - tau
                let to = step.end - tau
                while cursor < horizontal.count, horizontal[cursor].time < from { cursor += 1 }
                var index = cursor
                var sum = 0.0
                var count = 0
                while index < horizontal.count, horizontal[index].time < to {
                    sum += horizontal[index].magnitude
                    count += 1
                    index += 1
                }
                if count > 0 { pairs.append((step.magnitude, sum / Double(count))) }
            }
            if let correlation = Self.correlation(pairs), correlation > (best?.correlation ?? -1) {
                best = (tau, correlation)
            }
        }
        return best
    }

    // MARK: R29

    var steadyStretches: [Stretch] {
        let fixes = validFixes.filter { !$0.sample.isStationary && $0.sample.horizontalAccuracy >= 0 }
        var stretches: [Stretch] = []
        var window: [SpeedSample] = []

        func close() {
            if let stretch = makeStretch(window) { stretches.append(stretch) }
            window.removeAll()
        }

        for (sample, _) in fixes {
            if let last = window.last {
                let mean = window.map(\.metersPerSecond).reduce(0, +) / Double(window.count)
                let continuous = sample.timestamp.timeIntervalSince(last.timestamp) <= SpeedEstimator.gapStartInterval
                let steady = abs(sample.metersPerSecond - mean) <= Self.steadyTolerance * mean
                if !continuous || !steady { close() }
            }
            if sample.metersPerSecond >= Self.steadyMinimumSpeed {
                window.append(sample)
            } else {
                close()
            }
        }
        close()
        return stretches
    }

    private func makeStretch(_ window: [SpeedSample]) -> Stretch? {
        guard let first = window.first, let last = window.last, last.timestamp > first.timestamp else { return nil }
        var distance = 0.0
        var anchor = first
        for sample in window.dropFirst() where sample.timestamp.timeIntervalSince(anchor.timestamp) >= Self.chordInterval {
            distance += SpeedEstimator.distance(from: anchor, to: sample)
            anchor = sample
        }
        if anchor != last { distance += SpeedEstimator.distance(from: anchor, to: last) }
        guard distance >= Self.stretchMinimumDistance else { return nil }

        let elapsed = last.timestamp.timeIntervalSince(first.timestamp)
        let shown: [(Date, Double)] = drive.shown
            .filter { $0.time >= first.timestamp && $0.time <= last.timestamp }
            .compactMap { line in
                let estimate = line.source == .fused ? line.fused : line.gpsOnly
                return estimate.map { (line.time, $0.metersPerSecond) }
            }
        return Stretch(
            start: first.timestamp,
            end: last.timestamp,
            distance: distance,
            distanceSpeed: distance / elapsed,
            meanDoppler: Self.timeAverage(window.map { ($0.timestamp, $0.metersPerSecond) }),
            meanShownEstimate: shown.isEmpty ? nil : Self.timeAverage(shown)
        )
    }

    // MARK: trip-stats R18

    /// The trip distance the app would have shown: the recorded `shown` lines fed through `TripTracker`, exactly
    /// as the ViewModel feeds it (Live: the estimate behind the number; Acquiring; Unavailable).
    var tripDistance: Double {
        var tracker = TripTracker()
        for line in drive.shown {
            let reading: TripReading
            switch line.state {
            case "live", "liveWeak":
                let estimate = line.source == .fused ? line.fused : line.gpsOnly
                reading = .live(metersPerSecond: estimate?.metersPerSecond ?? 0)
            case "acquiring":
                reading = .acquiring
            default:
                reading = .notMeasured
            }
            tracker.update(at: line.time, reading: reading)
        }
        return tracker.current.distance + tracker.history.reduce(0) { $0 + $1.distance }
    }

    /// Distance along the road from positions: straight lines between fixes about `chordInterval` apart, restarting
    /// after any silence longer than the stale interval, so gaps are left out as the trip leaves them out.
    var positionDistance: Double {
        var total = 0.0
        var anchor: SpeedSample?
        var last: SpeedSample?
        for (sample, _) in drive.fixes where sample.horizontalAccuracy >= 0 && !sample.isStationary {
            if let previous = last, sample.timestamp.timeIntervalSince(previous.timestamp) > TripTracker.maxInterval {
                if let start = anchor { total += SpeedEstimator.distance(from: start, to: previous) }
                anchor = sample
            } else if let start = anchor, sample.timestamp.timeIntervalSince(start.timestamp) >= Self.chordInterval {
                total += SpeedEstimator.distance(from: start, to: sample)
                anchor = sample
            } else if anchor == nil {
                anchor = sample
            }
            last = sample
        }
        if let start = anchor, let end = last, end != start { total += SpeedEstimator.distance(from: start, to: end) }
        return total
    }

    // MARK: Text

    var text: String {
        func kmh(_ metersPerSecond: Double) -> String { String(format: "%.2f km/h", metersPerSecond * 3.6) }
        func seconds(_ value: Double) -> String { String(format: "%.2f s", value) }
        var lines = ["## \(drive.name)"]
        if let header = drive.header { lines.append("- device \(header.device), \(header.system)") }
        lines.append("- fixes: \(drive.fixes.count), motion samples: \(drive.motion.count)")
        if let interval = fixInterval { lines.append("- fix interval: median \(seconds(interval.median)), p95 \(seconds(interval.p95))") }
        if let latency = arrivalLatency {
            lines.append("- arrival latency: median \(seconds(latency.median)), p95 \(seconds(latency.p95))")
        }
        let missing = missingSpeed
        lines.append("- speed −1: \(missing.count) of \(missing.total) fixes; usable for position speed (R13): \(missing.usable)")
        if let accuracy = speedAccuracy {
            lines.append(String(format: "- speedAccuracy: median %.2f m/s, p95 %.2f m/s", accuracy.median, accuracy.p95))
        }
        if let sigma = liveSigma {
            lines.append(String(format: "- GPS-only σ while Live: median %.2f m/s, p95 %.2f m/s, weak share %.0f%%",
                                sigma.median, sigma.p95, sigma.weakShare * 100))
        }
        if let scale = speedAccuracyScale {
            lines.append(String(format: "- k_R: mean NIS %.2f at k_R = 1, suggested k_R %.2f", scale.meanNIS, scale.suggestedScale))
        }
        if let delay = reportingDelay {
            lines.append(String(format: "- τ (magnitude, preliminary): %.1f s, correlation %.2f", delay.tau, delay.correlation))
        }
        let gaps = self.gaps
        lines.append("- gaps while moving: \(gaps.count)")
        for gap in gaps {
            lines.append("  - \(seconds(gap.duration)), unavailable reported: \(gap.reportedUnavailable), "
                         + "accuracy after: \(String(format: "%.0f", gap.accuracyAfter)) m")
        }
        let stretches = steadyStretches
        let positions = positionDistance
        if positions > 0 {
            let trip = tripDistance
            lines.append(String(format: "- trip distance (trip-stats R18): %.2f km, from positions %.2f km (Δ %+.1f%%)",
                                trip / 1_000, positions / 1_000, (trip - positions) / positions * 100))
        }
        lines.append("- steady stretches ≥ 3 km (R29): \(stretches.count)")
        for stretch in stretches {
            var line = "  - \(String(format: "%.1f", stretch.distance / 1000)) km: distance/time \(kmh(stretch.distanceSpeed)), "
                + "Doppler \(kmh(stretch.meanDoppler)) (Δ \(kmh(stretch.meanDoppler - stretch.distanceSpeed)))"
            if let estimate = stretch.meanShownEstimate {
                line += ", shown \(kmh(estimate)) (Δ \(kmh(estimate - stretch.distanceSpeed)))"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Statistics

    static func percentiles(_ values: [Double]) -> (median: Double, p95: Double)? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        func at(_ fraction: Double) -> Double { sorted[min(sorted.count - 1, Int(fraction * Double(sorted.count - 1) + 0.5))] }
        return (at(0.5), at(0.95))
    }

    static func correlation(_ pairs: [(Double, Double)]) -> Double? {
        guard pairs.count >= 3 else { return nil }
        let count = Double(pairs.count)
        let meanX = pairs.map(\.0).reduce(0, +) / count
        let meanY = pairs.map(\.1).reduce(0, +) / count
        var covariance = 0.0
        var varianceX = 0.0
        var varianceY = 0.0
        for (x, y) in pairs {
            covariance += (x - meanX) * (y - meanY)
            varianceX += (x - meanX) * (x - meanX)
            varianceY += (y - meanY) * (y - meanY)
        }
        guard varianceX > 0, varianceY > 0 else { return nil }
        return covariance / (varianceX * varianceY).squareRoot()
    }

    /// Trapezoidal time average of (time, value) points.
    static func timeAverage(_ points: [(Date, Double)]) -> Double {
        guard let first = points.first, let last = points.last, last.0 > first.0 else { return points.first?.1 ?? 0 }
        let area = zip(points, points.dropFirst()).reduce(0.0) { sum, pair in
            sum + (pair.0.1 + pair.1.1) / 2 * pair.1.0.timeIntervalSince(pair.0.0)
        }
        return area / last.0.timeIntervalSince(first.0)
    }
}
