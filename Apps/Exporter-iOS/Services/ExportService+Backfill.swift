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

private actor CountingBackfillObservations: DayObservationSource {
    let base: HealthKitDayObservationSource
    private var samplesRead = 0

    init(base: HealthKitDayObservationSource) {
        self.base = base
    }

    func samples(metric: MetricID, day: String) async throws -> [SampleRecord] {
        let samples = try await base.samples(metric: metric, day: day)
        samplesRead += samples.count
        return samples
    }

    func count() -> Int {
        samplesRead
    }
}

private struct HealthBackfillProcessor: BackfillChunkProcessor {
    var observations: HealthKitDayObservationSource
    var statistics: HealthKitStatisticsSource
    /// Every sink this job was planned for. History is the one read a user waits
    /// minutes for: it is read once and fans out, so an archive-only backfill would
    /// leave the other sinks holding today's data and nothing before it, and a
    /// sweep per sink would multiply the read the R-75 budget measures.
    var destinations: [RunDestination]
    var store: any StateStore
    var scratchDirectory: URL
    var exporterID: String
    var temporal: TemporalContext
    var ledgerHeadSeal: any LedgerHeadSeal
    var ledgerSealURL: URL
    var externalStatusDirectory: URL?
    var tuning: ExportTuning
    var outcomes: ExportOutcomeRecorder

    func process(
        metric: MetricID,
        days: [String],
        mode: BackfillMode
    ) async throws -> BackfillChunkResult {
        let owed = ExportPlan.covering(destinations, metric: metric)
        guard !owed.isEmpty else {
            return BackfillChunkResult(samplesRead: 0, batchesEnqueued: 0)
        }
        let counted = CountingBackfillObservations(base: observations)
        let now = Date().ISO8601Format()
        let rows = DestinationRowCollector()
        var sweep = ReconcileSweep(
            observations: counted,
            destination: owed[0].destination,
            store: store,
            metric: metric,
            scratchDirectory: scratchDirectory,
            destinationName: owed[0].id,
            envelope: WireEnvelope(
                exporterId: exporterID,
                seq: 1,
                emittedAt: now,
                observedAt: now
            ),
            temporal: temporal,
            statistics: statistics,
            trigger: .manual,
            snapshotURL: owed[0].snapshotURL
                ?? StatusSnapshotLocation.url(destinationID: owed[0].id),
            externalStatusURL: externalStatusDirectory?
                .appendingPathComponent("status.json"),
            ledgerHeadSeal: ledgerHeadSeal,
            ledgerSealURL: ledgerSealURL,
            scope: owed[0].scope,
            freshnessCadenceSeconds: tuning.freshnessCadenceSeconds(),
            deferForLowPower: tuning.isLowPowerDeferred(),
            destinations: owed
        )
        sweep.rowCollector = rows
        let outcome = try await sweep.runBackfill(days: days, mode: mode)
        outcomes.apply(await rows.rows(), to: owed.map(\.id))
        return BackfillChunkResult(
            samplesRead: await counted.count(),
            batchesEnqueued: outcome.kind == RunOutcome.Kind.successNothingDue ? 0 : 1
        )
    }
}

/// Full reconcile, backfill and queue-gap re-exports.
extension ExportService {
    /// R-08's history half. A full reconcile repairs what a delta cannot see, so
    /// running it against the archive folder alone would leave every other sink with
    /// history nobody ever repairs.
    func runFullReconcile(
        metrics: [MetricID]? = nil,
        trigger: RunTrigger = .manual,
        onProgress: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> [String] {
        let plannedIDs = plannedDestinations(trigger: trigger)
        guard !plannedIDs.isEmpty else {
            return [ExportPlan.manualOnlyReconcileLine]
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
        let scratch = try AppFiles.protectedPayloadDirectory(named: "scratch", under: root)
        let store = try stateStore(root)
        let context = TemporalContext.utcHost
        let observations = HealthKitDayObservationSource(
            context: context,
            limit: samplePageLimit()
        )
        let statistics = HealthKitStatisticsSource(context: context)
        let now = Date().ISO8601Format()
        let exporterID = try AppFiles.installationID()
        let seal = AppFiles.ledgerHeadSeal()
        var destinations: [RunDestination] = []
        for destinationID in plannedIDs {
            guard
                let (destination, _) = try? await makeAutomaticRunDestination(
                    destinationID,
                    trigger: trigger,
                    root: root,
                    folderAccess: folderAccess
                ),
                // A sink with no transport in this context keeps its queued
                // obligations; reconciling it here would have nowhere to send.
                destination.attemptNow
            else { continue }
            destinations.append(destination)
        }
        guard !destinations.isEmpty else {
            return ["blocked: No destination could be reconstructed for this reconcile."]
        }
        var lines: [String] = []
        // One history read repairs every sink that was owed it. Sweeping per sink
        // read the same days once per destination and let two sinks be repaired
        // from two different observations of the same day.
        let owed = metrics ?? ExportPlan.metrics(for: destinations.compactMap(\.scope))
        for (index, metric) in owed.enumerated() {
            let covering = ExportPlan.covering(destinations, metric: metric)
            guard !covering.isEmpty else { continue }
            await onProgress?(index + 1, owed.count)
            let rows = DestinationRowCollector()
            var sweep = ReconcileSweep(
                observations: observations,
                destination: covering[0].destination,
                store: store,
                metric: metric,
                scratchDirectory: scratch,
                destinationName: covering[0].id,
                envelope: WireEnvelope(
                    exporterId: exporterID,
                    seq: 1,
                    emittedAt: now,
                    observedAt: now
                ),
                temporal: context,
                statistics: statistics,
                trigger: trigger,
                snapshotURL: covering[0].snapshotURL,
                externalStatusURL: folderAccess?.url
                    .appendingPathComponent("status.json"),
                ledgerHeadSeal: seal,
                ledgerSealURL: root.appendingPathComponent("ledger-head-seal.json"),
                scope: covering[0].scope,
                freshnessCadenceSeconds: freshnessCadenceSeconds(),
                deferForLowPower: isLowPowerDeferred(),
                destinations: covering
            )
            sweep.rowCollector = rows
            let outcome = try await sweep.runFullHistory(throughDay: String(now.prefix(10)))
            let reported = await rows.rows()
            applyDestinationOutcomes(reported, to: covering.map(\.id))
            for destination in covering {
                // A repair that failed for one sink is not news about the others.
                await notifyIfFailed(
                    DestinationRunRow.kind(for: destination.id, in: reported) ?? outcome.kind,
                    destinationID: destination.id,
                    destinationLabel: destinationLabel(destination.id)
                )
            }
            lines.append(
                "\(covering.map(\.id).joined(separator: ",")) \(metric.rawValue) full reconcile: \(outcome.kind.rawValue)"
            )
        }
        reloadStatusWidget()
        if let dest = folderAccess?.url {
            lines.append("Files: \(dest.path)")
        }
        return lines
    }

    func runBackfill(
        mode: BackfillMode,
        onProgress: (@Sendable (String) async -> Void)? = nil
    ) async throws -> [String] {
        // Backfill is an explicit user action (R-11/O-5), so manual-only sinks count.
        let plannedIDs = ExportPlan.backfillDestinations(
            among: healthDestinationIDs,
            isEnabled: destinations.isEnabled
        )
        guard !plannedIDs.isEmpty else {
            return [ExportPlan.noBackfillDestinationLine]
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
        let scratch = try AppFiles.protectedPayloadDirectory(named: "backfill-scratch", under: root)
        let store = try stateStore(root)
        let context = TemporalContext.utcHost
        let observations = HealthKitDayObservationSource(context: context, limit: samplePageLimit())

        let checkpointURL = root.appendingPathComponent(
            mode == .raw ? "backfill-raw.json" : "backfill-aggregate.json"
        )
        let resumed = try? BackfillCheckpoint.read(from: checkpointURL)
        let owedIDs = ExportPlan.backfillOwed(
            planned: plannedIDs,
            resumedPlan: resumed?.plan.destinations
        )

        var destinations: [RunDestination] = []
        for destinationID in owedIDs {
            guard
                let (destination, _) = try? await makeAutomaticRunDestination(
                    destinationID,
                    trigger: .manual,
                    root: root,
                    folderAccess: folderAccess
                ),
                destination.attemptNow
            else { continue }
            destinations.append(destination)
        }
        guard !destinations.isEmpty else {
            return ["blocked: No destination could be reconstructed for this backfill."]
        }
        let scopes = destinations.compactMap(\.scope)
        for scope in scopes {
            try ExportScopeGate.requireConfigured(scope)
        }
        var available: [MetricID: ClosedRange<String>] = [:]
        for metric in ExportPlan.metrics(for: scopes) {
            if let range = try? await observations.availableDayRange(metric: metric) {
                available[metric] = range
            }
        }
        guard let window = ExportPlan.backfillWindow(scopes: scopes, available: available) else {
            return [ExportPlan.noBackfillHistoryLine]
        }

        let processor = HealthBackfillProcessor(
            observations: observations,
            statistics: HealthKitStatisticsSource(context: context),
            destinations: destinations,
            store: store,
            scratchDirectory: scratch,
            exporterID: try AppFiles.installationID(),
            temporal: context,
            ledgerHeadSeal: AppFiles.ledgerHeadSeal(),
            ledgerSealURL: root.appendingPathComponent("ledger-head-seal.json"),
            externalStatusDirectory: folderAccess?.url,
            tuning: tuning,
            outcomes: outcomes
        )
        let job = BackfillJob(
            checkpointURL: checkpointURL,
            processor: processor,
            store: store,
            deferForLowPower: isLowPowerDeferred(),
            deferForThermal: isThermalDeferred()
        )
        if !FileManager.default.fileExists(atPath: checkpointURL.path) {
            let hostModel = await UIDevice.current.model
            try await job.create(
                BackfillCheckpoint(
                    jobID: UUID().uuidString,
                    createdAt: Date().ISO8601Format(),
                    hostModel: hostModel,
                    plan: BackfillPlan(
                        windowStartDay: window.firstDay,
                        windowEndDay: window.lastDay,
                        mode: mode,
                        metrics: window.metrics,
                        destinations: destinations.map(\.id)
                    )
                )
            )
        }
        let completed = try await job.run(onProgress: onProgress)
        reloadStatusWidget()
        if let parked = completed.progress.pausedReason {
            return [
                "\(mode.rawValue) backfill parked",
                parked,
                "Samples read: \(completed.progress.samplesRead)",
                "Batches enqueued: \(completed.progress.batchesEnqueued)",
                "Checkpoint: \(checkpointURL.path)",
            ]
        }
        var lines = [
            "\(mode.rawValue) backfill complete",
            "Destinations: \(destinations.map(\.id).joined(separator: ", "))",
            "Samples read: \(completed.progress.samplesRead)",
            "Batches enqueued: \(completed.progress.batchesEnqueued)",
            "Checkpoint: \(checkpointURL.path)",
        ]
        // The completion manifest describes the archive folder, so it is published
        // only where there is a folder to publish it into.
        if let destinationDirectory = folderAccess?.url {
            let published = destinationDirectory.appendingPathComponent("archive-manifest.json")
            try ArchiveCompletionManifest.make(from: completed).write(to: published)
            lines.append("Manifest: \(published.path)")
        }
        return lines
    }

    // MARK: Queue gaps

    func queueEvictionGaps() async throws -> [GapRecord] {
        let store = try stateStore(try AppFiles.applicationSupportRoot())
        return try await store.transact {
            ExportPlan.reExportableQueueGaps(try $0.loadGaps())
        }
    }

    /// An evicted batch was owed to every destination that was planned when it was
    /// read, so re-exporting the gap to the archive folder alone would leave the other
    /// sinks permanently short those records.
    func reExportQueueGap(_ gap: GapRecord) async throws -> RunOutcome.Kind {
        let plannedIDs = plannedDestinations(trigger: .manual)
        let root = try AppFiles.applicationSupportRoot()
        var folderAccess: SecurityScopedAccess?
        if plannedIDs.contains("local-file") {
            folderAccess = try localExportFolder(root: root)
        }
        defer { withExtendedLifetime(folderAccess) {} }
        let scratch = try AppFiles.protectedPayloadDirectory(named: "scratch", under: root)
        let store = try stateStore(root)
        let context = TemporalContext.utcHost
        let now = Date().ISO8601Format()
        let exporterID = try AppFiles.installationID()
        var owed: [RunDestination] = []
        for destinationID in plannedIDs {
            guard
                let (destination, _) = try? await makeAutomaticRunDestination(
                    destinationID,
                    trigger: .manual,
                    root: root,
                    folderAccess: folderAccess
                ),
                destination.attemptNow,
                ExportPlan.covers(destination.scope, metric: gap.metric)
            else { continue }
            owed.append(destination)
        }
        guard !owed.isEmpty else { return .successNothingDue }
        // The gap is a range of days, not a destination's problem: read it once and
        // re-export it to everyone who was owed it.
        let rows = DestinationRowCollector()
        var sweep = ReconcileSweep(
            observations: HealthKitDayObservationSource(
                context: context,
                limit: samplePageLimit()
            ),
            destination: owed[0].destination,
            store: store,
            metric: gap.metric,
            scratchDirectory: scratch,
            destinationName: owed[0].id,
            envelope: WireEnvelope(
                exporterId: exporterID,
                seq: 1,
                emittedAt: now,
                observedAt: now
            ),
            temporal: context,
            statistics: HealthKitStatisticsSource(context: context),
            trigger: .manual,
            snapshotURL: owed[0].snapshotURL,
            externalStatusURL: folderAccess?.url
                .appendingPathComponent("status.json"),
            ledgerHeadSeal: AppFiles.ledgerHeadSeal(),
            ledgerSealURL: root.appendingPathComponent("ledger-head-seal.json"),
            scope: owed[0].scope,
            freshnessCadenceSeconds: freshnessCadenceSeconds(),
            deferForLowPower: isLowPowerDeferred(),
            destinations: owed
        )
        sweep.rowCollector = rows
        let outcome = try await sweep.run(gap: gap)
        let reported = await rows.rows()
        applyDestinationOutcomes(reported, to: owed.map(\.id))
        for destination in owed {
            await notifyIfFailed(
                DestinationRunRow.kind(for: destination.id, in: reported) ?? outcome.kind,
                destinationID: destination.id,
                destinationLabel: destinationLabel(destination.id)
            )
        }
        reloadStatusWidget()
        return outcome.kind
    }
}
