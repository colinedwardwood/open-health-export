// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(HealthKit)
@preconcurrency import HealthKit
import CoreDomain
import CoreTemporal
import EnginePorts
import Foundation
import MetricCatalog
import RunJournal

public enum HealthKitObserverError: Error, Equatable {
    case unavailable
    case unknownMetric(MetricID)
    case registrationFailed(MetricID, String)
}

/// The parts of `HKHealthStore` the observer coordinator uses, so a test can stand in
/// for HealthKit and fail one registration on purpose.
public protocol ObserverHealthStore: AnyObject, Sendable {
    func execute(_ query: HKQuery)
    func stop(_ query: HKQuery)
    func enableBackgroundDelivery(
        for type: HKObjectType,
        frequency: HKUpdateFrequency,
        withCompletion completion: @escaping @Sendable (Bool, (any Error)?) -> Void
    )
}

extension HKHealthStore: ObserverHealthStore {}

/// Which selected metrics have a live observer with background delivery, and why the
/// rest do not.
public struct ObserverRegistration: Sendable, Equatable {
    public var registered: [MetricID] = []
    public var failures: [MetricID: String] = [:]

    public init(registered: [MetricID] = [], failures: [MetricID: String] = [:]) {
        self.registered = registered
        self.failures = failures
    }
}

/// One-observer-per-type fallback topology until R-71 G1 establishes that the
/// descriptor-based multi-type observer receives background deliveries.
///
/// Each type registers on its own. One that cannot be resolved or registered is
/// reported and the others keep their observers; resolving only quantity types used to
/// throw on sleep, workouts or any category type and tear down every observer (#28).
public final class HealthKitObserverCoordinator: @unchecked Sendable {
    public typealias WakeHandler = @Sendable (MetricID) async -> Void

    private let store: any ObserverHealthStore
    private let wakeLedger: WakeLedger
    private let clock: any Clock
    private let isAvailable: @Sendable () -> Bool
    private let lock = NSLock()
    private var queries: [HKObserverQuery] = []
    private var started = false

    public init(
        store: any ObserverHealthStore = HKHealthStore(),
        wakeLedger: WakeLedger,
        clock: any Clock = SystemClock(),
        isAvailable: @escaping @Sendable () -> Bool = { HealthKitAvailability.isAvailable() }
    ) {
        self.store = store
        self.wakeLedger = wakeLedger
        self.clock = clock
        self.isAvailable = isAvailable
    }

    /// The observable type for a metric, from the same routing the read path uses.
    /// Nil for characteristics, which are not samples and cannot be observed.
    public static func sampleType(for metric: MetricID) -> HKSampleType? {
        HealthKitAuthorization.objectType(for: metric) as? HKSampleType
    }

    @discardableResult
    public func start(
        metrics: [MetricID],
        onWake: @escaping WakeHandler
    ) async throws -> ObserverRegistration {
        guard isAvailable() else {
            throw HealthKitObserverError.unavailable
        }
        guard beginStart() else { return ObserverRegistration() }

        var registration = ObserverRegistration()
        for metric in metrics where !MetricCatalog.isCharacteristic(metric) {
            guard let type = Self.sampleType(for: metric) else {
                registration.failures[metric] = "no HealthKit sample type"
                continue
            }
            let query = makeQuery(type: type, metric: metric, onWake: onWake)
            retain(query)
            store.execute(query)
            do {
                try await enableBackgroundDelivery(
                    for: type,
                    frequency: Self.frequency(for: metric),
                    metric: metric
                )
                registration.registered.append(metric)
            } catch HealthKitObserverError.registrationFailed(_, let reason) {
                release(query)
                registration.failures[metric] = reason
            }
        }
        return registration
    }

    public func stop() {
        stopQueries()
        resetStarted()
    }

    private func makeQuery(
        type: HKSampleType,
        metric: MetricID,
        onWake: @escaping WakeHandler
    ) -> HKObserverQuery {
        HKObserverQuery(sampleType: type, predicate: nil) {
            [wakeLedger, clock] _, completion, error in
            let receipt = ObserverCompletionReceipt(completion: completion)
            do {
                try wakeLedger.append(
                    WakeRecord(
                        trigger: .observerQuery,
                        atEpoch: clock.now().timeIntervalSince1970
                    )
                )
            } catch {
                receipt.finish()
                return
            }
            guard error == nil else {
                receipt.finish()
                return
            }
            Task {
                defer { receipt.finish() }
                await onWake(metric)
            }
        }
    }

    private func enableBackgroundDelivery(
        for type: HKObjectType,
        frequency: HKUpdateFrequency,
        metric: MetricID
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            store.enableBackgroundDelivery(for: type, frequency: frequency) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: HealthKitObserverError.registrationFailed(
                            metric,
                            error?.localizedDescription ?? "unknown"
                        )
                    )
                }
            }
        }
    }

    private func stopQueries() {
        let active = lock.withLock {
            let active = queries
            queries.removeAll()
            return active
        }
        for query in active {
            store.stop(query)
        }
    }

    private func beginStart() -> Bool {
        lock.withLock {
            guard !started else { return false }
            started = true
            return true
        }
    }

    private func resetStarted() {
        lock.withLock {
            started = false
        }
    }

    private func retain(_ query: HKObserverQuery) {
        lock.withLock {
            queries.append(query)
        }
    }

    private func release(_ query: HKObserverQuery) {
        lock.withLock {
            queries.removeAll { $0 === query }
        }
        store.stop(query)
    }

    private static func frequency(for metric: MetricID) -> HKUpdateFrequency {
        switch metric {
        case MetricCatalog.heartRate.id:
            .immediate
        case MetricCatalog.stepCount.id, MetricCatalog.activeEnergy.id:
            .hourly
        case MetricCatalog.bodyMass.id, MetricCatalog.leanBodyMass.id:
            .weekly
        default:
            .daily
        }
    }
}
#endif
