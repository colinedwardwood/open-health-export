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

/// The automatic fan-out: one page per type to every destination the trigger allows,
/// the scheduled full reconcile, and the queue and trailing-reconcile follow-ups.
extension ExportService {
    func runOnePageEachMetric(
        metrics: [MetricID]? = nil,
        trigger: RunTrigger = .manual,
        onProgress: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> [String] {
        let plannedIDs = plannedDestinations(trigger: trigger)
        guard !plannedIDs.isEmpty else {
            return [ExportPlan.manualOnlyExportLine]
        }
        defer {
            for destinationID in plannedIDs {
                synchronizeDestinationExportRole(destinationID)
            }
        }
        let root = try AppFiles.applicationSupportRoot()
        var folderAccess: SecurityScopedAccess?
        if plannedIDs.contains("local-file") {
            folderAccess = try localExportFolder(root: root)
        }
        defer { withExtendedLifetime(folderAccess) {} }

        var destinations: [RunDestination] = []
        var traceparentEmissions: [(String, TraceparentEmission)] = []
        var unreconstructed: [String: ErrorClass] = [:]
        for destinationID in plannedIDs {
            do {
                let (destination, emission) = try await makeAutomaticRunDestination(
                    destinationID,
                    trigger: trigger,
                    root: root,
                    folderAccess: folderAccess
                )
                destinations.append(destination)
                if let emission {
                    traceparentEmissions.append((destinationID, emission))
                }
            } catch {
                // An enabled destination whose configuration or credential can no
                // longer be rebuilt is not exporting, and saying nothing would let
                // the other destinations' success stand in for it.
                unreconstructed[destinationID] =
                    (error as? DestinationSendError)?.errorClass ?? .internalFault
            }
        }
        for (destinationID, errorClass) in unreconstructed.sorted(by: { $0.key < $1.key }) {
            status.recordDestinationFailureSnapshot(destinationID, errorClass: errorClass)
            await status.notifyDestinationFailure(
                destinationID: destinationID,
                destinationLabel: destinationLabel(destinationID)
            )
        }
        guard !destinations.isEmpty else {
            return ["blocked: No destination could be reconstructed for this export."]
        }
        let scopes = destinations.compactMap(\.scope)
        for scope in scopes {
            try ExportScopeGate.requireConfigured(scope)
        }
        let metrics = metrics ?? ExportPlan.metrics(for: scopes)
        for metric in metrics {
            guard scopes.contains(where: { $0.metrics.contains(metric) }) else {
                throw ExportScopeViolation.metricNotSelected(
                    destinationID: destinations[0].id,
                    metric: metric
                )
            }
        }
        let sqliteURL = root.appendingPathComponent("state.sqlite")
        let dest = folderAccess?.url
        let scratch = try AppFiles.protectedPayloadDirectory(named: "scratch", under: root)

        let store = try StateStoreHost.store(path: sqliteURL.path)
        let gapIDsBefore = try await store.transact {
            Set(try $0.loadGaps().map(\.batchID))
        }
        if let dest {
            let (_, events) = try AppDestinationSetup.verifiedLocalFile(destinationDirectory: dest)
            try await AppDestinationSetup.service.emitTrustNotices(events, destination: "local-file")
        }
        // Anything still owed from an earlier read goes before this one. A failed
        // attempt leaves a durable obligation, and without this only the queue's
        // time-to-live would ever clear it.
        for destination in destinations where destination.attemptNow {
            try await drainPendingDeliveries(
                destination: destination.destination,
                destinationName: destination.id,
                store: store,
                scope: destination.scope,
                limit: ExportPlan.drainLimit(trigger: trigger)
            )
        }
        let context = TemporalContext.utcHost
        let source = HealthKitAnchoredSource(
            context: context,
            limit: samplePageLimit(),
            window: HealthKitQueryWindow(union: scopes)
        )
        let observations = HealthKitDayObservationSource(context: context, limit: samplePageLimit())
        let statistics = HealthKitStatisticsSource(context: context)
        let now = Date().ISO8601Format()
        let exporterId = try AppFiles.installationID()
        let ledgerSeal = AppFiles.ledgerHeadSeal()
        let ledgerSealURL = root.appendingPathComponent("ledger-head-seal.json")

        var lines: [String] = []
        var kinds: [RunOutcome.Kind] = []
        var kindsByDestination: [String: [RunOutcome.Kind]] = [:]
        for (index, metric) in metrics.enumerated() {
            await onProgress?(index + 1, metrics.count)
            let primary = destinations[0]
            let run = ExportRun(
                source: source,
                destination: primary.destination,
                store: store,
                metric: metric,
                scratchDirectory: scratch,
                destinationName: primary.id,
                envelope: WireEnvelope(
                    exporterId: exporterId,
                    seq: 1,
                    emittedAt: now,
                    observedAt: now
                ),
                temporal: context,
                statistics: statistics,
                observations: observations,
                characteristics: HealthKitCharacteristicSource(),
                trigger: trigger,
                snapshotURL: primary.snapshotURL,
                externalStatusURL: dest?.appendingPathComponent("status.json"),
                ledgerHeadSeal: ledgerSeal,
                ledgerSealURL: ledgerSealURL,
                scope: primary.scope,
                freshnessCadenceSeconds: freshnessCadenceSeconds(),
                deferForLowPower: isLowPowerDeferred(),
                destinations: destinations
            )
            let result = try await run.runFanout()
            let outcome = result.outcome
            kinds.append(outcome.kind)
            for destination in destinations {
                // A destination answers for itself. Reporting the combined outcome
                // against every sink told people a working archive folder had
                // failed because an unrelated server was unreachable.
                let own = result.kind(for: destination.id) ?? outcome.kind
                kindsByDestination[destination.id, default: []].append(own)
                await notifyIfFailed(
                    own,
                    destinationID: destination.id,
                    destinationLabel: destinationLabel(destination.id)
                )
                if ExportPlan.succeeded(own),
                   let snapshotURL = destination.snapshotURL {
                    await rescheduleOverdueNotification(snapshotURL: snapshotURL)
                }
            }
            reloadStatusWidget()
            lines.append("\(metric.rawValue): \(outcome.kind.rawValue)")

            let trailing = destinations.filter(\.attemptNow)
            if !trailing.isEmpty {
                lines.append(
                    try await trailingReconcileAfterDelta(
                        observations: observations,
                        destinations: trailing,
                        store: store,
                        metric: metric,
                        scratchDirectory: scratch,
                        envelope: WireEnvelope(
                            exporterId: exporterId,
                            seq: 1,
                            emittedAt: now,
                            observedAt: now
                        ),
                        temporal: context,
                        statistics: statistics,
                        trigger: trigger,
                        externalStatusURL: dest?.appendingPathComponent("status.json"),
                        ledgerHeadSeal: ledgerSeal,
                        ledgerSealURL: ledgerSealURL
                    )
                )
            }
        }
        let newQueueGap = try await store.transact {
            ExportPlan.evictedDuringRun(gaps: try $0.loadGaps(), before: gapIDsBefore)
        }
        if newQueueGap {
            _ = try await LocalUserNotifier().notify(
                UserNotice(kind: .queueEvicted, destination: "Configured destinations")
            )
        }
        if ScheduledReconcileGate.follows(trigger) {
            lines.append(
                contentsOf: try await maybeScheduledFullReconcile(
                    store: store,
                    trigger: trigger
                )
            )
        }
        for (destinationID, emission) in traceparentEmissions where emission.autoDisabled {
            if destinationID == "companion" {
                try AppDestinations.repository.setCompanionTraceparent(false)
            } else {
                try AppDestinations.repository.setHTTPSTraceparent(false, destinationID: destinationID)
            }
            lines.append(ExportPlan.traceparentAutoDisabledLine)
        }
        try await applyQueueRedIfNeeded(
            store: store,
            root: root,
            destinationLabel: destinationLabel(destinations[0].id)
        )
        try outcomes.applyRunOutcome(
            planned: plannedIDs,
            unreconstructed: Set(unreconstructed.keys),
            kindsByDestination: kindsByDestination,
            combined: CombinedExportSummary.kind(kinds)
        )
        for destinationID in unreconstructed.keys.sorted() {
            lines.append("\(destinationID): configuration could not be rebuilt for this export")
        }
        reloadStatusWidget()
        lines.insert(CombinedExportSummary.copy(kinds), at: 0)
        lines.append("Files: \(dest?.path ?? scratch.path)")
        return lines
    }

    /// O-9: a low-priority full reconcile on a daily cadence, skipped when the
    /// queue is already in I6 Amber so live deltas are not evicted.
    private func maybeScheduledFullReconcile(
        store: any StateStore,
        trigger: RunTrigger
    ) async throws -> [String] {
        let queued = try await store.transact { try $0.queuedBytes() }
        let nowEpoch = Date().timeIntervalSince1970
        switch scheduledReconcile.decide(queuedBytes: queued, nowEpoch: nowEpoch) {
        case .parked:
            return [ScheduledReconcileGate.parkedLine]
        case .notDue:
            return []
        case .due:
            let lines = try await runFullReconcile(trigger: trigger)
            scheduledReconcile.recordRun(atEpoch: nowEpoch)
            return [ScheduledReconcileGate.ranLine] + lines
        }
    }

    /// I6 Red: drop derived attempt bodies, truncate the WAL, and raise the
    /// approaching-loss notice. Live pending batches stay queued.
    func applyQueueRedIfNeeded(
        store: SQLiteStateStore,
        root: URL,
        destinationLabel: String
    ) async throws {
        let queued = try await store.transact { try $0.queuedBytes() }
        guard ExportPlan.queueIsRed(queuedBytes: queued) else { return }
        _ = try QueueRed.purgeAttemptCaches(root: root)
        try store.checkpointWAL()
        try await store.transact { tx in
            try tx.appendJournal(
                RunEvent(
                    runID: RunID(rawValue: "queue-red"),
                    outcomeKind: "partial",
                    detail: QueueRed.journalDetail,
                    wallTimeEpoch: Date().timeIntervalSince1970
                )
            )
        }
        _ = try await LocalUserNotifier().notify(
            UserNotice(kind: .queueApproachingLoss, destination: destinationLabel)
        )
    }

    /// R-08: every live destination run also applies the trailing seven-day sweep.
    /// Delta ExportRun does not itself reconcile. One trailing window is read once
    /// and fanned out; a sweep per sink would re-observe the same days and let the
    /// sinks be repaired from different observations of them.
    func trailingReconcileAfterDelta(
        observations: any DayObservationSource,
        destinations: [RunDestination],
        store: any StateStore,
        metric: MetricID,
        scratchDirectory: URL,
        envelope: WireEnvelope,
        temporal: TemporalContext,
        statistics: (any StatisticsSource)?,
        trigger: RunTrigger,
        externalStatusURL: URL? = nil,
        ledgerHeadSeal: (any LedgerHeadSeal)?,
        ledgerSealURL: URL?
    ) async throws -> String {
        let covering = ExportPlan.covering(destinations, metric: metric)
        guard !covering.isEmpty else {
            return "\(metric.rawValue) reconcile: \(RunOutcome.Kind.successNothingDue.rawValue)"
        }
        let rows = DestinationRowCollector()
        var sweep = ReconcileSweep(
            observations: observations,
            destination: covering[0].destination,
            store: store,
            metric: metric,
            scratchDirectory: scratchDirectory,
            destinationName: covering[0].id,
            envelope: envelope,
            temporal: temporal,
            statistics: statistics,
            trigger: trigger,
            snapshotURL: covering[0].snapshotURL,
            externalStatusURL: externalStatusURL,
            ledgerHeadSeal: ledgerHeadSeal,
            ledgerSealURL: ledgerSealURL,
            scope: covering[0].scope,
            freshnessCadenceSeconds: freshnessCadenceSeconds(),
            deferForLowPower: isLowPowerDeferred(),
            destinations: covering
        )
        sweep.rowCollector = rows
        let reconciled = try await sweep.run(
            throughDay: String(envelope.emittedAt.prefix(10))
        )
        let reported = await rows.rows()
        applyDestinationOutcomes(reported, to: covering.map(\.id))
        for destination in covering {
            let kind = DestinationRunRow.kind(for: destination.id, in: reported)
                ?? reconciled.kind
            await notifyIfFailed(
                kind,
                destinationID: destination.id,
                destinationLabel: destinationLabel(destination.id)
            )
            if ExportPlan.succeeded(kind),
               let snapshotURL = destination.snapshotURL
            {
                await rescheduleOverdueNotification(snapshotURL: snapshotURL)
            }
        }
        return "\(metric.rawValue) reconcile: \(reconciled.kind.rawValue)"
    }

    /// Reachable from the backfill runner.
    func applyBackfillOutcomes(
        _ rows: [DestinationRunRow],
        to destinationIDs: [String]
    ) {
        applyDestinationOutcomes(rows, to: destinationIDs)
    }
}
