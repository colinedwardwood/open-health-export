import CoreDomain
import CoreTemporal
import EnginePorts
import Foundation
import MetricCatalog

enum AggregateResolver {
    static func plans(
        metric: MetricID,
        days: Set<String>,
        samples: [SampleRecord],
        statistics: (any StatisticsSource)?,
        store: any StateStore,
        context: TemporalContext,
        computedAt: String,
        observedAt: String,
        now: Date
    ) async throws -> [AggregateDayPlan] {
        var plans: [AggregateDayPlan] = []
        let usesStatistics = MetricCatalog.declaration(for: metric)?.usesHealthKitStatistics == true
        for day in days.sorted() {
            if usesStatistics {
                guard let statistics,
                      let canonical = try await statistics.dailyBucket(metric: metric, day: day)
                else { continue }
                let plan = try await store.transact { tx -> AggregateDayPlan? in
                    let prior = try tx.loadAggregateEmitSeq(bucketKey: canonical.bucketKey)
                    return AggregateDrain.planStatisticsDay(
                        metric: metric,
                        day: day,
                        canonical: canonical,
                        context: context,
                        emitSeq: (prior ?? 0) + 1,
                        computedAt: computedAt,
                        observedAt: observedAt,
                        now: now,
                        priorEmitSeq: prior
                    )
                }
                if let plan { plans.append(plan) }
                continue
            }

            let plan = try await store.transact { tx -> AggregateDayPlan? in
                guard let probe = AggregateDrain.planDay(
                    metric: metric,
                    day: day,
                    samples: samples,
                    context: context,
                    emitSeq: 1,
                    computedAt: computedAt,
                    observedAt: observedAt,
                    now: now
                ) else { return nil }
                let prior = try tx.loadAggregateEmitSeq(bucketKey: probe.record.bucketKey)
                return AggregateDrain.planDay(
                    metric: metric,
                    day: day,
                    samples: samples,
                    context: context,
                    emitSeq: (prior ?? 0) + 1,
                    computedAt: computedAt,
                    observedAt: observedAt,
                    now: now,
                    priorEmitSeq: prior
                )
            }
            if let plan { plans.append(plan) }
        }
        return plans
    }
}
