// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation

/// UX-06: a previously populated type that later returns nothing is a coverage
/// drop. HealthKit has no revocation callback, so this is the detection.
public struct CoverageDropEvent: Sendable, Equatable {
    public var metric: MetricID
    public var lastDataDay: String

    public init(metric: MetricID, lastDataDay: String) {
        self.metric = metric
        self.lastDataDay = lastDataDay
    }
}

public enum CoverageDrop {
    public static let storageKey = "ohe.coverageLastDataDays"
    public static let reviewAction = "Review coverage"
    public static let attentionDetail =
        "Either the data stopped, or access was turned off in Health."

    public static func isoDay(from timestamp: String) -> String? {
        guard timestamp.count >= 10 else { return nil }
        let day = String(timestamp.prefix(10))
        let parts = day.split(separator: "-")
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) })
        else {
            return nil
        }
        return day
    }

    public static func displayDay(_ isoDay: String, fullMonth: Bool) -> String {
        let parts = isoDay.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              month >= 1,
              month <= 12,
              let day = Int(parts[2])
        else {
            return isoDay
        }
        let names = fullMonth ? monthNames : monthAbbreviations
        return "\(day) \(names[month - 1])"
    }

    public static func typeTitle(for metric: MetricID) -> String {
        let raw = MetricCatalog.declaration(for: metric)?.wireId
            ?? metric.rawValue
        return raw.replacingOccurrences(of: "_", with: " ")
    }

    public static func inlineNote(lastDataDay: String) -> String {
        "Returned data until \(displayDay(lastDataDay, fullMonth: false)), then stopped."
    }

    public static func attentionHeadline(for event: CoverageDropEvent) -> String {
        let title = typeTitle(for: event.metric)
        let name = title.isEmpty
            ? "This type"
            : title.prefix(1).uppercased() + title.dropFirst()
        return "\(name) stopped returning data on \(displayDay(event.lastDataDay, fullMonth: true))."
    }

    public static func nextLastDataDays(
        previous: [MetricID: String],
        current: [MetricID: CoverageState]
    ) -> [MetricID: String] {
        var next = previous
        for (metric, state) in current {
            switch state {
            case .dataAvailable(_, let latest):
                if let day = isoDay(from: latest) {
                    next[metric] = day
                }
            case .limitedWindow(_, let count, let latest):
                if count > 0, let latest, let day = isoDay(from: latest) {
                    next[metric] = day
                }
            case .nothingReturned:
                break
            }
        }
        return next
    }

    public static func events(
        lastDataDays: [MetricID: String],
        current: [MetricID: CoverageState],
        selected: Set<MetricID>
    ) -> [CoverageDropEvent] {
        selected.compactMap { metric -> CoverageDropEvent? in
            guard case .nothingReturned = current[metric],
                  let day = lastDataDays[metric]
            else {
                return nil
            }
            return CoverageDropEvent(metric: metric, lastDataDay: day)
        }
        .sorted { $0.metric.rawValue < $1.metric.rawValue }
    }

    public static func encodeLastDataDays(_ days: [MetricID: String]) -> Data? {
        let raw = Dictionary(uniqueKeysWithValues: days.map { ($0.key.rawValue, $0.value) })
        return try? JSONEncoder().encode(raw)
    }

    public static func decodeLastDataDays(_ data: Data?) -> [MetricID: String] {
        guard let data,
              let raw = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: raw.map { (MetricID(rawValue: $0.key), $0.value) })
    }

    private static let monthAbbreviations = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]
    private static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]
}
