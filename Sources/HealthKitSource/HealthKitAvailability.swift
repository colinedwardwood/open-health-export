// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(HealthKit)
@preconcurrency import HealthKit
import Foundation
import MetricCatalog

/// Single gate for HK-01. Production uses Apple's store probe. DEBUG builds
/// also honour `OHE_HEALTHKIT_UNAVAILABLE=1` so the terminal screen is testable
/// on simulators where HealthKit itself is present.
public enum HealthKitAvailability {
    public static func isAvailable(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        #if DEBUG
        if environment[HealthAvailability.unavailableEnvironmentKey] == "1" {
            return false
        }
        #endif
        return HKHealthStore.isHealthDataAvailable()
    }
}
#endif
