// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

#if canImport(HealthKit)
@preconcurrency import HealthKit
import CoreDomain
import CoreTemporal
import Foundation
import MetricCatalog
import Testing
@testable import HealthKitSource

/// #168: the category day reader refuses a type it has no category mapping for, and
/// reports Health as unavailable where it is, before it touches the store.
@Test func categoryDayReaderRejectsAQuantityMetric() async {
    let source = HealthKitDayObservationSource(context: TemporalContext(
        timeZoneIdentifier: "UTC",
        localeIdentifier: "en_US_POSIX",
        tzDatabaseVersion: "2024a"
    ))
    await #expect(throws: HealthKitSourceError.self) {
        _ = try await source.categories(metric: MetricCatalog.stepCount.id, day: "2026-11-25")
    }
}
#endif
