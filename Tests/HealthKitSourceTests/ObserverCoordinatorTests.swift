// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(HealthKit)
@preconcurrency import HealthKit
import CoreDomain
import Foundation
import HealthKitSource
import MetricCatalog
import RunJournal
import Testing

private final class FakeObserverStore: ObserverHealthStore, @unchecked Sendable {
    private let lock = NSLock()
    private let failing: Set<String>
    private(set) var executed: [HKSampleType] = []
    private(set) var stopped = 0
    private(set) var backgroundDelivery: [String] = []

    init(failing: Set<String> = []) {
        self.failing = failing
    }

    func execute(_ query: HKQuery) {
        lock.withLock {
            if let type = query.objectType as? HKSampleType { executed.append(type) }
        }
    }

    func stop(_ query: HKQuery) {
        lock.withLock { stopped += 1 }
    }

    func enableBackgroundDelivery(
        for type: HKObjectType,
        frequency: HKUpdateFrequency,
        withCompletion completion: @escaping @Sendable (Bool, (any Error)?) -> Void
    ) {
        let fails = lock.withLock {
            backgroundDelivery.append(type.identifier)
            return failing.contains(type.identifier)
        }
        completion(!fails, fails ? CocoaError(.featureUnsupported) : nil)
    }
}

private func coordinator(_ store: FakeObserverStore) -> HealthKitObserverCoordinator {
    HealthKitObserverCoordinator(
        store: store,
        wakeLedger: WakeLedger(
            path: FileManager.default.temporaryDirectory
                .appendingPathComponent("ohe-wake-\(UUID().uuidString).ndjson").path
        ),
        isAvailable: { true }
    )
}

/// #28: every metric a person can select, other than characteristics, resolves to a
/// sample type an observer can watch.
@Test func everySelectableSampleMetricHasAnObservableType() {
    let unresolved = MetricCatalog.selectable
        .map(\.id)
        .filter { !MetricCatalog.isCharacteristic($0) }
        .filter { HealthKitObserverCoordinator.sampleType(for: $0) == nil }
    #expect(unresolved.isEmpty, "\(unresolved)")
}

/// #28: sleep, workouts and category types used to throw and take every observer down
/// with them. Each type now gets its own observer and background delivery.
@Test func quantityCategoryAndWorkoutTypesEachRegister() async throws {
    let store = FakeObserverStore()
    let metrics = [
        MetricCatalog.stepCount.id,
        MetricCatalog.sleepAnalysis.id,
        MetricCatalog.workout.id,
        MetricCatalog.mindfulSession.id,
    ]
    let registration = try await coordinator(store).start(metrics: metrics) { _ in }
    #expect(registration.registered == metrics)
    #expect(registration.failures.isEmpty)
    #expect(store.executed.count == metrics.count)
    #expect(store.backgroundDelivery.count == metrics.count)
}

@Test func oneFailedRegistrationLeavesTheOthersObserved() async throws {
    let store = FakeObserverStore(failing: [HKCategoryTypeIdentifier.sleepAnalysis.rawValue])
    let metrics = [
        MetricCatalog.stepCount.id,
        MetricCatalog.sleepAnalysis.id,
        MetricCatalog.workout.id,
    ]
    let registration = try await coordinator(store).start(metrics: metrics) { _ in }
    #expect(registration.registered == [MetricCatalog.stepCount.id, MetricCatalog.workout.id])
    #expect(registration.failures.keys.sorted { $0.rawValue < $1.rawValue } == [MetricCatalog.sleepAnalysis.id])
    #expect(store.stopped == 1)
}
#endif
