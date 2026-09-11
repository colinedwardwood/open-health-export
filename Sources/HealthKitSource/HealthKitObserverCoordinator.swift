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

/// One-observer-per-type fallback topology until R-71 G1 establishes that the
/// descriptor-based multi-type observer receives background deliveries.
public final class HealthKitObserverCoordinator: @unchecked Sendable {
    public typealias WakeHandler = @Sendable (MetricID) async -> Void

    private let store: HKHealthStore
    private let wakeLedger: WakeLedger
    private let clock: any Clock
    private let lock = NSLock()
    private var queries: [HKObserverQuery] = []
    private var started = false

    public init(
        store: HKHealthStore = HKHealthStore(),
        wakeLedger: WakeLedger,
        clock: any Clock = SystemClock()
    ) {
        self.store = store
        self.wakeLedger = wakeLedger
        self.clock = clock
    }

    public func start(
        metrics: [MetricID],
        onWake: @escaping WakeHandler
    ) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitObserverError.unavailable
        }
        guard beginStart() else { return }

        do {
            for metric in metrics {
                guard let type = SampleConversion.quantityType(for: metric) else {
                    throw HealthKitObserverError.unknownMetric(metric)
                }
                let query = makeQuery(type: type, metric: metric, onWake: onWake)
                retain(query)
                store.execute(query)
                try await enableBackgroundDelivery(
                    for: type,
                    frequency: Self.frequency(for: metric),
                    metric: metric
                )
            }
        } catch {
            stopQueries()
            resetStarted()
            throw error
        }
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
