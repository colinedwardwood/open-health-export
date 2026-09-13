// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(HealthKit)
@preconcurrency import HealthKit
import CoreDomain
import CoreTemporal
import EnginePorts
import Foundation
import MetricCatalog

/// UX-06: one-sample (or first/last day) coverage probe per selected type.
/// Sample counts here mean "at least this many", not a full-store census.
public enum HealthKitCoverageProbe {
    public static func observations(
        for metrics: [MetricID],
        store: HKHealthStore = HKHealthStore(),
        context: TemporalContext
    ) async -> [MetricID: CoverageObservation] {
        guard HealthKitAvailability.isAvailable() else { return [:] }
        let authorizedDays = (try? await HealthKitAuthorization.earliestAuthorizedDays(
            for: metrics,
            store: store,
            context: context
        )) ?? [:]
        let quantities = HealthKitDayObservationSource(store: store, context: context, limit: 1)
        let anchored = HealthKitAnchoredSource(store: store, context: context, limit: 1)
        var result: [MetricID: CoverageObservation] = [:]
        for metric in metrics {
            let authorized = authorizedDays[metric]
            if SampleConversion.quantityType(for: metric) != nil,
               let range = try? await quantities.availableDayRange(metric: metric)
            {
                result[metric] = CoverageObservation(
                    sampleCount: 1,
                    latestStart: range.upperBound,
                    earliestAuthorizedDay: authorized
                )
                continue
            }
            if let page = try? await anchored.page(metric: metric, afterAnchor: nil) {
                result[metric] = observation(from: page, earliestAuthorizedDay: authorized)
                continue
            }
            result[metric] = CoverageObservation(earliestAuthorizedDay: authorized)
        }
        return result
    }

    private static func observation(
        from page: SamplePage,
        earliestAuthorizedDay: String?
    ) -> CoverageObservation {
        let starts =
            page.samples.map(\.start)
            + page.categories.map(\.start)
            + page.workouts.map(\.start)
            + page.correlations.map(\.start)
            + page.minds.map(\.start)
            + page.electrocardiograms.map(\.start)
            + page.audiograms.map(\.start)
            + page.medicationDoses.map(\.start)
            + page.series.map(\.parentStart)
        let count = starts.count
        return CoverageObservation(
            sampleCount: count,
            latestStart: starts.max(),
            earliestAuthorizedDay: earliestAuthorizedDay
        )
    }
}
#endif
