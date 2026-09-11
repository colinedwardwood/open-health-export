// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CoreTemporal
import Foundation
import MetricCatalog

public struct AggregateDayPlan: Sendable, Equatable {
    public var metric: MetricID
    public var day: String
    public var record: AggregateRecord

    public init(metric: MetricID, day: String, record: AggregateRecord) {
        self.metric = metric
        self.day = day
        self.record = record
    }
}

/// Fixture-friendly stage-5 head: one dirty day → one aggregate record.
public enum AggregateDrain {
    public static func planDay(
        metric: MetricID,
        day: String,
        samples: [SampleRecord],
        context: TemporalContext,
        emitSeq: Int,
        computedAt: String,
        observedAt: String,
        now: Date,
        priorEmitSeq: Int? = nil,
        reconcileWindowDays: Int = 7
    ) -> AggregateDayPlan? {
        guard let bounds = BucketKey.boundsP1D(day: day, context: context) else { return nil }
        let fold = AggregateFold.foldDay(metric: metric, day: day, samples: samples)
        let decl = MetricCatalog.declaration(for: metric)
        let wireId = decl?.wireId ?? metric.rawValue
        let unit = decl?.canonicalUnit ?? CanonicalUnit(symbol: "1")
        let bucketKey = BucketKey.render(
            metricWireId: wireId,
            statistic: fold.statistic.rawValue,
            granularity: "P1D",
            bucketStart: bounds.bucketStart,
            timeZoneIdentifier: context.timeZoneIdentifier,
            sourceScope: AggregateSourceScope.all.rawValue
        )
        let state = bucketState(
            priorEmitSeq: priorEmitSeq,
            bucketEnd: bounds.bucketEnd,
            day: day,
            now: now,
            reconcileWindowDays: reconcileWindowDays,
            context: context
        )
        let record = AggregateRecord(
            bucketKey: bucketKey,
            metric: metric,
            statistic: fold.statistic,
            computation: .localSampleFold,
            sourceScope: .all,
            granularity: "P1D",
            bucketStart: bounds.bucketStart,
            bucketEnd: bounds.bucketEnd,
            bucketDurationSeconds: bounds.bucketDurationSeconds,
            timeZoneIdentifier: context.timeZoneIdentifier,
            localStart: bounds.localStart,
            value: fold.value,
            unit: unit,
            sampleCount: fold.sampleCount,
            state: state,
            emitSeq: emitSeq,
            computedAt: computedAt,
            observedAt: observedAt,
            supersedes: priorEmitSeq
        )
        return AggregateDayPlan(metric: metric, day: day, record: record)
    }

    public static func planStatisticsDay(
        metric: MetricID,
        day: String,
        canonical: AggregateRecord,
        context: TemporalContext,
        emitSeq: Int,
        computedAt: String,
        observedAt: String,
        now: Date,
        priorEmitSeq: Int? = nil,
        reconcileWindowDays: Int = 7
    ) -> AggregateDayPlan? {
        guard canonical.metric == metric,
              canonical.computation == .healthKitStatisticsCollectionQuery,
              let bounds = BucketKey.boundsP1D(day: day, context: context)
        else { return nil }
        var record = canonical
        record.bucketStart = bounds.bucketStart
        record.bucketEnd = bounds.bucketEnd
        record.bucketDurationSeconds = bounds.bucketDurationSeconds
        record.timeZoneIdentifier = context.timeZoneIdentifier
        record.localStart = bounds.localStart
        record.state = bucketState(
            priorEmitSeq: priorEmitSeq,
            bucketEnd: bounds.bucketEnd,
            day: day,
            now: now,
            reconcileWindowDays: reconcileWindowDays,
            context: context
        )
        record.emitSeq = emitSeq
        record.computedAt = computedAt
        record.observedAt = observedAt
        record.supersedes = priorEmitSeq
        return AggregateDayPlan(metric: metric, day: day, record: record)
    }

    static func bucketState(
        priorEmitSeq: Int?,
        bucketEnd: String,
        day: String,
        now: Date,
        reconcileWindowDays: Int,
        context: TemporalContext
    ) -> AggregateBucketState {
        if priorEmitSeq != nil {
            return .revised
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        guard let end = formatter.date(from: bucketEnd), now >= end else {
            return .open
        }
        let today = DayBucket.containing(now, context: context).isoDay
        let window = ReconcilePlanner.trailingDays(throughDay: today, count: reconcileWindowDays)
        if window.contains(day) {
            return .open
        }
        return .final
    }
}
