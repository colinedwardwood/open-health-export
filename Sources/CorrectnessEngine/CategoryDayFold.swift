// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import CoreDomain
import MetricCatalog

/// Daily totals for category types, which carry a duration rather than a quantity.
public enum CategoryDayFold {
    /// One duration sample per category record, valued in the metric's canonical unit
    /// (minutes), so the ordinary day fold sums it. Empty for a type with no daily
    /// total (Sleep, symptom events).
    static func durationSamples(
        _ categories: [CategoryRecord],
        metric: MetricID
    ) -> [SampleRecord] {
        guard let declaration = MetricCatalog.declaration(for: metric),
              declaration.isCategory,
              declaration.hasDailyTotal
        else { return [] }
        return categories.filter { $0.metric == metric }.map {
            SampleRecord(
                key: $0.key,
                metric: metric,
                start: $0.start,
                end: $0.end,
                timeZoneOffsetMinutes: $0.timeZoneOffsetMinutes,
                timeZoneSource: $0.timeZoneSource,
                value: minutes($0),
                unit: declaration.canonicalUnit,
                observedAt: $0.observedAt
            )
        }
    }

    /// Minutes per stage name for one day of Sleep (`asleepCore`, `asleepREM`, ...).
    public static func minutesByStage(_ categories: [CategoryRecord]) -> [String: Double] {
        categories.reduce(into: [:]) { totals, record in
            totals[record.categoryName, default: 0] += minutes(record)
        }
    }

    private static func minutes(_ record: CategoryRecord) -> Double {
        (record.durationSeconds ?? 0) / 60
    }
}
