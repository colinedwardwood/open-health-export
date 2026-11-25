// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2


import AppServices
import CompanionWire
import CoreDomain
import CoreTemporal
import CorrectnessEngine
import DestinationTrust
import EnginePorts
import FileWriteKit
import Foundation
import HealthKitSource
import MetricCatalog
import NetEgress
import RunJournal
import SinkCompanion
import StorageSQLite
import UIKit
import Watchdog
import WidgetKit
import WireFormat

/// The per-destination runs: Mac companion, MQTT and HTTPS.
extension ExportService {
    func runCompanion(
        session: PairingSession,
        onTestProgress: DestinationTestProgress? = nil,
        onProgress: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> [String] {
        defer { synchronizeDestinationExportRole("companion") }
        let scope = try await destinationScope("companion")
        try ExportScopeGate.requireConfigured(scope)
        let root = try AppFiles.applicationSupportRoot()
        let sqliteURL = root.appendingPathComponent("state.sqlite")
        let scratch = try AppFiles.protectedPayloadDirectory(named: "scratch", under: root)
        let store = try StateStoreHost.store(path: sqliteURL.path)
        let (verified, emission) = try await AppDestinationSetup.verifiedCompanion(
            session: session,
            onTestProgress: onTestProgress
        )
        try await drainPendingDeliveries(
            destination: verified,
            destinationName: "companion",
            store: store,
            scope: scope
        )
        try await requestScopeAuthorizationIfConfigured("companion")
        let context = TemporalContext.utcHost
        let source = HealthKitAnchoredSource(
            context: context,
            limit: samplePageLimit(),
            window: HealthKitQueryWindow(scope: scope)
        )
        let observations = HealthKitDayObservationSource(context: context, limit: samplePageLimit())
        let statistics = HealthKitStatisticsSource(context: context)
        let now = Date().ISO8601Format()
        let ledgerSeal = AppFiles.ledgerHeadSeal()
        let ledgerSealURL = root.appendingPathComponent("ledger-head-seal.json")
        var lines: [String] = []
        let metrics = scope.metrics.sorted { $0.rawValue < $1.rawValue }
        for (index, metric) in metrics.enumerated() {
            await onProgress?(index + 1, metrics.count)
            let run = ExportRun(
                source: source,
                destination: verified,
                store: store,
                metric: metric,
                scratchDirectory: scratch,
                destinationName: "companion",
                envelope: WireEnvelope(
                    exporterId: session.localInstallationID,
                    seq: 1,
                    emittedAt: now,
                    observedAt: now
                ),
                temporal: context,
                statistics: statistics,
                observations: observations,
                characteristics: HealthKitCharacteristicSource(),
                snapshotURL: StatusSnapshotLocation.url(destinationID: "companion"),
                ledgerHeadSeal: ledgerSeal,
                ledgerSealURL: ledgerSealURL,
                scope: scope,
                freshnessCadenceSeconds: freshnessCadenceSeconds(),
                deferForLowPower: isLowPowerDeferred()
            )
            let outcome = try await run.run()
            await notifyIfFailed(
                outcome.kind,
                destinationID: "companion",
                destinationLabel: "Mac companion"
            )
            reloadStatusWidget()
            lines.append("\(metric.rawValue): \(outcome.kind.rawValue)")
            lines.append(
                try await trailingReconcileAfterDelta(
                    observations: observations,
                    destinations: [
                        RunDestination(
                            id: "companion",
                            destination: verified,
                            scope: scope,
                            snapshotURL: StatusSnapshotLocation.url(destinationID: "companion")
                        ),
                    ],
                    store: store,
                    metric: metric,
                    scratchDirectory: scratch,
                    envelope: WireEnvelope(
                        exporterId: session.localInstallationID,
                        seq: 1,
                        emittedAt: now,
                        observedAt: now
                    ),
                    temporal: context,
                    statistics: statistics,
                    trigger: .manual,
                    ledgerHeadSeal: ledgerSeal,
                    ledgerSealURL: ledgerSealURL
                )
            )
        }
        if emission.autoDisabled {
            try AppDestinations.repository.setCompanionTraceparent(false)
            lines.append(ExportPlan.traceparentAutoDisabledLine)
        }
        lines.append("Companion: \(session.serviceName)")
        try await applyQueueRedIfNeeded(
            store: store,
            root: root,
            destinationLabel: "Mac companion"
        )
        return lines
    }

    func runMQTTDestination(
        onProgress: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> [String] {
        defer { synchronizeDestinationExportRole("mqtt") }
        let root = try AppFiles.applicationSupportRoot()
        let verified = try await AppDestinationSetup.verifiedMQTT(root: root)
        let store = try stateStore(root)
        let scratch = try AppFiles.protectedPayloadDirectory(named: "scratch", under: root)
        let context = TemporalContext.utcHost
        let now = Date().ISO8601Format()
        let exporterID = try AppFiles.installationID()
        var lines: [String] = []
        let scope = try await destinationScope("mqtt")
        try ExportScopeGate.requireConfigured(scope)
        let source = HealthKitAnchoredSource(
            context: context,
            limit: samplePageLimit(),
            window: HealthKitQueryWindow(scope: scope)
        )
        let observations = HealthKitDayObservationSource(context: context)
        let statistics = HealthKitStatisticsSource(context: context)
        let snapshotURL = StatusSnapshotLocation.url(destinationID: "mqtt")
        let ledgerSeal = AppFiles.ledgerHeadSeal()
        let ledgerSealURL = root.appendingPathComponent("ledger-head-seal.json")
        let metrics = scope.metrics.sorted { $0.rawValue < $1.rawValue }
        for (index, metric) in metrics.enumerated() {
            await onProgress?(index + 1, metrics.count)
            let envelope = WireEnvelope(
                exporterId: exporterID,
                seq: 1,
                emittedAt: now,
                observedAt: now
            )
            let outcome = try await ExportRun(
                source: source,
                destination: verified,
                store: store,
                metric: metric,
                scratchDirectory: scratch,
                destinationName: "mqtt",
                envelope: envelope,
                temporal: context,
                statistics: statistics,
                observations: observations,
                characteristics: HealthKitCharacteristicSource(),
                trigger: .manual,
                snapshotURL: snapshotURL,
                ledgerHeadSeal: ledgerSeal,
                ledgerSealURL: ledgerSealURL,
                scope: scope,
                freshnessCadenceSeconds: freshnessCadenceSeconds(),
                deferForLowPower: isLowPowerDeferred()
            ).run()
            await notifyIfFailed(
                outcome.kind,
                destinationID: "mqtt",
                destinationLabel: "MQTT destination"
            )
            lines.append("\(metric.rawValue): \(outcome.kind.rawValue)")
            lines.append(
                try await trailingReconcileAfterDelta(
                    observations: observations,
                    destinations: [
                        RunDestination(
                            id: "mqtt",
                            destination: verified,
                            scope: scope,
                            snapshotURL: snapshotURL
                        ),
                    ],
                    store: store,
                    metric: metric,
                    scratchDirectory: scratch,
                    envelope: envelope,
                    temporal: context,
                    statistics: statistics,
                    trigger: .manual,
                    ledgerHeadSeal: ledgerSeal,
                    ledgerSealURL: ledgerSealURL
                )
            )
        }
        reloadStatusWidget()
        try await applyQueueRedIfNeeded(
            store: store,
            root: root,
            destinationLabel: "MQTT destination"
        )
        return lines
    }

    func runHTTPSDestination(
        destinationID: String = "https",
        destinationLabel: String = "HTTPS destination",
        onProgress: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> [String] {
        defer { synchronizeDestinationExportRole(destinationID) }
        return try await withThermalCompression {
            try await runHTTPSDestinationUnscoped(
                destinationID: destinationID,
                destinationLabel: destinationLabel,
                onProgress: onProgress
            )
        }
    }

    private func runHTTPSDestinationUnscoped(
        destinationID: String,
        destinationLabel: String,
        onProgress: (@Sendable (Int, Int) async -> Void)?
    ) async throws -> [String] {
        let root = try AppFiles.applicationSupportRoot()
        // The transport inside holds a background-task assertion per request (#27).
        let (verified, emission) = try await AppDestinationSetup.verifiedHTTPS(
            destinationID: destinationID,
            root: root
        )
        let store = try stateStore(root)
        let scratch = try AppFiles.protectedPayloadDirectory(named: "scratch", under: root)
        let context = TemporalContext.utcHost
        let now = Date().ISO8601Format()
        let exporterID = try AppFiles.installationID()
        var lines: [String] = []
        let scope = try await destinationScope(destinationID)
        try ExportScopeGate.requireConfigured(scope)
        let source = HealthKitAnchoredSource(
            context: context,
            limit: samplePageLimit(),
            window: HealthKitQueryWindow(scope: scope)
        )
        let observations = HealthKitDayObservationSource(context: context)
        let statistics = HealthKitStatisticsSource(context: context)
        let snapshotURL = StatusSnapshotLocation.url(destinationID: destinationID)
        let ledgerSeal = AppFiles.ledgerHeadSeal()
        let ledgerSealURL = root.appendingPathComponent("ledger-head-seal.json")
        let metrics = scope.metrics.sorted { $0.rawValue < $1.rawValue }
        for (index, metric) in metrics.enumerated() {
            await onProgress?(index + 1, metrics.count)
            let envelope = WireEnvelope(
                exporterId: exporterID,
                seq: 1,
                emittedAt: now,
                observedAt: now
            )
            let outcome = try await ExportRun(
                source: source,
                destination: verified,
                store: store,
                metric: metric,
                scratchDirectory: scratch,
                destinationName: destinationID,
                envelope: envelope,
                temporal: context,
                statistics: statistics,
                observations: observations,
                characteristics: HealthKitCharacteristicSource(),
                trigger: .manual,
                snapshotURL: snapshotURL,
                ledgerHeadSeal: ledgerSeal,
                ledgerSealURL: ledgerSealURL,
                scope: scope,
                freshnessCadenceSeconds: freshnessCadenceSeconds(),
                deferForLowPower: isLowPowerDeferred()
            ).run()
            await notifyIfFailed(
                outcome.kind,
                destinationID: destinationID,
                destinationLabel: destinationLabel
            )
            lines.append("\(metric.rawValue): \(outcome.kind.rawValue)")
            lines.append(
                try await trailingReconcileAfterDelta(
                    observations: observations,
                    destinations: [
                        RunDestination(
                            id: destinationID,
                            destination: verified,
                            scope: scope,
                            snapshotURL: snapshotURL
                        ),
                    ],
                    store: store,
                    metric: metric,
                    scratchDirectory: scratch,
                    envelope: envelope,
                    temporal: context,
                    statistics: statistics,
                    trigger: .manual,
                    ledgerHeadSeal: ledgerSeal,
                    ledgerSealURL: ledgerSealURL
                )
            )
        }
        if emission.autoDisabled {
            try AppDestinations.repository.setHTTPSTraceparent(false, destinationID: destinationID)
            lines.append(ExportPlan.traceparentAutoDisabledLine)
        }
        reloadStatusWidget()
        try await applyQueueRedIfNeeded(
            store: store,
            root: root,
            destinationLabel: destinationLabel
        )
        return lines
    }
}
