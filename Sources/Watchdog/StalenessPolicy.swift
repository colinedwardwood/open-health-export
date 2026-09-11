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

public enum FreshnessClass: String, Sendable, Codable, CaseIterable {
    case a
    case b
    case c
    case d
}

public struct FreshnessObservation: Sendable, Equatable {
    public var observedAt: Date
    public var latency: TimeInterval

    public init(observedAt: Date, latency: TimeInterval) {
        self.observedAt = observedAt
        self.latency = latency
    }
}

public enum FreshnessTarget {
    public static let minimumSamples = 100
    public static let minimumSpan: TimeInterval = 14 * 24 * 60 * 60
    public static let alarmFloor: TimeInterval = 6 * 60 * 60
    public static let alarmCap: TimeInterval = 48 * 60 * 60
    public static let provisionalDisclosure =
        "Freshness target pending R-71 evidence. The overdue alarm floor is 6 hours; this is not a delivery promise."

    public static func classDisclosure(
        _ freshnessClass: FreshnessClass,
        localP95: TimeInterval? = nil
    ) -> String {
        let name = "Class \(freshnessClass.rawValue.uppercased())"
        if let localP95 {
            let hours = localP95 / 3600
            let alarm = alarmThreshold(p95: localP95) / 3600
            return
                "\(name): this device's p95 is \(hours) hours. "
                    + "The overdue alarm uses \(alarm) hours (floor 6, cap 48)."
        }
        return
            "\(name): freshness target N pending R-71. "
                + "The overdue alarm floor is 6 hours; this is not a delivery promise."
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

    public static func alarmThreshold(p95: TimeInterval) -> TimeInterval {
        min(alarmCap, max(alarmFloor, 2 * p95))
    }
}
