// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppServices
import CoreDomain
import CorrectnessEngine
import EnginePorts
import Foundation
import HealthKitSource
import RunJournal
import StorageSQLite
import WidgetKit

/// The observer-registration failures in the app's preferences (key in SettingsStore).
struct PreferencesObserverFailureStorage: ObserverFailureStorage {
    private var key: String { SettingKey.observerRegistrationFailures.rawValue }

    func load() -> [String: String]? {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String]
    }

    func save(_ failures: [String: String]?) {
        if let failures {
            UserDefaults.standard.set(failures, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

/// Health authorization, revocation and observers (#42). The decisions live in
/// `HealthObserverPolicy` / `HealthAuthorizationPlan` (AppServices, tested); this is the
/// HealthKit, file and notification side.
struct HealthService: Sendable {
    let root: @Sendable () throws -> URL
    let store: @Sendable (URL) throws -> SQLiteStateStore
    let selectedMetrics: @Sendable () async throws -> [MetricID]
    let owedDestinations: @Sendable () -> [String]
    let failureLog: ObserverFailureLog

    func wakeLedger() throws -> WakeLedger {
        WakeLedger(path: try root().appendingPathComponent("wake-ledger.log").path)
    }

    /// R-44: checks the tracked grant for a revocation and, if one happened, drops what
    /// was owed, stops background delivery and tells the user. True when revoked.
    @discardableResult
    func observeAuthorizationChanges() async throws -> Bool {
        let root = try root()
        let metrics = try await selectedMetrics()
        guard !metrics.isEmpty else { return false }
        let grant = HealthAuthorizationGrant(
            id: HealthAuthorizationPlan.grantID,
            metrics: metrics
        )
        let observer = HealthAuthorizationObserver(
            recordURL: root.appendingPathComponent("health-authorization.json")
        )
        let changes = try await observer.observe(
            grants: [grant],
            atEpoch: Date().timeIntervalSince1970
        )
        guard !changes.isEmpty else { return false }

        let store = try store(root)
        let owed = owedDestinations()
        for change in changes {
            for purge in HealthAuthorizationPlan.purges(
                grantID: change.grant.id,
                metrics: change.grant.metrics,
                observedAtEpoch: change.observedAtEpoch,
                owedDestinations: owed
            ) {
                try await store.purgeType(
                    metric: purge.metric,
                    reason: purge.reason,
                    destination: purge.destination,
                    atEpoch: purge.atEpoch
                )
            }
            await HealthKitBackgroundDelivery.disable(metrics: change.grant.metrics)
            _ = try await LocalUserNotifier().notify(
                UserNotice(
                    kind: .healthAccessRevoked,
                    destination: change.grant.id
                )
            )
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
        return true
    }

    /// After the user asks Health for access again, every selected type exports again.
    func reenableAfterAuthorizationRequest() async throws {
        let store = try store(try root())
        for metric in try await selectedMetrics() {
            try await store.reenableType(
                metric: metric,
                reason: HealthAuthorizationPlan.reenableReason
            )
        }
    }

    /// Asks Health for one destination's types, once its scope is configured.
    func requestReadAccess(for scope: DestinationExportScope) async throws {
        guard let metrics = HealthAuthorizationPlan.readRequest(for: scope) else { return }
        try await HealthKitAuthorization.requestReadAccess(metrics: metrics)
    }

    /// Registers one observer per selected type. Each wake first checks for a
    /// revocation, then hands the type to `onWake`. Failures are recorded (#28).
    func startObservers(
        onWake: @escaping @Sendable (MetricID) async -> Void
    ) async throws -> HealthKitObserverCoordinator {
        let coordinator = HealthKitObserverCoordinator(
            wakeLedger: try wakeLedger()
        )
        let metrics = try await selectedMetrics()
        guard !metrics.isEmpty else {
            failureLog.record([:])
            return coordinator
        }
        let registration = try await coordinator.start(
            metrics: metrics
        ) { metric in
            try? await observeAuthorizationChanges()
            await onWake(metric)
        }
        failureLog.record(registration.failures)
        return coordinator
    }

    func observerRegistrationFailureSummary() -> String? {
        failureLog.summary()
    }
}

enum AppHealth {
    static let service = HealthService(
        root: { try HarnessExport.applicationSupportRoot() },
        store: { root in
            try StateStoreHost.store(path: root.appendingPathComponent("state.sqlite").path)
        },
        selectedMetrics: { try await HarnessExport.selectedMetrics() },
        owedDestinations: {
            HarnessExport.healthDestinationIDs.filter { HarnessExport.isDestinationEnabled($0) }
        },
        failureLog: ObserverFailureLog(storage: PreferencesObserverFailureStorage())
    )
}
