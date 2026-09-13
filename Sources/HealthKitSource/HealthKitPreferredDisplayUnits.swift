// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(HealthKit)
@preconcurrency import HealthKit
import Foundation
import MetricCatalog

extension Notification.Name {
    public static let healthKitPreferredDisplayUnitsDidChange =
        Notification.Name("ohe.healthKitPreferredDisplayUnitsDidChange")
}

/// UX-44: display units come from Health's preferred units and refresh when
/// those preferences change. Export units stay on the wire catalogue.
@MainActor
public enum HealthKitPreferredDisplayUnits {
    public static let didChange = Notification.Name.healthKitPreferredDisplayUnitsDidChange

    private static var observing = false

    public static func startObserving() {
        guard !observing else { return }
        observing = true
        NotificationCenter.default.addObserver(
            forName: .HKUserPreferencesDidChange,
            object: nil,
            queue: .main
        ) { _ in
            NotificationCenter.default.post(
                name: .healthKitPreferredDisplayUnitsDidChange,
                object: nil
            )
        }
    }

    public static func policy(
        store: HKHealthStore = HKHealthStore(),
        fallback: UnitDisplayPolicy
    ) async -> UnitDisplayPolicy {
        guard HealthKitAvailability.isAvailable() else { return fallback }
        var types = Set<HKQuantityType>()
        func insert(_ identifier: HKQuantityTypeIdentifier) -> HKQuantityType? {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
                return nil
            }
            types.insert(type)
            return type
        }
        let mass = insert(.bodyMass)
        let distance = insert(.distanceWalkingRunning)
        let length = insert(.height)
        let temperature = insert(.bodyTemperature)
        let glucose = insert(.bloodGlucose)
        let volume = insert(.dietaryWater)
        let preferred: [HKQuantityType: HKUnit]
        do {
            preferred = try await store.preferredUnits(for: types)
        } catch {
            return fallback
        }
        return HealthDisplayUnitMapping.overlay(
            mass: mass.flatMap { preferred[$0]?.unitString },
            distance: distance.flatMap { preferred[$0]?.unitString },
            length: length.flatMap { preferred[$0]?.unitString },
            temperature: temperature.flatMap { preferred[$0]?.unitString },
            glucose: glucose.flatMap { preferred[$0]?.unitString },
            volume: volume.flatMap { preferred[$0]?.unitString },
            onto: fallback
        )
    }
}
#endif
