// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CoreTemporal
import EnginePorts
import Foundation

public struct StalenessPolicy: Sendable {
    /// Nil until R-71 publishes a class baseline or this device has qualifying local evidence.
    public var defaultInterval: TimeInterval?

    public init(defaultInterval: TimeInterval? = nil) {
        self.defaultInterval = defaultInterval
    }

    public func shouldEscalate(lastSuccess: Date?, now: Date) -> Bool {
        guard let defaultInterval else { return false }
        guard let lastSuccess else { return true }
        return now.timeIntervalSince(lastSuccess) >= defaultInterval
    }
}

public struct FreshnessObservation: Sendable, Equatable {
    public var observedAt: Date
    public var latency: TimeInterval

    public init(observedAt: Date, latency: TimeInterval) {
        self.observedAt = observedAt
        self.latency = latency
    }
}

public struct LocalFreshnessEstimate: Sendable, Equatable, Codable {
    public var sampleCount: Int
    public var spanSeconds: TimeInterval
    public var observationP95Seconds: TimeInterval?
    public var deliveryP95Seconds: TimeInterval?
    public var totalP95Seconds: TimeInterval?

    public init(
        sampleCount: Int,
        spanSeconds: TimeInterval,
        observationP95Seconds: TimeInterval? = nil,
        deliveryP95Seconds: TimeInterval? = nil,
        totalP95Seconds: TimeInterval? = nil
    ) {
        self.sampleCount = max(0, sampleCount)
        self.spanSeconds = max(0, spanSeconds)
        self.observationP95Seconds = observationP95Seconds
        self.deliveryP95Seconds = deliveryP95Seconds
        self.totalP95Seconds = totalP95Seconds
    }

    public var isQualified: Bool {
        sampleCount >= FreshnessTarget.minimumSamples
            && spanSeconds >= FreshnessTarget.minimumSpan
            && observationP95Seconds != nil
            && deliveryP95Seconds != nil
            && totalP95Seconds != nil
    }
}

public enum FreshnessTarget {
    public static let minimumSamples = 100
    public static let minimumSpan: TimeInterval = 14 * 24 * 60 * 60
    public static let alarmFloor: TimeInterval = 6 * 60 * 60
    public static let alarmCap: TimeInterval = 48 * 60 * 60
    /// UX-22 / UX-33: C defaults to 15 minutes; stale is max(2·C, 90 min).
    public static let defaultCadenceSeconds: TimeInterval = 15 * 60
    public static let staleFloor: TimeInterval = 90 * 60
    public static let provisionalDisclosure =
        "Freshness target pending R-71 evidence. The overdue alarm floor is 6 hours; this is not a delivery promise."

    public static func classDisclosure(
        _ freshnessClass: FreshnessClass,
        estimate: LocalFreshnessEstimate? = nil
    ) -> String {
        let name = "Class \(freshnessClass.rawValue.uppercased())"
        if let estimate,
           estimate.isQualified,
           let observationP95 = estimate.observationP95Seconds,
           let deliveryP95 = estimate.deliveryP95Seconds,
           let totalP95 = estimate.totalP95Seconds {
            let alarm = alarmThreshold(p95: totalP95)
            return
                "\(name): on this device, p95 observation latency is \(duration(observationP95)), "
                    + "p95 delivery latency is \(duration(deliveryP95)), and p95 total latency is "
                    + "\(duration(totalP95)) (\(estimate.sampleCount) successful runs). "
                    + "The overdue alarm uses \(duration(alarm))."
        }
        if let estimate, estimate.sampleCount > 0 {
            let days = estimate.spanSeconds / (24 * 60 * 60)
            return
                "\(name): local estimate not yet available "
                    + "(\(estimate.sampleCount)/\(minimumSamples) successful runs over "
                    + "\(String(format: "%.1f", days))/14 days). "
                    + "Freshness target N remains pending R-71."
        }
        return
            "\(name): freshness target N pending R-71. "
                + "The overdue alarm floor is 6 hours; this is not a delivery promise."
    }

    /// Compatibility for callers that already hold a qualified combined p95.
    public static func classDisclosure(
        _ freshnessClass: FreshnessClass,
        localP95: TimeInterval?
    ) -> String {
        guard let localP95 else { return classDisclosure(freshnessClass) }
        let name = "Class \(freshnessClass.rawValue.uppercased())"
        let hours = localP95 / 3600
        let alarm = alarmThreshold(p95: localP95) / 3600
        return
            "\(name): this device's p95 is \(hours) hours. "
                + "The overdue alarm uses \(alarm) hours (floor 6, cap 48)."
    }

    public static var pendingClassDisclosures: [String] {
        FreshnessClass.allCases.map { classDisclosure($0) }
    }

    /// Device-local p95 becomes eligible only with ≥100 observations spanning ≥14 days.
    public static func localP95(observations: [FreshnessObservation]) -> TimeInterval? {
        guard observations.count >= minimumSamples,
              let first = observations.map(\.observedAt).min(),
              let last = observations.map(\.observedAt).max(),
              last.timeIntervalSince(first) >= minimumSpan
        else {
            return nil
        }
        let ordered = observations.map(\.latency).filter { $0 >= 0 }.sorted()
        guard ordered.count >= minimumSamples else { return nil }
        let nearestRank = max(0, Int(ceil(0.95 * Double(ordered.count))) - 1)
        return ordered[nearestRank]
    }

    public static func localEstimate(
        observations: [RunFreshnessLatency]
    ) -> LocalFreshnessEstimate {
        let dates = observations.map(\.recordedAtEpoch)
        let span = (dates.max() ?? 0) - (dates.min() ?? 0)
        guard observations.count >= minimumSamples, span >= minimumSpan else {
            return LocalFreshnessEstimate(sampleCount: observations.count, spanSeconds: span)
        }
        return LocalFreshnessEstimate(
            sampleCount: observations.count,
            spanSeconds: span,
            observationP95Seconds: p95(observations.map(\.observationLatencySeconds)),
            deliveryP95Seconds: p95(observations.map(\.deliveryLatencySeconds)),
            totalP95Seconds: p95(observations.map(\.totalLatencySeconds))
        )
    }

    public static func alarmThreshold(p95: TimeInterval) -> TimeInterval {
        min(alarmCap, max(alarmFloor, 2 * p95))
    }

    /// R-23 overdue window: qualified local p95 when we have it, otherwise the 6-hour floor.
    /// Several classes may be exporting to one destination; the slowest alarm wins.
    public static func overdueThreshold(
        estimates: [FreshnessClass: LocalFreshnessEstimate]
    ) -> TimeInterval {
        let alarms = estimates.values.compactMap { estimate -> TimeInterval? in
            guard estimate.isQualified, let p95 = estimate.totalP95Seconds else { return nil }
            return alarmThreshold(p95: p95)
        }
        return alarms.max() ?? alarmFloor
    }

    /// Stale is the earlier watchdog step, always strictly inside the overdue window.
    public static func staleThreshold(overdue: TimeInterval) -> TimeInterval {
        max(1, overdue / 2)
    }

    /// UX-22: notify at lastSuccess + max(4·C, 6 h). UX-33: Stale at max(2·C, 90 min).
    public static func cadenceThresholds(
        cadenceSeconds: TimeInterval
    ) -> (stale: TimeInterval, overdue: TimeInterval) {
        let cadence = max(60, cadenceSeconds)
        let overdue = max(4 * cadence, alarmFloor)
        let stale = min(max(2 * cadence, staleFloor), overdue - 1)
        return (stale, overdue)
    }

    public static func snapshotThresholds(
        estimates: [FreshnessClass: LocalFreshnessEstimate],
        cadenceSeconds: TimeInterval = defaultCadenceSeconds
    ) -> (stale: TimeInterval, overdue: TimeInterval) {
        let cadence = cadenceThresholds(cadenceSeconds: cadenceSeconds)
        let overdue = max(cadence.overdue, overdueThreshold(estimates: estimates))
        let stale = min(cadence.stale, staleThreshold(overdue: overdue), overdue - 1)
        return (stale, overdue)
    }

    private static func p95(_ values: [TimeInterval]) -> TimeInterval? {
        let ordered = values.filter { $0.isFinite && $0 >= 0 }.sorted()
        guard ordered.count >= minimumSamples else { return nil }
        return ordered[max(0, Int(ceil(0.95 * Double(ordered.count))) - 1)]
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        if seconds >= 3600 {
            return String(format: "%.1f h", seconds / 3600)
        }
        if seconds >= 60 {
            return String(format: "%.1f min", seconds / 60)
        }
        return "\(Int(seconds.rounded())) s"
    }
}

public extension FreshnessClass {
    /// Conservative pre-R-71 assignments: only classes explicitly named by the design
    /// are instrumented. Unlisted metrics return nil instead of guessing a boundary.
    static func knownClass(for metric: MetricID) -> FreshnessClass? {
        switch metric.rawValue {
        case "stepCount", "walkingRunningDistance", "flightsClimbed":
            .a
        case "heartRate", "heartRateVariabilitySDNN", "activeEnergy", "workout":
            .b
        case "sleep_analysis":
            .c
        case "bloodGlucose", "bodyMass":
            .d
        default:
            nil
        }
    }
}
