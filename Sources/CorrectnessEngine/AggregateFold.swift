// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import MetricCatalog

public struct AggregateFoldResult: Sendable, Equatable {
    public var value: Double?
    public var sampleCount: Int
    public var statistic: AggregateStatistic

    public init(value: Double?, sampleCount: Int, statistic: AggregateStatistic) {
        self.value = value
        self.sampleCount = sampleCount
        self.statistic = statistic
    }
}

/// P1D localSampleFold over in-memory samples (no HealthKit statistics).
public enum AggregateFold {
    public static func foldDay(
        metric: MetricID,
        day: String,
        samples: [SampleRecord]
    ) -> AggregateFoldResult {
        let decl = MetricCatalog.declaration(for: metric)
        let statistic: AggregateStatistic = (decl?.cumulative == true) ? .sum : .mean
        let values = samples
            .filter { $0.metric == metric && $0.start.hasPrefix(day) }
            .sorted {
                if $0.key.uuid != $1.key.uuid { return $0.key.uuid < $1.key.uuid }
                return $0.start < $1.start
            }
            .map(\.value)
        guard !values.isEmpty else {
            return AggregateFoldResult(value: nil, sampleCount: 0, statistic: statistic)
        }
        switch statistic {
        case .sum:
            return AggregateFoldResult(value: values.reduce(0, +), sampleCount: values.count, statistic: .sum)
        case .mean:
            let sum = values.reduce(0, +)
            return AggregateFoldResult(value: sum / Double(values.count), sampleCount: values.count, statistic: .mean)
        case .min:
            return AggregateFoldResult(value: values.min(), sampleCount: values.count, statistic: .min)
        case .max:
            return AggregateFoldResult(value: values.max(), sampleCount: values.count, statistic: .max)
        case .count:
            return AggregateFoldResult(value: Double(values.count), sampleCount: values.count, statistic: .count)
        }
    }
}
