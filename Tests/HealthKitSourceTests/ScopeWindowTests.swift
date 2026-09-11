// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(HealthKit)
@preconcurrency import HealthKit
import CoreDomain
import CoreTemporal
import Foundation
import MetricCatalog
import Testing
@testable import HealthKitSource

private let windowStart = Date(timeIntervalSince1970: 1_704_067_200)
private let windowEnd = windowStart.addingTimeInterval(24 * 60 * 60)

/// Synthetic sample: the predicate only reads `startDate`, so no store is involved.
private func heartRate(startingAt start: Date) -> HKQuantitySample {
    HKQuantitySample(
        type: HKQuantityType(.heartRate),
        quantity: HKQuantity(
            unit: HKUnit.count().unitDivided(by: .minute()),
            doubleValue: 72
        ),
        start: start,
        end: start.addingTimeInterval(60)
    )
}

@Test func scopeWindowAdmitsItsStartInstantAndRejectsTheOneBefore() throws {
    let window = HealthKitQueryWindow(
        startInclusive: windowStart,
        endExclusive: windowEnd
    )
    let predicate = try #require(window.samplePredicate)
    #expect(!predicate.evaluate(with: heartRate(startingAt: windowStart.addingTimeInterval(-1))))
    #expect(predicate.evaluate(with: heartRate(startingAt: windowStart)))
    #expect(predicate.evaluate(with: heartRate(startingAt: windowStart.addingTimeInterval(1))))
}

@Test func scopeWindowExcludesItsEndInstantSoAdjacentWindowsNeverOverlap() throws {
    let window = HealthKitQueryWindow(
        startInclusive: windowStart,
        endExclusive: windowEnd
    )
    let predicate = try #require(window.samplePredicate)
    #expect(predicate.evaluate(with: heartRate(startingAt: windowEnd.addingTimeInterval(-1))))
    #expect(!predicate.evaluate(with: heartRate(startingAt: windowEnd)))
    #expect(!predicate.evaluate(with: heartRate(startingAt: windowEnd.addingTimeInterval(1))))

    // The sample that straddles the boundary is judged by its start alone.
    let straddling = HKQuantitySample(
        type: HKQuantityType(.heartRate),
        quantity: HKQuantity(
            unit: HKUnit.count().unitDivided(by: .minute()),
            doubleValue: 72
        ),
        start: windowEnd.addingTimeInterval(-30),
        end: windowEnd.addingTimeInterval(30)
    )
    #expect(predicate.evaluate(with: straddling))
}

@Test func unboundedScopeWindowCarriesNoPredicateAtAll() {
    #expect(HealthKitQueryWindow.unbounded.isUnbounded)
    #expect(HealthKitQueryWindow.unbounded.samplePredicate == nil)
    #expect(HealthKitQueryWindow() == .unbounded)
    #expect(HealthKitQueryWindow(startInclusive: nil, endExclusive: nil).samplePredicate == nil)
}

@Test func halfOpenScopeWindowsStillFilterTheBoundTheyDeclare() throws {
    let fromStart = HealthKitQueryWindow(startInclusive: windowStart)
    #expect(!fromStart.isUnbounded)
    let startOnly = try #require(fromStart.samplePredicate)
    #expect(!startOnly.evaluate(with: heartRate(startingAt: windowStart.addingTimeInterval(-1))))
    #expect(startOnly.evaluate(with: heartRate(startingAt: windowStart)))
    #expect(startOnly.evaluate(with: heartRate(startingAt: windowEnd.addingTimeInterval(90 * 86_400))))

    let untilEnd = HealthKitQueryWindow(endExclusive: windowEnd)
    #expect(!untilEnd.isUnbounded)
    let endOnly = try #require(untilEnd.samplePredicate)
    #expect(endOnly.evaluate(with: heartRate(startingAt: windowStart)))
    #expect(!endOnly.evaluate(with: heartRate(startingAt: windowEnd)))
}

@Test func destinationScopeDatesBecomeTheQueryWindowVerbatim() throws {
    let scope = try DestinationExportScope(
        destinationID: "dest-1",
        metrics: [MetricCatalog.heartRate.id],
        startInclusive: windowStart,
        endExclusive: windowEnd
    )
    let window = HealthKitQueryWindow(scope: scope)
    #expect(window.startInclusive == windowStart)
    #expect(window.endExclusive == windowEnd)
    #expect(
        window == HealthKitQueryWindow(
            startInclusive: windowStart,
            endExclusive: windowEnd
        )
    )

    let predicate = try #require(window.samplePredicate)
    #expect(predicate.evaluate(with: heartRate(startingAt: windowStart)))
    #expect(!predicate.evaluate(with: heartRate(startingAt: windowEnd)))

    // Defense in depth: an unconfigured destination must never become an
    // unbounded HealthKit query if an app caller misses the engine gate.
    let empty = try DestinationExportScope(destinationID: "dest-2")
    let denied = HealthKitQueryWindow(scope: empty)
    #expect(!denied.isUnbounded)
    let deniedPredicate = try #require(denied.samplePredicate)
    #expect(!deniedPredicate.evaluate(with: heartRate(startingAt: windowStart)))
}

@Test func anchoredSourcesKeepTheirUnscopedInitialisers() {
    let unscoped = HealthKitAnchoredSource(context: .utc, limit: 10)
    let scoped = HealthKitAnchoredSource(
        context: .utc,
        limit: 10,
        window: HealthKitQueryWindow(startInclusive: windowStart)
    )
    _ = unscoped
    _ = scoped
    _ = HealthKitSampleSource(context: .utc)
    _ = HealthKitCategorySource(context: .utc)
    _ = HealthKitCorrelationSource(context: .utc)
    _ = HealthKitStructuredSource(context: .utc)
}
#endif
