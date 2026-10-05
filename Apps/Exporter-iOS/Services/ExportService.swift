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

// MARK: Settings and device conditions

/// The export settings in the app's preferences (keys in SettingsStore).
struct PreferencesExportSettings: ExportSettingsStorage {
    func exportWindowHours() -> Int? {
        UserDefaults.standard.object(forKey: SettingKey.exportWindowHours.rawValue) as? Int
    }

    func freshnessIntervalMinutes() -> Int? {
        UserDefaults.standard.object(forKey: SettingKey.freshnessIntervalMinutes.rawValue) as? Int
    }

    func lastScheduledFullReconcileEpoch() -> TimeInterval? {
        let stored = UserDefaults.standard.double(
            forKey: SettingKey.lastScheduledFullReconcileEpoch.rawValue
        )
        return stored > 0 ? stored : nil
    }

    func setLastScheduledFullReconcileEpoch(_ epoch: TimeInterval) {
        UserDefaults.standard.set(epoch, forKey: SettingKey.lastScheduledFullReconcileEpoch.rawValue)
    }
}

/// Low Power Mode and the thermal state from the process, and the network path.
struct SystemExportConditions: ExportConditionsSource {
    func conditions() -> ExportConditions {
        let thermal: ThermalLevel = switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
        return ExportConditions(
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermal: thermal
        )
    }

    func networkPath() -> NetworkPathConditions {
        NetworkPathMonitorCache.conditions()
    }
}

// MARK: Run plumbing

/// A companion sink in a context with no transport: the obligation is queued, and no
/// attempt is made.
private struct QueuedWithoutAttemptSink: DestinationSink {
    func send(fileHandle: String, idempotencyKey: BatchID) async throws -> DeliveryReceipt {
        throw DestinationSendError.destinationUnreachable
    }
}

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

/// Observer wakes for one type at a time: a wake that arrives while a run is going
/// joins the queue rather than starting a second run.
actor ObserverExportGate {
    static let shared = ObserverExportGate()
    private var pending: Set<MetricID> = []
    private var running = false

    func enqueue(_ metric: MetricID) async {
        guard AppExport.service.destinations.hasAutomaticExport(trigger: .observerQuery) else {
            return
        }
        pending.insert(metric)
        guard !running else { return }
        running = true
        defer { running = false }
        while let next = pending.first {
            pending.remove(next)
            _ = try? await AppExport.service.runOnePageEachMetric(
                metrics: [next],
                trigger: .observerQuery
            )
        }
    }
}

// MARK: Export service

/// Runs exports (#42): the automatic fan-out, full reconciles, backfill, gap
/// re-exports, the per-destination runs, queue expiry and recovery, and the wipe. The
/// decisions live in `ExportPlan`, `ExportTuning`, `ScheduledReconcileGate` and
/// `ExportOutcomeRecorder` (AppServices, tested); this is the HealthKit, store and
/// system side. Destination construction still goes through HarnessExport's bridges.
struct ExportService: Sendable {
    let tuning: ExportTuning
    let scheduledReconcile: ScheduledReconcileGate
    let outcomes: ExportOutcomeRecorder
    let status: StatusService
    let destinations: DestinationRepository

    // MARK: Tuning

    func samplePageLimit() -> Int { tuning.samplePageLimit() }

    func freshnessCadenceSeconds() -> TimeInterval { tuning.freshnessCadenceSeconds() }

    func isLowPowerDeferred() -> Bool { tuning.isLowPowerDeferred() }

    func isThermalDeferred() -> Bool { tuning.isThermalDeferred() }

    func networkPathConditions() -> NetworkPathConditions { tuning.networkPathConditions() }

    func gzipLevel() -> Int32 {
        tuning.prefersStoredCompression() ? Gzip.storedLevel : Gzip.speedLevel
    }

    func withThermalCompression<T>(
        _ body: () async throws -> T
    ) async rethrows -> T {
        try await Gzip.$level.withValue(gzipLevel(), operation: body)
    }

    // MARK: Helpers

    private var healthDestinationIDs: [String] { DestinationRepository.healthDestinationIDs }

    private func plannedDestinations(trigger: RunTrigger) -> [String] {
        ExportPlan.destinations(
            for: trigger,
            among: healthDestinationIDs,
            isEnabled: destinations.isEnabled,
            allowsExport: destinations.allowsExport
        )
    }

    private func destinationScope(_ destinationID: String) async throws -> DestinationExportScope {
        try await destinations.scope(destinationID)
    }

    private func destinationLabel(_ destinationID: String) -> String {
        DestinationRepository.label(destinationID)
    }

    private func synchronizeDestinationExportRole(_ destinationID: String) {
        destinations.synchronizeExportRole(destinationID)
    }

    private func requestScopeAuthorizationIfConfigured(_ destinationID: String) async throws {
        try await AppHealth.service.requestReadAccess(for: try await destinationScope(destinationID))
    }

    private func notifyIfFailed(
        _ kind: RunOutcome.Kind,
        destinationID: String,
        destinationLabel: String
    ) async {
        await status.notifyIfFailed(kind, destinationID: destinationID, destinationLabel: destinationLabel)
    }

    private func rescheduleOverdueNotification(snapshotURL: URL) async {
        guard let snapshot = try? DestinationSnapshotFile.read(from: snapshotURL) else { return }
        await status.rescheduleOverdueNotification(for: snapshot)
    }

    private func applyDestinationOutcomes(
        _ rows: [DestinationRunRow],
        to destinationIDs: [String]
    ) {
        outcomes.apply(rows, to: destinationIDs)
    }

    /// The one shared store for the process (#26).
    private func stateStore(_ root: URL) throws -> SQLiteStateStore {
        try StateStoreHost.store(path: root.appendingPathComponent("state.sqlite").path)
    }

    private func localExportFolder(root: URL) throws -> SecurityScopedAccess {
        try AppDestinations.folder.access(root: root)
    }

    private func reloadStatusWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
    }

    // MARK: Destinations for a run

    private func makeAutomaticRunDestination(
        _ destinationID: String,
        trigger: RunTrigger,
        root: URL,
        folderAccess: SecurityScopedAccess?
    ) async throws -> (RunDestination, TraceparentEmission?) {
        let scope = try await destinationScope(destinationID)
        let role = destinations.exportRole(destinationID)
        let snapshotURL = StatusSnapshotLocation.url(destinationID: destinationID)
        switch destinationID {
        case "local-file":
            guard let folderAccess else {
                throw LocalExportFolderError.notSelected
            }
            let (verified, _) = try HarnessExport.exportVerifiedLocalFile(
                root: root,
                destinationDirectory: folderAccess.url
            )
            return (
                RunDestination(
                    id: destinationID,
                    destination: verified,
                    scope: scope,
                    role: role,
                    snapshotURL: snapshotURL
                ),
                nil
            )
        case "https", "home-assistant":
            let (verified, emission) = try await HarnessExport.exportVerifiedHTTPSDestination(
                destinationID: destinationID,
                root: root
            )
            return (
                RunDestination(
                    id: destinationID,
                    destination: verified,
                    scope: scope,
                    role: role,
                    snapshotURL: snapshotURL
                ),
                emission
            )
        case "mqtt":
            return (
                RunDestination(
                    id: destinationID,
                    destination: try await HarnessExport.exportVerifiedMQTTDestination(root: root),
                    scope: scope,
                    role: role,
                    snapshotURL: snapshotURL
                ),
                nil
            )
        case "companion":
            if trigger.attemptsCompanionTransport {
                let session = try await HarnessExport.vault().load()
                let (verified, emission) = try await HarnessExport.exportVerifiedCompanionDestination(
                    session: session,
                    root: root
                )
                return (
                    RunDestination(
                        id: destinationID,
                        destination: verified,
                        scope: scope,
                        role: role,
                        snapshotURL: snapshotURL
                    ),
                    emission
                )
            }
            return (
                RunDestination(
                    id: destinationID,
                    destination: .testing(QueuedWithoutAttemptSink()),
                    scope: scope,
                    role: role,
                    snapshotURL: snapshotURL,
                    attemptNow: false
                ),
                nil
            )
        default:
            throw DestinationSendError.destinationUnreachable
        }
    }

    private func drainPendingDeliveries(
        destination: VerifiedDestination,
        destinationName: String,
        store: SQLiteStateStore,
        scope: DestinationExportScope?,
        limit: Int = 32
    ) async throws {
        for _ in 0..<max(1, limit) {
            let receipts = try await PendingDeliveryRunner(
                destination: destination,
                store: store,
                destinationName: destinationName,
                scope: scope
            ).runOnce()
            if receipts.isEmpty { return }
        }
    }

    // MARK: Automatic export

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
        let root = try HarnessExport.applicationSupportRoot()
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
        let scratch = try HarnessExport.exportProtectedPayloadDirectory(named: "scratch", under: root)

        let store = try StateStoreHost.store(path: sqliteURL.path)
        let gapIDsBefore = try await store.transact {
            Set(try $0.loadGaps().map(\.batchID))
        }
        if let dest {
            let (_, events) = try HarnessExport.exportVerifiedLocalFile(root: root, destinationDirectory: dest)
            try await HarnessExport.exportEmitTrustNotices(events)
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
        let exporterId = try HarnessExport.installationID()
        let ledgerSeal = HarnessExport.ledgerHeadSeal()
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
                try HarnessExport.setCompanionTraceparent(false)
            } else {
                try HarnessExport.setHTTPSTraceparent(false, destinationID: destinationID)
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
    private func applyQueueRedIfNeeded(
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
    private func trailingReconcileAfterDelta(
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

    // MARK: Full reconcile and backfill

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
        let root = try HarnessExport.applicationSupportRoot()
        var folderAccess: SecurityScopedAccess?
        if plannedIDs.contains("local-file") {
            folderAccess = try localExportFolder(root: root)
        }
        defer { withExtendedLifetime(folderAccess) {} }
        let scratch = try HarnessExport.exportProtectedPayloadDirectory(named: "scratch", under: root)
        let store = try stateStore(root)
        let context = TemporalContext.utcHost
        let observations = HealthKitDayObservationSource(
            context: context,
            limit: samplePageLimit()
        )
        let statistics = HealthKitStatisticsSource(context: context)
        let now = Date().ISO8601Format()
        let exporterID = try HarnessExport.installationID()
        let seal = HarnessExport.ledgerHeadSeal()
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
        let root = try HarnessExport.applicationSupportRoot()
        var folderAccess: SecurityScopedAccess?
        if plannedIDs.contains("local-file") {
            folderAccess = try localExportFolder(root: root)
        }
        defer { withExtendedLifetime(folderAccess) {} }
        let scratch = try HarnessExport.exportProtectedPayloadDirectory(named: "backfill-scratch", under: root)
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
            exporterID: try HarnessExport.installationID(),
            temporal: context,
            ledgerHeadSeal: HarnessExport.ledgerHeadSeal(),
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
        let store = try stateStore(try HarnessExport.applicationSupportRoot())
        return try await store.transact {
            ExportPlan.reExportableQueueGaps(try $0.loadGaps())
        }
    }

    /// An evicted batch was owed to every destination that was planned when it was
    /// read, so re-exporting the gap to the archive folder alone would leave the other
    /// sinks permanently short those records.
    func reExportQueueGap(_ gap: GapRecord) async throws -> RunOutcome.Kind {
        let plannedIDs = plannedDestinations(trigger: .manual)
        let root = try HarnessExport.applicationSupportRoot()
        var folderAccess: SecurityScopedAccess?
        if plannedIDs.contains("local-file") {
            folderAccess = try localExportFolder(root: root)
        }
        defer { withExtendedLifetime(folderAccess) {} }
        let scratch = try HarnessExport.exportProtectedPayloadDirectory(named: "scratch", under: root)
        let store = try stateStore(root)
        let context = TemporalContext.utcHost
        let now = Date().ISO8601Format()
        let exporterID = try HarnessExport.installationID()
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
            ledgerHeadSeal: HarnessExport.ledgerHeadSeal(),
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

    // MARK: Demo and single-destination runs

    func runDemoDataset(typedDestinationName: String) async throws -> [String] {
        try DemoExportGate.confirmSending(to: "local-file", typed: typedDestinationName)
        let root = try HarnessExport.applicationSupportRoot()
        let sqliteURL = root.appendingPathComponent("demo-state.sqlite")
        let folderAccess = try localExportFolder(root: root)
        defer { withExtendedLifetime(folderAccess) {} }
        let dest = folderAccess.url
        let scratch = try HarnessExport.exportProtectedPayloadDirectory(named: "demo-scratch", under: root)
        let store = try StateStoreHost.store(path: sqliteURL.path)
        let (verified, events) = try HarnessExport.exportVerifiedLocalFile(root: root, destinationDirectory: dest)
        try await HarnessExport.exportEmitTrustNotices(events)
        let context = TemporalContext.utcHost
        let now = Date().ISO8601Format()
        let exporterId = try HarnessExport.installationID()
        var envelope = WireEnvelope(
            exporterId: exporterId,
            seq: 1,
            emittedAt: now,
            observedAt: now,
            demo: true
        )
        envelope.reason = "manual"
        let source = DemoSampleSource(seed: 1, samplesPerMetric: 4)
        let characteristics = DemoCharacteristicSource()
        var lines: [String] = ["DEMO MODE — synthetic data, not HealthKit"]
        for declaration in MetricCatalog.selectable {
            let run = ExportRun(
                source: source,
                destination: verified,
                store: store,
                metric: declaration.id,
                scratchDirectory: scratch,
                destinationName: "local-file",
                envelope: envelope,
                temporal: context,
                characteristics: characteristics,
                trigger: .manual,
                freshnessCadenceSeconds: freshnessCadenceSeconds(),
                deferForLowPower: isLowPowerDeferred()
            )
            let outcome = try await run.run()
            lines.append("\(declaration.id.rawValue): \(outcome.kind.rawValue) (demo)")
        }
        lines.append("Files: \(dest.path)")
        return lines
    }

    func runCompanion(
        session: PairingSession,
        onTestProgress: DestinationTestProgress? = nil,
        onProgress: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> [String] {
        defer { synchronizeDestinationExportRole("companion") }
        let scope = try await destinationScope("companion")
        try ExportScopeGate.requireConfigured(scope)
        let root = try HarnessExport.applicationSupportRoot()
        let sqliteURL = root.appendingPathComponent("state.sqlite")
        let scratch = try HarnessExport.exportProtectedPayloadDirectory(named: "scratch", under: root)
        let store = try StateStoreHost.store(path: sqliteURL.path)
        let (verified, emission) = try await HarnessExport.exportVerifiedCompanionDestination(
            session: session,
            root: root,
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
        let ledgerSeal = HarnessExport.ledgerHeadSeal()
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
            try HarnessExport.setCompanionTraceparent(false)
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
        let root = try HarnessExport.applicationSupportRoot()
        let verified = try await HarnessExport.exportVerifiedMQTTDestination(root: root)
        let store = try stateStore(root)
        let scratch = try HarnessExport.exportProtectedPayloadDirectory(named: "scratch", under: root)
        let context = TemporalContext.utcHost
        let now = Date().ISO8601Format()
        let exporterID = try HarnessExport.installationID()
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
        let ledgerSeal = HarnessExport.ledgerHeadSeal()
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
        let root = try HarnessExport.applicationSupportRoot()
        // The transport inside holds a background-task assertion per request (#27).
        let (verified, emission) = try await HarnessExport.exportVerifiedHTTPSDestination(
            destinationID: destinationID,
            root: root
        )
        let store = try stateStore(root)
        let scratch = try HarnessExport.exportProtectedPayloadDirectory(named: "scratch", under: root)
        let context = TemporalContext.utcHost
        let now = Date().ISO8601Format()
        let exporterID = try HarnessExport.installationID()
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
        let ledgerSeal = HarnessExport.ledgerHeadSeal()
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
            try HarnessExport.setHTTPSTraceparent(false, destinationID: destinationID)
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

    // MARK: Queue expiry, recovery, stops and holds

    func stopExportingHeartRate() async throws {
        let store = try stateStore(try HarnessExport.applicationSupportRoot())
        // A stop drops the queued payload for every sink that was owed it, so the
        // ledger entry names them all rather than whichever one came first.
        let owed = healthDestinationIDs.filter { destinations.isEnabled($0) }
        try await store.purgeType(
            metric: MetricCatalog.heartRate.id,
            reason: "explicit_stop",
            destination: ExportPlan.owedDestinationLabel(owed),
            atEpoch: Date().timeIntervalSince1970
        )
    }

    func expireQueuesAndNotify() async throws -> QueueExpiryResult {
        let root = try HarnessExport.applicationSupportRoot()
        let store = try stateStore(root)
        let now = Date().timeIntervalSince1970
        let result = try await store.expirePending(
            nowEpoch: now,
            destination: "configured destinations"
        )
        guard result.expiredBatches > 0 else { return result }
        let entries = try await store.transact { try $0.loadLedger() }
        try await LedgerHeadSealRecordFile.update(
            entries: entries,
            seal: HarnessExport.ledgerHeadSeal(),
            sealedAtEpoch: now,
            url: root.appendingPathComponent("ledger-head-seal.json")
        )
        _ = try await LocalUserNotifier().notify(
            UserNotice(kind: .queueExpired, destination: "Configured destinations")
        )
        return result
    }

    /// UX-26: seal leftover open runs after process death, then tell the person.
    func recoverInterruptedExports() async throws -> String? {
        let store = try stateStore(try HarnessExport.applicationSupportRoot())
        let now = Date().timeIntervalSince1970
        let sealed = try await InterruptedRunRecovery.seal(store: store, nowEpoch: now)
        guard let first = sealed.min(by: { $0.startedAtEpoch < $1.startedAtEpoch }) else {
            return nil
        }
        let notice = UserNotice(
            kind: .exportInterrupted,
            destinationID: first.destinationID,
            destination: outcomes.label(first.destinationID),
            errorClass: ErrorClass.cancelledBySystem.rawValue,
            startedAtEpoch: first.startedAtEpoch
        )
        _ = try await LocalUserNotifier().notify(notice)
        try outcomes.markInterrupted(sealed.map(\.destinationID), atEpoch: now)
        reloadStatusWidget()
        return NoticeCopy.render(notice).body
    }

    func anchorHolds() async throws -> [AnchorHold] {
        let store = try stateStore(try HarnessExport.applicationSupportRoot())
        return try await store.transact { try $0.loadAnchorHolds() }
    }

    /// QA-17: the user chose to send the history again. Recording the decision is what
    /// releases the hold; the run reads it rather than inferring intent from a retry.
    func authoriseAnchorReexport(metric: MetricID) async throws {
        let store = try stateStore(try HarnessExport.applicationSupportRoot())
        try await store.transact { tx in
            guard var hold = try tx.loadAnchorHold(metric: metric) else { return }
            hold.decision = .reexportAuthorized
            try tx.upsertAnchorHold(hold)
        }
    }

    /// QA-17's other answer: stop this type rather than pay to send its history again.
    func stopExportingHeldType(metric: MetricID) async throws {
        let store = try stateStore(try HarnessExport.applicationSupportRoot())
        try await store.transact { tx in
            let generation = try tx.loadTypeStatus(metric: metric)?.generation ?? 1
            try tx.upsertTypeStatus(
                TypeStatus(
                    metric: metric,
                    disabled: true,
                    reason: "anchor_invalidated_user_stop",
                    generation: generation
                )
            )
            try tx.clearAnchorHold(metric: metric)
        }
    }

    // MARK: Wakes and wipe

    /// ADR-R8: a system-scheduled wake never migrates the store. It opens under a policy
    /// that forbids migration, and if the on-disk schema is not this build's it journals
    /// `migrationPending` and returns `true` so the caller finishes the wake without
    /// exporting. Otherwise a multi-second migration runs inside a thirty-second wake and
    /// is retried on every wake: a permanent outage that reads as a scheduling problem.
    ///
    /// Checked at the wake boundary rather than inside each store open, because the
    /// decision belongs to the wake — the same migration on a foreground launch is fine.
    func deferWakeIfMigrationPending(trigger: RunTrigger) -> Bool {
        guard let root = try? HarnessExport.applicationSupportRoot() else { return false }
        let path = root.appendingPathComponent("state.sqlite").path
        do {
            let probe = try StateStoreHost.store(
                path: path,
                policy: SQLiteOpenPolicy(allowsSchemaMigration: false)
            )
            withExtendedLifetime(probe) {}
            return false
        } catch StorageError.migrationPending(let onDisk, let expected) {
            try? SQLiteStateStore.journalMigrationPending(
                path: path,
                runID: UUID().uuidString,
                onDisk: onDisk,
                expected: expected
            )
            return true
        } catch {
            // Any other open failure is the export path's problem to report, not ours.
            return false
        }
    }

    func wipeEverything() async throws {
        let root = try HarnessExport.applicationSupportRoot()
        let store = try stateStore(root)
        try await DestructiveWipe.perform(
            store: store,
            secretStores: [
                KeychainSecretStore(service: IdentifierRoot.qualified("ios.psk")),
                KeychainSecretStore(service: IdentifierRoot.qualified("ios.https")),
                KeychainSecretStore(service: IdentifierRoot.qualified("ios.home-assistant")),
                KeychainSecretStore(service: IdentifierRoot.qualified("mqtt")),
            ],
            ledgerSeal: HarnessExport.exportResettableLedgerHeadSeal(),
            ledgerSealURL: root.appendingPathComponent("ledger-head-seal.json"),
            atEpoch: Date().timeIntervalSince1970
        )
        try await HarnessExport.vault().forget()
        EgressAttemptLog.wipePersistent()
        StateStoreHost.evict(path: root.appendingPathComponent("demo-state.sqlite").path)
        for name in ExportWipe.applicationSupportArtifacts {
            try removeIfPresent(root.appendingPathComponent(name))
        }
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        if let directory = StatusSnapshotLocation.directory() {
            try removeIfPresent(directory)
        }
        reloadStatusWidget()
    }

    private func removeIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

enum AppExport {
    private static let settings = PreferencesExportSettings()

    static let service = ExportService(
        tuning: ExportTuning(settings: settings, conditions: SystemExportConditions()),
        scheduledReconcile: ScheduledReconcileGate(settings: settings),
        outcomes: ExportOutcomeRecorder(snapshots: SharedContainerStatusStore(), now: { Date() }),
        status: AppStatus.status,
        destinations: AppDestinations.repository
    )
}
