// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CompanionWire
import CoreDomain
import CoreTemporal
import CorrectnessEngine
import DestinationTrust
import DiagnosticBundle
import EnginePorts
import FileWriteKit
import Foundation
import HealthKitSource
import MetricCatalog
import NetEgress
#if !OHE_OBS25_SIZE_BASELINE
import OTLPExport
#endif
import RunJournal
import SinkCompanion
import SinkHTTP
import SinkLocalFile
import SinkMQTT
import StorageSQLite
import UIKit
import Watchdog
import WidgetKit
import WireFormat

private struct CompanionVerificationRecord: Codable {
    var serviceName: String
    var macInstallationID: String
    var report: DestinationTestReport
    var propagateTraceparent: Bool?
}

private struct HTTPSVerificationRecord: Codable {
    var urlString: String
    var allowedHosts: [String]
    var allowInsecureHTTP: Bool
    var report: DestinationTestReport
    var leafSPKISha256: String?
    var issuerSPKISha256: String?
    var firstSeen: String
    var hasBearer: Bool
    var propagateTraceparent: Bool?
    var importedLocalIdentifier: String?
}

#if !OHE_OBS25_SIZE_BASELINE
private struct OTLPDestinationRecord: Codable {
    var urlString: String
    var allowedHosts: [String]
    var allowInsecureHTTP: Bool
    var previewDigest: String
}
#endif

private struct PendingHTTPS {
    var probe: HTTPSDestinationProbe
    var host: String
    var allowedHosts: [String]
    var allowInsecureHTTP: Bool
    var bearer: String?
    var firstSeen: String
    var importedLocalIdentifier: String?
}

private struct PendingMQTT {
    var probe: MQTTDestinationProbe
    var host: String
    var allowedHosts: [String]
    var allowInsecure: Bool
    var clientID: String
    var topic: String
    var qos: UInt8
    var clientPKCS12: Data?
    var clientPKCS12Password: String?
    var username: String?
    var password: String?
    var firstSeen: String
    var importedLocalIdentifier: String?
}

@MainActor
private final class PendingDestination {
    static let shared = PendingDestination()
    var https: PendingHTTPS?
    var mqtt: PendingMQTT?

    func setHTTPS(_ value: PendingHTTPS?) {
        https = value
    }

    func takeHTTPS() -> PendingHTTPS? {
        let value = https
        https = nil
        return value
    }

    func setMQTT(_ value: PendingMQTT?) {
        mqtt = value
    }

    func takeMQTT() -> PendingMQTT? {
        let value = mqtt
        mqtt = nil
        return value
    }
}

private struct MQTTVerificationRecord: Codable {
    var urlString: String
    var allowedHosts: [String]
    var allowInsecure: Bool
    var clientID: String
    var topic: String
    var qos: UInt8?
    var report: DestinationTestReport
    var hasClientPKCS12: Bool?
    var clientPKCS12Password: String?
    var username: String?
    var hasPassword: Bool?
    var leafSPKISha256: String?
    var issuerSPKISha256: String?
    var firstSeen: String?
    var importedLocalIdentifier: String?
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
    var destination: VerifiedDestination
    var store: any StateStore
    var scratchDirectory: URL
    var exporterID: String
    var temporal: TemporalContext
    var ledgerHeadSeal: any LedgerHeadSeal
    var ledgerSealURL: URL

    func process(
        metric: MetricID,
        days: [String],
        mode: BackfillMode
    ) async throws -> BackfillChunkResult {
        let counted = CountingBackfillObservations(base: observations)
        let now = Date().ISO8601Format()
        let outcome = try await ReconcileSweep(
            observations: counted,
            destination: destination,
            store: store,
            metric: metric,
            scratchDirectory: scratchDirectory,
            destinationName: "local-file",
            envelope: WireEnvelope(
                exporterId: exporterID,
                seq: 1,
                emittedAt: now,
                observedAt: now
            ),
            temporal: temporal,
            statistics: statistics,
            trigger: .manual,
            snapshotURL: StatusSnapshotLocation.url(destinationID: "local-file"),
            externalStatusURL: scratchDirectory
                .deletingLastPathComponent()
                .appendingPathComponent("exports/status.json"),
            ledgerHeadSeal: ledgerHeadSeal,
            ledgerSealURL: ledgerSealURL,
            freshnessCadenceSeconds: freshnessCadenceSeconds(),
            deferForLowPower: isLowPowerDeferred()
        ).runBackfill(days: days, mode: mode)
        return BackfillChunkResult(
            samplesRead: await counted.count(),
            batchesEnqueued: outcome.kind == .successNothingDue ? 0 : 1
        )
    }
}

private actor ObserverExportGate {
    static let shared = ObserverExportGate()
    private var pending: Set<MetricID> = []
    private var running = false

    func enqueue(_ metric: MetricID) async {
        pending.insert(metric)
        guard !running else { return }
        running = true
        defer { running = false }
        while let next = pending.first {
            pending.remove(next)
            _ = try? await HarnessExport.runOnePageEachMetric(
                metrics: [next],
                trigger: .observerQuery
            )
        }
    }
}

enum HarnessExport {
    static let healthDestinationIDs = ["local-file", "https", "mqtt", "companion"]

    /// UX-29: the 413 shorten-window action writes `ohe.exportWindowHours`; HealthKit
    /// pages follow that owned setting so the next batch is smaller.
    static func samplePageLimit() -> Int {
        let stored = UserDefaults.standard.object(forKey: "ohe.exportWindowHours") as? Int
        return SamplePaging.pageLimit(
            windowHours: stored ?? 24,
            thermalHalved: isThermalDeferred()
        )
    }

    static func gzipLevel() -> Int32 {
        isThermalDeferred() ? Gzip.storedLevel : Gzip.speedLevel
    }

    static func withThermalCompression<T>(
        _ body: () async throws -> T
    ) async rethrows -> T {
        try await Gzip.$level.withValue(gzipLevel(), operation: body)
    }

    static func freshnessCadenceSeconds() -> TimeInterval {
        let stored = UserDefaults.standard.object(forKey: "ohe.freshnessIntervalMinutes") as? Int
        return TimeInterval(max(1, stored ?? 15) * 60)
    }

    static func isLowPowerDeferred() -> Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    static func isThermalDeferred() -> Bool {
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical:
            return true
        default:
            return false
        }
    }

    static func allowsMeteredNetwork(destinationID: String) -> Bool {
        UserDefaults.standard.bool(forKey: "ohe.\(destinationID).allowsMeteredNetwork")
    }

    static func networkPathConditions() -> NetworkPathConditions {
        NetworkPathMonitorCache.conditions()
    }

    static func attachNetworkActivityLedger() {
        guard let root = try? applicationSupportRoot() else { return }
        EgressAttemptLog.attachPersistent(
            EgressAttemptLog.PersistentStore(
                url: root.appendingPathComponent("network-activity.json"),
                nowEpoch: { Date().timeIntervalSince1970 }
            )
        )
    }

    static func networkActivityLines() -> [String] {
        attachNetworkActivityLedger()
        let rows = EgressAttemptLog.persistentSnapshot()
        var lines = [
            EgressAttemptLog.selfReportedCaveat(sourceCommit: BuildIdentity.current.sourceCommit)
        ]
        if rows.isEmpty {
            lines.append(EgressAttemptLog.emptyCopy)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            for row in rows {
                let first = formatter.string(from: Date(timeIntervalSince1970: row.firstSeenEpoch))
                let last = formatter.string(from: Date(timeIntervalSince1970: row.lastSeenEpoch))
                lines.append(
                    "\(row.host) · \(row.count) · \(row.bytes) bytes · \(first) → \(last)"
                )
            }
        }
        return lines
    }

    static func buildProvenanceLines() -> [String] {
        let identity = BuildIdentity.current
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.1.0"
        var lines = [BuildIdentity.versionLine(version: version, commit: identity.sourceCommit)]
        if let link = BuildIdentity.sourceLink(commit: identity.sourceCommit) {
            lines.append(link)
        }
        return lines
    }

    static func destinationScope(_ destinationID: String) async throws -> DestinationExportScope {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
        return try await store.transact { tx in
            try tx.loadDestinationScope(destinationID: destinationID)
                ?? DestinationExportScope(destinationID: destinationID)
        }
    }

    static func destinationScopes() async throws -> [DestinationExportScope] {
        var scopes: [DestinationExportScope] = []
        for destinationID in healthDestinationIDs {
            scopes.append(try await destinationScope(destinationID))
        }
        return scopes
    }

    static func selectedMetrics() async throws -> [MetricID] {
        let union = try await destinationScopes().reduce(into: Set<MetricID>()) {
            guard isDestinationEnabled($1.destinationID) else { return }
            $0.formUnion($1.metrics)
        }
        return union.sorted { $0.rawValue < $1.rawValue }
    }

    static func isDestinationEnabled(_ destinationID: String) -> Bool {
        guard let root = try? applicationSupportRoot() else { return false }
        switch destinationID {
        case "local-file":
            return isLocalFileEnabled()
        case "https":
            guard let data = try? Data(
                contentsOf: root.appendingPathComponent("https-destination.json")
            ), let record = try? JSONDecoder().decode(HTTPSVerificationRecord.self, from: data)
            else { return false }
            return record.report.allowsEnablement
        case "mqtt":
            guard let data = try? Data(
                contentsOf: root.appendingPathComponent("mqtt-destination.json")
            ), let record = try? JSONDecoder().decode(MQTTVerificationRecord.self, from: data)
            else { return false }
            return record.report.allowsEnablement
        case "companion":
            guard let data = try? Data(contentsOf: companionTestReportURL(root: root)),
                  let record = try? JSONDecoder().decode(CompanionVerificationRecord.self, from: data)
            else { return false }
            return record.report.allowsEnablement
        default:
            return false
        }
    }

    static func hasDestinationConfiguration(_ destinationID: String) -> Bool {
        guard let root = try? applicationSupportRoot() else { return false }
        let filename: String
        switch destinationID {
        case "https":
            filename = "https-destination.json"
        case "mqtt":
            filename = "mqtt-destination.json"
        default:
            return false
        }
        return FileManager.default.fileExists(
            atPath: root.appendingPathComponent(filename).path
        )
    }

    private static func requestScopeAuthorizationIfConfigured(
        _ destinationID: String
    ) async throws {
        let scope = try await destinationScope(destinationID)
        guard scope.isConfigured else { return }
        try await HealthKitAuthorization.requestReadAccess(
            metrics: scope.metrics.sorted { $0.rawValue < $1.rawValue }
        )
    }

    static func saveDestinationScope(_ scope: DestinationExportScope) async throws {
        let allowed = Set(MetricCatalog.selectable.map(\.id))
        let sanitized = try DestinationExportScope(
            destinationID: scope.destinationID,
            metrics: scope.metrics.intersection(allowed),
            startInclusive: scope.startInclusive,
            endExclusive: scope.endExclusive
        )
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
        try await store.transact { try $0.upsertDestinationScope(sanitized) }
    }

    static func applyDestinationScope(
        _ scope: DestinationExportScope,
        previousMetrics: Set<MetricID>
    ) async throws {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        try await saveDestinationScope(scope)
        for metric in scope.metrics.subtracting(previousMetrics) {
            try await store.reenableType(metric: metric, reason: "user_selected")
        }
    }

    @MainActor
    static func fetchSecurityAdvisory(enabled: Bool) async throws -> AdvisoryPresentation {
        let defaults = UserDefaults.standard
        let state = AdvisoryState(
            enabled: enabled,
            lastAttemptEpoch: defaults.object(
                forKey: "ohe.advisoryLastAttemptEpoch"
            ) as? TimeInterval,
            lastVerifiedEpoch: defaults.object(
                forKey: "ohe.advisoryLastVerifiedEpoch"
            ) as? TimeInterval,
            lastSeenSeq: defaults.integer(forKey: "ohe.advisoryLastSeenSeq")
        )
        let root = try applicationSupportRoot()
        let emptyBody = root.appendingPathComponent("advisory-request-body")
        if !FileManager.default.fileExists(atPath: emptyBody.path) {
            try Data().write(to: emptyBody, options: .atomic)
        }
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        let result = try await AdvisoryClient.fetch(
            transport: SystemHTTPTransport.make(),
            store: store,
            state: state,
            now: Date(),
            marketingVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "0.0.0",
            foregroundVisible: true,
            emptyBody: emptyBody
        )
        defaults.set(
            result.state.lastAttemptEpoch,
            forKey: "ohe.advisoryLastAttemptEpoch"
        )
        defaults.set(
            result.state.lastVerifiedEpoch,
            forKey: "ohe.advisoryLastVerifiedEpoch"
        )
        defaults.set(
            result.state.lastSeenSeq,
            forKey: "ohe.advisoryLastSeenSeq"
        )
        return result.presentation
    }

    static func installationID() throws -> String {
        let root = try applicationSupportRoot()
        let exporterURL = root.appendingPathComponent("exporter-id")
        if let existing = try? String(contentsOf: exporterURL, encoding: .utf8), !existing.isEmpty {
            return existing.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let id = UUID().uuidString.lowercased()
        try id.write(to: exporterURL, atomically: true, encoding: .utf8)
        return id
    }

    static func runOnePageEachMetric(
        metrics: [MetricID]? = nil,
        trigger: RunTrigger = .manual,
        onProgress: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> [String] {
        let scope = try await destinationScope("local-file")
        try ExportScopeGate.requireConfigured(scope)
        let metrics = metrics ?? scope.metrics.sorted { $0.rawValue < $1.rawValue }
        for metric in metrics {
            try ExportScopeGate.require(metric: metric, scope: scope)
        }
        let root = try applicationSupportRoot()
        let sqliteURL = root.appendingPathComponent("state.sqlite")
        let dest = try protectedPayloadDirectory(named: "exports", under: root)
        let scratch = try protectedPayloadDirectory(named: "scratch", under: root)

        let store = try SQLiteStateStore(path: sqliteURL.path)
        let gapIDsBefore = try await store.transact {
            Set(try $0.loadGaps().map(\.batchID))
        }
        let (verified, events) = try verifiedLocalFile(root: root, destinationDirectory: dest)
        try await emitTrustNotices(events)
        let context = TemporalContext.utcHost
        let source = HealthKitAnchoredSource(
            context: context,
            limit: samplePageLimit(),
            window: HealthKitQueryWindow(scope: scope)
        )
        let observations = HealthKitDayObservationSource(context: context, limit: samplePageLimit())
        let statistics = HealthKitStatisticsSource(context: context)
        let now = Date().ISO8601Format()
        let exporterId = try installationID()
        let ledgerSeal = ledgerHeadSeal()
        let ledgerSealURL = root.appendingPathComponent("ledger-head-seal.json")

        var lines: [String] = []
        var kinds: [RunOutcome.Kind] = []
        for (index, metric) in metrics.enumerated() {
            await onProgress?(index + 1, metrics.count)
            let snapshotURL = StatusSnapshotLocation.url(destinationID: "local-file")
            let run = ExportRun(
                source: source,
                destination: verified,
                store: store,
                metric: metric,
                scratchDirectory: scratch,
                destinationName: "local-file",
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
                snapshotURL: snapshotURL,
                externalStatusURL: dest.appendingPathComponent("status.json"),
                ledgerHeadSeal: ledgerSeal,
                ledgerSealURL: ledgerSealURL,
                scope: scope,
                freshnessCadenceSeconds: freshnessCadenceSeconds(),
            deferForLowPower: isLowPowerDeferred()
            )
            let outcome = try await run.run()
            kinds.append(outcome.kind)
            await notifyIfFailed(
                outcome,
                destinationID: "local-file",
                destinationLabel: "Archive folder"
            )
            WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
            lines.append("\(metric.rawValue): \(outcome.kind.rawValue)")
            if (outcome.kind == .success || outcome.kind == .successNothingDue),
               let snapshotURL {
                await rescheduleOverdueNotification(snapshotURL: snapshotURL)
            }

            lines.append(
                try await trailingReconcileAfterDelta(
                    observations: observations,
                    destination: verified,
                    store: store,
                    metric: metric,
                    scratchDirectory: scratch,
                    destinationID: "local-file",
                    destinationLabel: "Archive folder",
                    envelope: WireEnvelope(
                        exporterId: exporterId,
                        seq: 1,
                        emittedAt: now,
                        observedAt: now
                    ),
                    temporal: context,
                    statistics: statistics,
                    trigger: trigger,
                    snapshotURL: snapshotURL,
                    externalStatusURL: dest.appendingPathComponent("status.json"),
                    ledgerHeadSeal: ledgerSeal,
                    ledgerSealURL: ledgerSealURL,
                    scope: scope
                )
            )
        }
        let newQueueGap = try await store.transact {
            try $0.loadGaps().contains {
                !gapIDsBefore.contains($0.batchID)
                    && $0.rangeDescription.hasPrefix("queue_eviction:")
            }
        }
        if newQueueGap {
            _ = try await LocalUserNotifier().notify(
                UserNotice(kind: .queueEvicted, destination: "Configured destinations")
            )
        }
        if trigger == .appForeground || trigger == .launch {
            lines.append(contentsOf: try await maybeScheduledFullReconcile(store: store))
        }
        try await applyQueueRedIfNeeded(
            store: store,
            root: root,
            destinationLabel: "Archive folder"
        )
        let combined = CombinedExportSummary.kind(kinds)
        if let snapshotURL = StatusSnapshotLocation.url(destinationID: "local-file"),
           var snapshot = try? DestinationSnapshotFile.read(from: snapshotURL)
        {
            snapshot.applyLastOutcome(combined.rawValue)
            snapshot.writtenAtEpoch = Date().timeIntervalSince1970
            try DestinationSnapshotFile.write(snapshot, to: snapshotURL)
            WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
        }
        lines.insert(CombinedExportSummary.copy(kinds), at: 0)
        lines.append("Files: \(dest.path)")
        return lines
    }

    private static let lastScheduledFullReconcileEpochKey = "ohe.lastScheduledFullReconcileEpoch"

    /// O-9: a low-priority full reconcile on a daily cadence, skipped when the
    /// queue is already in I6 Amber so live deltas are not evicted.
    private static func maybeScheduledFullReconcile(store: any StateStore) async throws -> [String] {
        let queued = try await store.transact { try $0.queuedBytes() }
        if !CatchUpAdmission.allows(queuedBytes: queued) {
            return ["scheduled full reconcile skipped: catch_up_parked"]
        }
        let defaults = UserDefaults.standard
        let stored = defaults.double(forKey: lastScheduledFullReconcileEpochKey)
        let lastEpoch = stored > 0 ? stored : nil
        let nowEpoch = Date().timeIntervalSince1970
        guard ScheduledReconcile.due(lastEpoch: lastEpoch, nowEpoch: nowEpoch) else {
            return []
        }
        let lines = try await runFullReconcile()
        defaults.set(nowEpoch, forKey: lastScheduledFullReconcileEpochKey)
        return ["scheduled full reconcile"] + lines
    }

    /// I6 Red: drop derived attempt bodies, truncate the WAL, and raise the
    /// approaching-loss notice. Live pending batches stay queued.
    private static func applyQueueRedIfNeeded(
        store: SQLiteStateStore,
        root: URL,
        destinationLabel: String
    ) async throws {
        let queued = try await store.transact { try $0.queuedBytes() }
        guard QueueRed.occupancy(queuedBytes: queued) >= .red else { return }
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
    /// Delta ExportRun does not itself reconcile; leaving this only on the archive
    /// folder would skip repair for HTTPS, MQTT, and the Mac companion.
    private static func trailingReconcileAfterDelta(
        observations: any DayObservationSource,
        destination: VerifiedDestination,
        store: any StateStore,
        metric: MetricID,
        scratchDirectory: URL,
        destinationID: String,
        destinationLabel: String,
        envelope: WireEnvelope,
        temporal: TemporalContext,
        statistics: (any StatisticsSource)?,
        trigger: RunTrigger,
        snapshotURL: URL?,
        externalStatusURL: URL? = nil,
        ledgerHeadSeal: (any LedgerHeadSeal)?,
        ledgerSealURL: URL?,
        scope: DestinationExportScope?
    ) async throws -> String {
        let reconciled = try await ReconcileSweep(
            observations: observations,
            destination: destination,
            store: store,
            metric: metric,
            scratchDirectory: scratchDirectory,
            destinationName: destinationID,
            envelope: envelope,
            temporal: temporal,
            statistics: statistics,
            trigger: trigger,
            snapshotURL: snapshotURL,
            externalStatusURL: externalStatusURL,
            ledgerHeadSeal: ledgerHeadSeal,
            ledgerSealURL: ledgerSealURL,
            scope: scope,
            freshnessCadenceSeconds: freshnessCadenceSeconds(),
            deferForLowPower: isLowPowerDeferred()
        ).run(throughDay: String(envelope.emittedAt.prefix(10)))
        await notifyIfFailed(
            reconciled,
            destinationID: destinationID,
            destinationLabel: destinationLabel
        )
        if (reconciled.kind == .success || reconciled.kind == .successNothingDue),
           let snapshotURL {
            await rescheduleOverdueNotification(snapshotURL: snapshotURL)
        }
        return "\(metric.rawValue) reconcile: \(reconciled.kind.rawValue)"
    }

    private static func rescheduleOverdueNotification(snapshotURL: URL) async {
        guard let snapshot = try? DestinationSnapshotFile.read(from: snapshotURL) else {
            return
        }
        _ = try? await LocalUserNotifier().rescheduleExportOverdue(snapshot: snapshot)
    }

    private static func notifyIfFailed(
        _ outcome: RunOutcome,
        destinationID: String,
        destinationLabel: String
    ) async {
        guard outcome.kind == .failed else { return }
        await notifyDestinationFailure(
            destinationID: destinationID,
            destinationLabel: destinationLabel
        )
    }

    static func notifyDestinationFailure(
        destinationID: String,
        destinationLabel: String
    ) async {
        let errorClass = StatusSnapshotLocation.readAll().first {
            $0.destinationID == destinationID
        }?.errorClass
        _ = try? await LocalUserNotifier().notify(
            UserNotice(
                kind: .exportFailed,
                destinationID: destinationID,
                destination: destinationLabel,
                errorClass: errorClass
            )
        )
    }

    static func runFullReconcile(
        metrics: [MetricID]? = nil,
        onProgress: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> [String] {
        let scope = try await destinationScope("local-file")
        try ExportScopeGate.requireConfigured(scope)
        let metrics = metrics ?? scope.metrics.sorted { $0.rawValue < $1.rawValue }
        for metric in metrics {
            try ExportScopeGate.require(metric: metric, scope: scope)
        }
        let root = try applicationSupportRoot()
        let dest = try protectedPayloadDirectory(named: "exports", under: root)
        let scratch = try protectedPayloadDirectory(named: "scratch", under: root)
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        let (verified, events) = try verifiedLocalFile(
            root: root,
            destinationDirectory: dest
        )
        try await emitTrustNotices(events)
        let context = TemporalContext.utcHost
        let observations = HealthKitDayObservationSource(
            context: context,
            limit: samplePageLimit()
        )
        let statistics = HealthKitStatisticsSource(context: context)
        let now = Date().ISO8601Format()
        let exporterID = try installationID()
        let seal = ledgerHeadSeal()
        var lines: [String] = []
        for (index, metric) in metrics.enumerated() {
            await onProgress?(index + 1, metrics.count)
            let outcome = try await ReconcileSweep(
                observations: observations,
                destination: verified,
                store: store,
                metric: metric,
                scratchDirectory: scratch,
                destinationName: "local-file",
                envelope: WireEnvelope(
                    exporterId: exporterID,
                    seq: 1,
                    emittedAt: now,
                    observedAt: now
                ),
                temporal: context,
                statistics: statistics,
                trigger: .manual,
                snapshotURL: StatusSnapshotLocation.url(destinationID: "local-file"),
                externalStatusURL: dest.appendingPathComponent("status.json"),
                ledgerHeadSeal: seal,
                ledgerSealURL: root.appendingPathComponent("ledger-head-seal.json"),
                scope: scope,
                freshnessCadenceSeconds: freshnessCadenceSeconds(),
            deferForLowPower: isLowPowerDeferred()
            ).runFullHistory(throughDay: String(now.prefix(10)))
            await notifyIfFailed(
                outcome,
                destinationID: "local-file",
                destinationLabel: "Archive folder"
            )
            lines.append("\(metric.rawValue) full reconcile: \(outcome.kind.rawValue)")
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
        lines.append("Files: \(dest.path)")
        return lines
    }

    static func runBackfill(
        mode: BackfillMode,
        onProgress: (@Sendable (String) async -> Void)? = nil
    ) async throws -> [String] {
        let root = try applicationSupportRoot()
        let destinationDirectory = try protectedPayloadDirectory(named: "exports", under: root)
        let scratch = try protectedPayloadDirectory(named: "backfill-scratch", under: root)
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        let (destination, events) = try verifiedLocalFile(
            root: root,
            destinationDirectory: destinationDirectory
        )
        try await emitTrustNotices(events)
        let context = TemporalContext.utcHost
        let observations = HealthKitDayObservationSource(context: context, limit: samplePageLimit())
        let scope = try await destinationScope("local-file")
        try ExportScopeGate.requireConfigured(scope)
        let scopeStartDay = String(
            (scope.startInclusive ?? .distantFuture).ISO8601Format().prefix(10)
        )
        let scopeEndDay = scope.endExclusive.map {
            String($0.addingTimeInterval(-1).ISO8601Format().prefix(10))
        }
        var metrics: [MetricID] = []
        var firstDay: String?
        var lastDay: String?
        for metric in scope.metrics.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let range = try? await observations.availableDayRange(metric: metric) else {
                continue
            }
            let lower = max(range.lowerBound, scopeStartDay)
            let upper = min(range.upperBound, scopeEndDay ?? range.upperBound)
            guard lower <= upper else { continue }
            metrics.append(metric)
            firstDay = min(firstDay ?? lower, lower)
            lastDay = max(lastDay ?? upper, upper)
        }
        guard let firstDay, let lastDay, !metrics.isEmpty else {
            return ["No supported Health history is available for backfill."]
        }

        let checkpointURL = root.appendingPathComponent(
            mode == .raw ? "backfill-raw.json" : "backfill-aggregate.json"
        )
        let processor = HealthBackfillProcessor(
            observations: observations,
            statistics: HealthKitStatisticsSource(context: context),
            destination: destination,
            store: store,
            scratchDirectory: scratch,
            exporterID: try installationID(),
            temporal: context,
            ledgerHeadSeal: ledgerHeadSeal(),
            ledgerSealURL: root.appendingPathComponent("ledger-head-seal.json")
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
                        windowStartDay: firstDay,
                        windowEndDay: lastDay,
                        mode: mode,
                        metrics: metrics,
                        destinations: ["local-file"]
                    )
                )
            )
        }
        let completed = try await job.run(onProgress: onProgress)
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
        if let parked = completed.progress.pausedReason {
            return [
                "\(mode.rawValue) backfill parked",
                parked,
                "Samples read: \(completed.progress.samplesRead)",
                "Batches enqueued: \(completed.progress.batchesEnqueued)",
                "Checkpoint: \(checkpointURL.path)",
            ]
        }
        let manifest = ArchiveCompletionManifest.make(from: completed)
        let published = destinationDirectory.appendingPathComponent("archive-manifest.json")
        try manifest.write(to: published)
        return [
            "\(mode.rawValue) backfill complete",
            "Samples read: \(completed.progress.samplesRead)",
            "Batches enqueued: \(completed.progress.batchesEnqueued)",
            "Checkpoint: \(checkpointURL.path)",
            "Manifest: \(published.path)",
        ]
    }

    static func queueEvictionGaps() async throws -> [GapRecord] {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        return try await store.transact {
            try $0.loadGaps().filter {
                $0.rangeDescription.hasPrefix("queue_eviction:")
                    && $0.rangeStartDay != nil
                    && $0.rangeEndDay != nil
            }
        }
    }

    static func recordNotificationSuppressionIfNeeded() async throws {
        #if DEBUG
        let forcedDenied = ProcessInfo.processInfo
            .environment["OHE_SEED_NOTIFICATION_AUTHORIZATION"] == "denied"
        #else
        let forcedDenied = false
        #endif
        let systemDenied = await LocalUserNotifier().authorizationDenied()
        let denied = forcedDenied || systemDenied
        let defaults = UserDefaults.standard
        let key = "ohe.notificationsPreviouslyDenied"
        let previouslyDenied = forcedDenied ? false : defaults.bool(forKey: key)
        defer { defaults.set(denied, forKey: key) }
        guard NotificationSuppression.shouldRecord(
            previouslyDenied: previouslyDenied,
            currentlyDenied: denied
        ) else {
            return
        }
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        try await store.transact { tx in
            try tx.appendLedger(
                EgressEntry(
                    destination: "local-notifications",
                    sampleCount: 0,
                    outcomeKind: "security:notifications_denied",
                    detail: "watchdog_escalation_suppressed",
                    wallTimeEpoch: Date().timeIntervalSince1970
                )
            )
        }
        for snapshot in StatusSnapshotLocation.readAll() {
            if let url = StatusSnapshotLocation.url(
                destinationID: snapshot.destinationID
            ) {
                try DestinationSnapshotFile.recordSecurityEvents(
                    1,
                    destinationID: snapshot.destinationID,
                    destinationLabel: snapshot.destinationLabel,
                    writtenAtEpoch: Date().timeIntervalSince1970,
                    at: url
                )
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func reExportQueueGap(_ gap: GapRecord) async throws -> RunOutcome {
        let root = try applicationSupportRoot()
        let dest = try protectedPayloadDirectory(named: "exports", under: root)
        let scratch = try protectedPayloadDirectory(named: "scratch", under: root)
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        let (verified, events) = try verifiedLocalFile(
            root: root,
            destinationDirectory: dest
        )
        try await emitTrustNotices(events)
        let context = TemporalContext.utcHost
        let now = Date().ISO8601Format()
        let outcome = try await ReconcileSweep(
            observations: HealthKitDayObservationSource(
                context: context,
                limit: samplePageLimit()
            ),
            destination: verified,
            store: store,
            metric: gap.metric,
            scratchDirectory: scratch,
            destinationName: "local-file",
            envelope: WireEnvelope(
                exporterId: try installationID(),
                seq: 1,
                emittedAt: now,
                observedAt: now
            ),
            temporal: context,
            statistics: HealthKitStatisticsSource(context: context),
            trigger: .manual,
            snapshotURL: StatusSnapshotLocation.url(destinationID: "local-file"),
            externalStatusURL: dest.appendingPathComponent("status.json"),
            ledgerHeadSeal: ledgerHeadSeal(),
            ledgerSealURL: root.appendingPathComponent("ledger-head-seal.json"),
            freshnessCadenceSeconds: freshnessCadenceSeconds(),
            deferForLowPower: isLowPowerDeferred()
        ).run(gap: gap)
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
        return outcome
    }

    static func runDemoDataset(typedDestinationName: String) async throws -> [String] {
        try DemoExportGate.confirmSending(to: "local-file", typed: typedDestinationName)
        let root = try applicationSupportRoot()
        let sqliteURL = root.appendingPathComponent("demo-state.sqlite")
        let dest = try protectedPayloadDirectory(named: "demo-exports", under: root)
        let scratch = try protectedPayloadDirectory(named: "demo-scratch", under: root)
        let store = try SQLiteStateStore(path: sqliteURL.path)
        let (verified, events) = try verifiedLocalFile(root: root, destinationDirectory: dest)
        try await emitTrustNotices(events)
        let context = TemporalContext.utcHost
        let now = Date().ISO8601Format()
        let exporterId = try installationID()
        var envelope = WireEnvelope(
            exporterId: exporterId,
            seq: 1,
            emittedAt: now,
            observedAt: now,
            demo: true
        )
        envelope.reason = "manual"
        let source = DemoSampleSource(seed: 1, samplesPerMetric: 4)
        var lines: [String] = ["DEMO MODE — synthetic data, not HealthKit"]
        for declaration in MetricCatalog.all {
            let run = ExportRun(
                source: source,
                destination: verified,
                store: store,
                metric: declaration.id,
                scratchDirectory: scratch,
                destinationName: "local-file",
                envelope: envelope,
                temporal: context,
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

    static func runCompanion(
        session: PairingSession,
        onProgress: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> [String] {
        let scope = try await destinationScope("companion")
        try ExportScopeGate.requireConfigured(scope)
        let root = try applicationSupportRoot()
        let sqliteURL = root.appendingPathComponent("state.sqlite")
        let scratch = try protectedPayloadDirectory(named: "scratch", under: root)
        let store = try SQLiteStateStore(path: sqliteURL.path)
        let psk = try CompanionPSK.preSharedKey(from: session.secret)
        let discovered = try await CompanionDiscovery().find(pairedName: session.serviceName, for: .seconds(8))
        let options = NWByteStream.Options(
            requireTLS13: true,
            failFastOnWaiting: true,
            preSharedKey: psk
        )
        let deliveryPipe = ByteStreamCompanionPipe(
            stream: NWByteStream(service: discovered, options: options)
        )
        let emission = TraceparentEmission(enabled: storedCompanionTraceparent())
        let verified: VerifiedDestination
        let verificationURL = companionTestReportURL(root: root)
        if let data = try? Data(contentsOf: verificationURL),
           let saved = try? JSONDecoder().decode(CompanionVerificationRecord.self, from: data),
           saved.serviceName == session.serviceName,
           saved.macInstallationID == session.macInstallationID,
           saved.report.allowsEnablement {
            verified = try CompanionDestinationEnable.resume(
                deliveryPipe: deliveryPipe,
                installationID: session.localInstallationID,
                testReport: saved.report,
                traceparent: emission,
                meteredPolicy: .fromAllowsMetered(allowsMeteredNetwork(destinationID: "companion")),
                pathConditions: networkPathConditions()
            )
        } else {
            let testPipe = ByteStreamCompanionPipe(
                stream: NWByteStream(service: discovered, options: options)
            )
            let completed = try await CompanionDestinationEnable.complete(
                testPipe: testPipe,
                deliveryPipe: deliveryPipe,
                installationID: session.localInstallationID,
                emittedAt: Date().ISO8601Format(),
                traceparent: emission,
                meteredPolicy: .fromAllowsMetered(allowsMeteredNetwork(destinationID: "companion")),
                pathConditions: networkPathConditions()
            )
            verified = completed.destination
            let record = CompanionVerificationRecord(
                serviceName: session.serviceName,
                macInstallationID: session.macInstallationID,
                report: completed.report,
                propagateTraceparent: emission.header(seed: "preview") != nil
            )
            try JSONEncoder().encode(record).write(to: verificationURL, options: .atomic)
            if let snapshotURL = StatusSnapshotLocation.url(destinationID: "companion") {
                try DestinationSnapshotFile.recordSecurityEvents(
                    completed.events.count,
                    destinationID: "companion",
                    destinationLabel: "Mac companion · \(session.serviceName)",
                    writtenAtEpoch: Date().timeIntervalSince1970,
                    at: snapshotURL
                )
            }
            try await emitTrustNotices(completed.events, destination: session.serviceName)
        }
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
        let ledgerSeal = ledgerHeadSeal()
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
                outcome,
                destinationID: "companion",
                destinationLabel: "Mac companion"
            )
            WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
            lines.append("\(metric.rawValue): \(outcome.kind.rawValue)")
            lines.append(
                try await trailingReconcileAfterDelta(
                    observations: observations,
                    destination: verified,
                    store: store,
                    metric: metric,
                    scratchDirectory: scratch,
                    destinationID: "companion",
                    destinationLabel: "Mac companion",
                    envelope: WireEnvelope(
                        exporterId: session.localInstallationID,
                        seq: 1,
                        emittedAt: now,
                        observedAt: now
                    ),
                    temporal: context,
                    statistics: statistics,
                    trigger: .manual,
                    snapshotURL: StatusSnapshotLocation.url(destinationID: "companion"),
                    ledgerHeadSeal: ledgerSeal,
                    ledgerSealURL: ledgerSealURL,
                    scope: scope
                )
            )
        }
        if emission.autoDisabled {
            try setCompanionTraceparent(false)
            lines.append("traceparent auto-disabled after a header-plausible failure")
        }
        lines.append("Companion: \(session.serviceName)")
        try await applyQueueRedIfNeeded(
            store: store,
            root: root,
            destinationLabel: "Mac companion"
        )
        return lines
    }

    private static func applicationSupportRoot() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appendingPathComponent("OpenHealthExporter", isDirectory: true)
        try fm.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        // createDirectory does not update attributes when the directory already
        // exists, so re-apply the SEC-32 floor for upgrades as well as fresh installs.
        try fm.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: root.path
        )
        // SEC-30: everything the engine keeps — state, journal, queued payloads — lives
        // under here, and none of it may reach a backup.
        try FileWriteKit.excludeFromBackup(root)
        return root
    }

    private static func protectedPayloadDirectory(
        named name: String,
        under root: URL
    ) throws -> URL {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        let protection = FileProtectionType.completeUnlessOpen
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: protection]
        )
        // Apply the accepted ADR-0002 Class B split to pre-existing directories too.
        try FileManager.default.setAttributes(
            [.protectionKey: protection],
            ofItemAtPath: directory.path
        )
        return directory
    }

    @MainActor
    static func diagnosticBundle(
        minimumRuns: Int = 30,
        windowHours: Int = 24
    ) throws -> (preview: String, payload: Data) {
        let assembler = BundleAssembler(
            maxRuns: minimumRuns,
            windowSeconds: TimeInterval(windowHours) * 60 * 60
        )
        let root = try applicationSupportRoot()
        let journal = SQLiteDiagnosticReader.read(
            path: root.appendingPathComponent("state.sqlite").path,
            maxRuns: assembler.maxRuns,
            windowSeconds: assembler.windowSeconds
        )
        let payload = try assembler.assemble(
            header: DiagnosticHeader(
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
                osVersion: UIDevice.current.systemVersion,
                deviceModel: UIDevice.current.model,
                localeIdentifier: Locale.current.identifier,
                utcOffsetMinutes: TimeZone.current.secondsFromGMT() / 60,
                generatedAt: Date().ISO8601Format(),
                degraded: journal.degraded,
                sourceCommit: BuildIdentity.current.sourceCommit,
                buildHash: BuildIdentity.current.buildHash
            ),
            events: journal.events
        )
        let text = String(decoding: payload, as: UTF8.self)
        let lines = assembler.previewLines(events: journal.events)
        let preview = lines.isEmpty ? text : lines.joined(separator: "\n") + "\n\n" + text
        return (preview, payload)
    }

    static func destinationStatusLines() -> [String] {
        let snapshots = StatusSnapshotLocation.readAll()
        guard !snapshots.isEmpty else { return [DestinationStatusLine.emptyCopy] }
        let now = Date().timeIntervalSince1970
        return snapshots.map { snapshot in
            DestinationStatusLine.render(snapshot, nowEpoch: now) {
                Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .shortened)
            }
        }
    }

    static func freshnessDisclosureLines() -> [(id: String, text: String)] {
        let snapshots = StatusSnapshotLocation.readAll()
        return FreshnessClass.allCases.flatMap { freshnessClass in
            let measured = snapshots.compactMap { snapshot -> (String, LocalFreshnessEstimate)? in
                snapshot.freshnessEstimates[freshnessClass].map {
                    (snapshot.destinationLabel, $0)
                }
            }
            guard !measured.isEmpty else {
                return [(
                    "freshness-class-\(freshnessClass.rawValue)",
                    FreshnessTarget.classDisclosure(freshnessClass)
                )]
            }
            return measured.map { label, estimate in
                (
                    "freshness-\(freshnessClass.rawValue)-\(label)",
                    "\(label) — \(FreshnessTarget.classDisclosure(freshnessClass, estimate: estimate))"
                )
            }
        }
    }

    static func destinationChangeBannerDetail() -> String? {
        let snapshots = StatusSnapshotLocation.readAll()
        guard DestinationChangeBanner.isVisible(snapshots) else { return nil }
        return DestinationChangeBanner.detail(snapshots)
    }

    /// QA-15 / R-23: the in-app rung. Staleness is computed at read time, so a destination
    /// that succeeded once and then went quiet still surfaces without a server.
    static func overdueBannerDetail() -> String? {
        let now = Date().timeIntervalSince1970
        let overdue = StatusSnapshotLocation.readAll().filter {
            $0.state(at: now) == .overdue
        }
        guard !overdue.isEmpty else { return nil }
        let names = overdue.map(\.destinationLabel).joined(separator: ", ")
        return "\(names). \(EscalationCopy.overdue)"
    }

    static func anchorHolds() async throws -> [AnchorHold] {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        return try await store.transact { try $0.loadAnchorHolds() }
    }

    /// QA-17: the user chose to send the history again. Recording the decision is what
    /// releases the hold; the run reads it rather than inferring intent from a retry.
    static func authoriseAnchorReexport(metric: MetricID) async throws {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        try await store.transact { tx in
            guard var hold = try tx.loadAnchorHold(metric: metric) else { return }
            hold.decision = .reexportAuthorized
            try tx.upsertAnchorHold(hold)
        }
    }

    /// QA-17's other answer: stop this type rather than pay to send its history again.
    static func stopExportingHeldType(metric: MetricID) async throws {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
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

    #if DEBUG
    /// QA-14 wants the success, stale and failed surfaces asserted. Reaching them for
    /// real needs a destination, a network and a clock that has moved on by days, none
    /// of which a UI test has. Seeding the snapshot exercises the same read path the
    /// app uses in the field.
    static func seedDestinationStatusForUITests(scenario: String) throws {
        let now = Date().timeIntervalSince1970
        let day: TimeInterval = 86_400
        let snapshot: DestinationStatusSnapshot
        switch scenario {
        case "stale":
            snapshot = DestinationStatusSnapshot(
                destinationID: "home-assistant",
                destinationLabel: "Home Assistant",
                enabled: true,
                lastOutcome: "success",
                lastSuccessEpoch: now - (3 * day),
                staleThresholdSeconds: day,
                overdueThresholdSeconds: 7 * day,
                writtenAtEpoch: now
            )
        case "overdue":
            snapshot = DestinationStatusSnapshot(
                destinationID: "home-assistant",
                destinationLabel: "Home Assistant",
                enabled: true,
                lastOutcome: "success",
                lastSuccessEpoch: now - (8 * day),
                staleThresholdSeconds: day,
                overdueThresholdSeconds: 7 * day,
                writtenAtEpoch: now
            )
        case "failed":
            snapshot = DestinationStatusSnapshot(
                destinationID: "home-assistant",
                destinationLabel: "Home Assistant",
                enabled: true,
                lastOutcome: "failed",
                lastSuccessEpoch: now - (2 * day),
                errorClass: ErrorClass.destinationUnreachable.rawValue,
                writtenAtEpoch: now
            )
        case "deferred":
            snapshot = DestinationStatusSnapshot(
                destinationID: "home-assistant",
                destinationLabel: "Home Assistant",
                enabled: true,
                lastOutcome: "blockedDeviceLocked",
                lastSuccessEpoch: now - 60,
                errorClass: ErrorClass.deviceLocked.rawValue,
                staleThresholdSeconds: day,
                overdueThresholdSeconds: 7 * day,
                writtenAtEpoch: now
            )
        case "changed":
            snapshot = DestinationStatusSnapshot(
                destinationID: "home-assistant",
                destinationLabel: "Home Assistant",
                enabled: true,
                lastOutcome: "success",
                lastSuccessEpoch: now - 60,
                errorClass: ErrorClass.none.rawValue,
                staleThresholdSeconds: day,
                unacknowledgedSecurityEventCount: 2,
                writtenAtEpoch: now
            )
        default:
            snapshot = DestinationStatusSnapshot(
                destinationID: "home-assistant",
                destinationLabel: "Home Assistant",
                enabled: true,
                lastOutcome: "success",
                lastSuccessEpoch: now - 60,
                errorClass: ErrorClass.none.rawValue,
                staleThresholdSeconds: day,
                writtenAtEpoch: now
            )
        }
        guard let url = StatusSnapshotLocation.url(destinationID: snapshot.destinationID)
        else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try DestinationSnapshotFile.write(snapshot, to: url)
    }

    /// A hold can only arise from state the simulator has no way to produce — a cursor
    /// that went missing behind a real HealthKit history. Seeding one is the only way a
    /// UI test can assert what the user sees when it happens.
    static func seedAnchorHoldForUITests(metric: MetricID) async throws {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        try await store.transact { tx in
            try tx.upsertAnchorHold(
                AnchorHold(
                    metric: metric,
                    reason: .cursorLost,
                    detectedAtEpoch: 0,
                    lastEmittedDay: "2026-09-08"
                )
            )
        }
    }
    #endif

    static func ledgerLines() async throws -> [String] {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
        let entries = try await store.transact { tx in
            try tx.loadLedger()
        }
        let verification = await LedgerHeadSealRecordFile.verify(
            entries: entries,
            seal: ledgerHeadSeal(),
            url: root.appendingPathComponent("ledger-head-seal.json")
        )
        var lines: [String]
        switch verification {
        case .valid(let head, let count):
            let shortHead = head == LedgerChain.genesisHash ? "genesis" : String(head.prefix(12))
            lines = ["Chain and device seal valid · \(count) entries · head \(shortHead)"]
        case .chainInvalid(let sequence):
            lines = ["WARNING: chain verification failed at sequence \(sequence)"]
        case .sealMissing:
            lines = ["WARNING: ledger head has not been device-sealed"]
        case .headMismatch:
            lines = ["WARNING: sealed head does not match the ledger"]
        case .identityChanged:
            lines = ["WARNING: ledger identity changed"]
        }
        lines.append(contentsOf: entries.suffix(50).reversed().map { entry in
            let date = Date(timeIntervalSince1970: entry.wallTimeEpoch)
                .formatted(date: .abbreviated, time: .shortened)
            return "\(date) · \(entry.destination) · \(entry.outcomeKind) · \(entry.sampleCount) records · \(entry.byteCount) bytes"
        })
        return lines
    }

    static func ledgerIntegrityLine() async throws -> String {
        let lines = try await ledgerLines()
        return lines.first ?? "Ledger has not been written yet."
    }

    static func historyLines() async throws -> [String] {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        let events = try await store.transact { try $0.loadJournal() }
        guard !events.isEmpty else {
            return [RunHistoryDetail.emptyStateCopy, RunHistoryDetail.retentionCopy]
        }
        var lines = [RunHistoryDetail.retentionCopy]
        for event in RunHistory.problemsFirst(events) {
            lines.append(contentsOf: RunHistoryDetail.lines(for: event))
        }
        return lines
    }

    static func sentThroughDay(metric: MetricID) async throws -> String? {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        return try await BrowserSendState.sentThroughDay(metric: metric, store: store)
    }

    static func indexHorizonDay() async throws -> String? {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        return try await BrowserSendState.indexHorizonDay(store: store)
    }

    static func wakeAttributionLine() async throws -> String {
        let snapshots = StatusSnapshotLocation.readAll()
        guard let expected = snapshots.compactMap(\.nextAttemptLatestEpoch).min() else {
            return "Wake attribution: no measured delivery deadline is configured."
        }
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        let journal = try await store.transact { try $0.loadJournal() }
        let attribution = WakeAttribution.classify(
            wakes: try wakeLedger().records(),
            lastJournal: journal.last,
            nowEpoch: Date().timeIntervalSince1970,
            expectedWakeByEpoch: expected
        )
        return "Wake attribution: \(attribution.userFacingCopy)"
    }

    static func acknowledgeDestinationChanges() throws {
        let now = Date().timeIntervalSince1970
        for snapshot in StatusSnapshotLocation.readAll() where snapshot.unacknowledgedSecurityEventCount > 0 {
            guard let url = StatusSnapshotLocation.url(destinationID: snapshot.destinationID) else {
                continue
            }
            try DestinationSnapshotFile.acknowledgeSecurityEvents(writtenAtEpoch: now, at: url)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
    }

    static func prepareHTTPSDestination(
        urlString: String,
        allowInsecureHTTP: Bool,
        bearer: String?,
        importedLocalIdentifier: String? = nil,
        onProgress: DestinationTestProgress? = nil
    ) async throws -> DestinationConfirmationCard {
        guard let host = URL(string: urlString)?.host?.lowercased(), !host.isEmpty else {
            throw EgressError.invalidURL
        }
        let allowedHosts: Set<String> = [host]
        let destination = try HTTPSDestination(
            urlString: urlString,
            allowedHosts: allowedHosts,
            allowInsecureHTTP: allowInsecureHTTP,
            authorizationBearer: bearer
        )
        let transport = try SystemHTTPTransport.make(
            probing: destination.url,
            allowedHosts: allowedHosts,
            allowInsecureHTTP: allowInsecureHTTP
        )
        let now = Date().ISO8601Format()
        let probe = try await withThermalCompression {
            try await HTTPSDestinationEnable.probe(
                destination: destination,
                transport: transport,
                exporterID: try installationID(),
                emittedAt: now,
                meteredPolicy: .fromAllowsMetered(allowsMeteredNetwork(destinationID: "https")),
                pathConditions: networkPathConditions(),
                onProgress: onProgress
            )
        }
        await PendingDestination.shared.setHTTPS(PendingHTTPS(
            probe: probe,
            host: host,
            allowedHosts: allowedHosts.sorted(),
            allowInsecureHTTP: allowInsecureHTTP,
            bearer: bearer,
            firstSeen: now,
            importedLocalIdentifier: importedLocalIdentifier
        ))
        return DestinationConfirmationCard(
            host: host,
            identity: probe.identity,
            preview: probe.preview,
            insecureWithoutTLS: allowInsecureHTTP && probe.identity == nil
        )
    }

    static func confirmPendingHTTPSDestination(propagateTraceparent: Bool = false) async throws -> [String] {
        try ExportScopeGate.requireConfigured(try await destinationScope("https"))
        guard let pending = await PendingDestination.shared.takeHTTPS() else {
            throw SetupError.verificationRequired
        }
        let probe = pending.probe
        let events = probe.pendingEvents + [.destinationEnabled]
        let record = HTTPSVerificationRecord(
            urlString: probe.destination.url.absoluteString,
            allowedHosts: pending.allowedHosts,
            allowInsecureHTTP: pending.allowInsecureHTTP,
            report: probe.report,
            leafSPKISha256: probe.identity?.leafSPKISha256,
            issuerSPKISha256: probe.identity?.issuerSPKISha256,
            firstSeen: pending.firstSeen,
            hasBearer: pending.bearer != nil,
            propagateTraceparent: propagateTraceparent,
            importedLocalIdentifier: pending.importedLocalIdentifier
        )
        let root = try applicationSupportRoot()
        let bearerStore = KeychainSecretStore(
            service: "app.openhealthexporter.ios.https"
        )
        let bearerHandle = SecretHandle(rawValue: "bearer")
        if let bearer = pending.bearer {
            try await bearerStore.store(Array(bearer.utf8), handle: bearerHandle)
        } else {
            try? await bearerStore.delete(bearerHandle)
        }
        try JSONEncoder().encode(record).write(
            to: root.appendingPathComponent("https-destination.json"),
            options: .atomic
        )
        if let snapshotURL = StatusSnapshotLocation.url(destinationID: "https") {
            try DestinationSnapshotFile.recordSecurityEvents(
                events.count,
                destinationID: "https",
                destinationLabel: pending.host,
                writtenAtEpoch: Date().timeIntervalSince1970,
                at: snapshotURL
            )
        }
        try await emitTrustNotices(events, destination: pending.host)
        try await requestScopeAuthorizationIfConfigured("https")
        if pending.allowInsecureHTTP {
            let store = try SQLiteStateStore(
                path: root.appendingPathComponent("state.sqlite").path
            )
            try await store.transact { tx in
                try tx.appendLedger(
                    EgressEntry(
                        destination: pending.host,
                        sampleCount: 0,
                        outcomeKind: "security:insecure_http_enabled",
                        detail: "explicit_user_opt_in",
                        wallTimeEpoch: Date().timeIntervalSince1970
                    )
                )
            }
        }
        return DestinationConfirmationCard(
            host: pending.host,
            identity: probe.identity,
            preview: probe.preview,
            insecureWithoutTLS: pending.allowInsecureHTTP && probe.identity == nil
        ).lines
            + probe.report.steps.map { "\($0.name.rawValue): \($0.outcome.rawValue)" }
    }

    static func cancelPendingHTTPSDestination() {
        Task { await PendingDestination.shared.setHTTPS(nil) }
    }

    static func prepareMQTTDestination(
        urlString: String,
        allowInsecure: Bool,
        clientID: String,
        topic: String,
        clientPKCS12: Data? = nil,
        clientPKCS12Password: String? = nil,
        username: String? = nil,
        password: String? = nil,
        qos: UInt8 = 1,
        importedLocalIdentifier: String? = nil,
        onProgress: DestinationTestProgress? = nil
    ) async throws -> DestinationConfirmationCard {
        guard let host = URL(string: urlString)?.host?.lowercased(), !host.isEmpty else {
            throw EgressError.invalidURL
        }
        let allowedHosts: Set<String> = [host]
        let exporterID = try installationID()
        let destination = try MQTTDestination(
            urlString: urlString,
            allowedHosts: allowedHosts,
            allowInsecure: allowInsecure,
            clientID: clientID,
            topic: topic,
            qos: try MQTTDestination.qos(configurationValue: qos),
            username: username,
            password: password,
            clientPKCS12: clientPKCS12,
            clientPKCS12Password: clientPKCS12Password,
            exporterID: exporterID
        )
        let sink = try MQTTSink.overNetwork(destination: destination, pin: nil)
        let now = Date().ISO8601Format()
        let probe = try await MQTTDestinationEnable.probe(
            destination: destination,
            pipe: sink.pipe,
            exporterID: try installationID(),
            emittedAt: now,
            meteredPolicy: .fromAllowsMetered(allowsMeteredNetwork(destinationID: "mqtt")),
            pathConditions: networkPathConditions(),
            onProgress: onProgress
        )
        await PendingDestination.shared.setMQTT(PendingMQTT(
            probe: probe,
            host: host,
            allowedHosts: allowedHosts.sorted(),
            allowInsecure: allowInsecure,
            clientID: clientID,
            topic: topic,
            qos: qos,
            clientPKCS12: clientPKCS12,
            clientPKCS12Password: clientPKCS12Password,
            username: username,
            password: password,
            firstSeen: now,
            importedLocalIdentifier: importedLocalIdentifier
        ))
        return DestinationConfirmationCard(
            host: host,
            identity: probe.identity,
            preview: probe.preview,
            insecureWithoutTLS: allowInsecure && probe.identity == nil
        )
    }

    static func confirmPendingMQTTDestination() async throws -> [String] {
        try ExportScopeGate.requireConfigured(try await destinationScope("mqtt"))
        guard let pending = await PendingDestination.shared.takeMQTT() else {
            throw SetupError.verificationRequired
        }
        let probe = pending.probe
        let events = probe.pendingEvents + [.destinationEnabled]
        let record = MQTTVerificationRecord(
            urlString: probe.destination.url.absoluteString,
            allowedHosts: pending.allowedHosts,
            allowInsecure: pending.allowInsecure,
            clientID: pending.clientID,
            topic: pending.topic,
            qos: pending.qos,
            report: probe.report,
            hasClientPKCS12: pending.clientPKCS12 != nil,
            clientPKCS12Password: pending.clientPKCS12Password,
            username: pending.username,
            hasPassword: pending.password != nil,
            leafSPKISha256: probe.identity?.leafSPKISha256,
            issuerSPKISha256: probe.identity?.issuerSPKISha256,
            firstSeen: pending.firstSeen,
            importedLocalIdentifier: pending.importedLocalIdentifier
        )
        let root = try applicationSupportRoot()
        let pkcs12URL = root.appendingPathComponent("mqtt-client.p12")
        if let clientPKCS12 = pending.clientPKCS12 {
            try clientPKCS12.write(to: pkcs12URL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: pkcs12URL)
        }
        let passwordStore = KeychainSecretStore(
            service: "app.openhealthexporter.mqtt"
        )
        let passwordHandle = SecretHandle(rawValue: "mqtt_password")
        if let password = pending.password {
            try await passwordStore.store(Array(password.utf8), handle: passwordHandle)
        } else {
            try? await passwordStore.delete(passwordHandle)
        }
        try JSONEncoder().encode(record).write(
            to: root.appendingPathComponent("mqtt-destination.json"),
            options: .atomic
        )
        if let snapshotURL = StatusSnapshotLocation.url(destinationID: "mqtt") {
            try DestinationSnapshotFile.recordSecurityEvents(
                events.count,
                destinationID: "mqtt",
                destinationLabel: pending.host,
                writtenAtEpoch: Date().timeIntervalSince1970,
                at: snapshotURL
            )
        }
        try await emitTrustNotices(events, destination: pending.host)
        try await requestScopeAuthorizationIfConfigured("mqtt")
        if pending.allowInsecure {
            let store = try SQLiteStateStore(
                path: root.appendingPathComponent("state.sqlite").path
            )
            try await store.transact { tx in
                try tx.appendLedger(
                    EgressEntry(
                        destination: pending.host,
                        sampleCount: 0,
                        outcomeKind: "security:insecure_mqtt_enabled",
                        detail: "explicit_user_opt_in",
                        wallTimeEpoch: Date().timeIntervalSince1970
                    )
                )
            }
        }
        return DestinationConfirmationCard(
            host: pending.host,
            identity: probe.identity,
            preview: probe.preview,
            insecureWithoutTLS: pending.allowInsecure && probe.identity == nil
        ).lines
            + probe.report.steps.map { "\($0.name.rawValue): \($0.outcome.rawValue)" }
    }

    static func cancelPendingMQTTDestination() {
        Task { await PendingDestination.shared.setMQTT(nil) }
    }

    static func runMQTTDestination(
        onProgress: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> [String] {
        let root = try applicationSupportRoot()
        let data = try Data(
            contentsOf: root.appendingPathComponent("mqtt-destination.json")
        )
        let saved = try JSONDecoder().decode(MQTTVerificationRecord.self, from: data)
        let allowedHosts = Set(saved.allowedHosts)
        let pkcs12URL = root.appendingPathComponent("mqtt-client.p12")
        let pkcs12 = (saved.hasClientPKCS12 == true) ? try Data(contentsOf: pkcs12URL) : nil
        let password: String?
        if saved.hasPassword == true {
            password = String(
                decoding: try await KeychainSecretStore(
                    service: "app.openhealthexporter.mqtt"
                ).load(SecretHandle(rawValue: "mqtt_password")),
                as: UTF8.self
            )
        } else {
            password = nil
        }
        let destination = try MQTTDestination(
            urlString: saved.urlString,
            allowedHosts: allowedHosts,
            allowInsecure: saved.allowInsecure,
            clientID: saved.clientID,
            topic: saved.topic,
            qos: try MQTTDestination.qos(configurationValue: saved.qos ?? 1),
            username: saved.username,
            password: password,
            clientPKCS12: pkcs12,
            clientPKCS12Password: saved.clientPKCS12Password,
            exporterID: try installationID()
        )
        let pin: PinRecord?
        if let leaf = saved.leafSPKISha256, let issuer = saved.issuerSPKISha256 {
            pin = PinRecord(
                leafSPKISha256: leaf,
                issuerSPKISha256: issuer,
                firstSeen: saved.firstSeen ?? "1970-01-01T00:00:00Z",
                policy: .leaf
            )
        } else {
            pin = nil
        }
        var sink = try MQTTSink.overNetwork(destination: destination, pin: pin)
        sink.meteredPolicy = .fromAllowsMetered(allowsMeteredNetwork(destinationID: "mqtt"))
        sink.pathConditions = networkPathConditions()
        var setup = DestinationSetup()
        try setup.resumeEnabled(testReport: saved.report)
        let verified = try setup.enable(sink: sink)
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        let scratch = try protectedPayloadDirectory(named: "scratch", under: root)
        let context = TemporalContext.utcHost
        let now = Date().ISO8601Format()
        let exporterID = try installationID()
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
        let ledgerSeal = ledgerHeadSeal()
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
                outcome,
                destinationID: "mqtt",
                destinationLabel: "MQTT destination"
            )
            lines.append("\(metric.rawValue): \(outcome.kind.rawValue)")
            lines.append(
                try await trailingReconcileAfterDelta(
                    observations: observations,
                    destination: verified,
                    store: store,
                    metric: metric,
                    scratchDirectory: scratch,
                    destinationID: "mqtt",
                    destinationLabel: "MQTT destination",
                    envelope: envelope,
                    temporal: context,
                    statistics: statistics,
                    trigger: .manual,
                    snapshotURL: snapshotURL,
                    ledgerHeadSeal: ledgerSeal,
                    ledgerSealURL: ledgerSealURL,
                    scope: scope
                )
            )
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
        try await applyQueueRedIfNeeded(
            store: store,
            root: root,
            destinationLabel: "MQTT destination"
        )
        return lines
    }

    static func runHTTPSDestination(
        onProgress: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> [String] {
        try await withThermalCompression {
            try await runHTTPSDestinationUnscoped(onProgress: onProgress)
        }
    }

    private static func runHTTPSDestinationUnscoped(
        onProgress: (@Sendable (Int, Int) async -> Void)?
    ) async throws -> [String] {
        let root = try applicationSupportRoot()
        let data = try Data(
            contentsOf: root.appendingPathComponent("https-destination.json")
        )
        let saved = try JSONDecoder().decode(HTTPSVerificationRecord.self, from: data)
        let allowedHosts = Set(saved.allowedHosts)
        let bearer: String?
        if saved.hasBearer {
            bearer = String(
                decoding: try await KeychainSecretStore(
                    service: "app.openhealthexporter.ios.https"
                ).load(SecretHandle(rawValue: "bearer")),
                as: UTF8.self
            )
        } else {
            bearer = nil
        }
        let destination = try HTTPSDestination(
            urlString: saved.urlString,
            allowedHosts: allowedHosts,
            allowInsecureHTTP: saved.allowInsecureHTTP,
            authorizationBearer: bearer
        )
        let base = try SystemHTTPTransport.make(
            probing: destination.url,
            allowedHosts: allowedHosts,
            allowInsecureHTTP: saved.allowInsecureHTTP
        )
        let transport: any HTTPTransport
        if let leaf = saved.leafSPKISha256, let issuer = saved.issuerSPKISha256 {
            transport = PinningHTTPTransport(
                inner: base,
                pin: PinRecord(
                    leafSPKISha256: leaf,
                    issuerSPKISha256: issuer,
                    firstSeen: saved.firstSeen,
                    policy: .leaf
                )
            )
        } else {
            transport = base
        }
        let emission = TraceparentEmission(enabled: saved.propagateTraceparent ?? false)
        var setup = DestinationSetup()
        try setup.resumeEnabled(testReport: saved.report)
        let verified = try setup.enable(
            sink: HTTPSSink(
                destination: destination,
                transport: transport,
                traceparent: emission,
                meteredPolicy: .fromAllowsMetered(allowsMeteredNetwork(destinationID: "https")),
                pathConditions: networkPathConditions()
            )
        )
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        let scratch = try protectedPayloadDirectory(named: "scratch", under: root)
        let context = TemporalContext.utcHost
        let now = Date().ISO8601Format()
        let exporterID = try installationID()
        var lines: [String] = []
        let scope = try await destinationScope("https")
        try ExportScopeGate.requireConfigured(scope)
        let source = HealthKitAnchoredSource(
            context: context,
            limit: samplePageLimit(),
            window: HealthKitQueryWindow(scope: scope)
        )
        let observations = HealthKitDayObservationSource(context: context)
        let statistics = HealthKitStatisticsSource(context: context)
        let snapshotURL = StatusSnapshotLocation.url(destinationID: "https")
        let ledgerSeal = ledgerHeadSeal()
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
                destinationName: "https",
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
                outcome,
                destinationID: "https",
                destinationLabel: "HTTPS destination"
            )
            lines.append("\(metric.rawValue): \(outcome.kind.rawValue)")
            lines.append(
                try await trailingReconcileAfterDelta(
                    observations: observations,
                    destination: verified,
                    store: store,
                    metric: metric,
                    scratchDirectory: scratch,
                    destinationID: "https",
                    destinationLabel: "HTTPS destination",
                    envelope: envelope,
                    temporal: context,
                    statistics: statistics,
                    trigger: .manual,
                    snapshotURL: snapshotURL,
                    ledgerHeadSeal: ledgerSeal,
                    ledgerSealURL: ledgerSealURL,
                    scope: scope
                )
            )
        }
        if emission.autoDisabled {
            try setHTTPSTraceparent(false)
            lines.append("traceparent auto-disabled after a header-plausible failure")
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
        try await applyQueueRedIfNeeded(
            store: store,
            root: root,
            destinationLabel: "HTTPS destination"
        )
        return lines
    }

    static func enableLocalFileDestination(
        onProgress: DestinationTestProgress? = nil
    ) async throws -> [String] {
        try ExportScopeGate.requireConfigured(try await destinationScope("local-file"))
        let root = try applicationSupportRoot()
        let dest = try protectedPayloadDirectory(named: "exports", under: root)
        try? FileManager.default.removeItem(at: localFileTestReportURL(root: root))
        let (_, events) = try verifiedLocalFile(
            root: root,
            destinationDirectory: dest,
            onProgress: onProgress
        )
        try await emitTrustNotices(events)
        try await requestScopeAuthorizationIfConfigured("local-file")
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
        return destinationStatusLines()
    }

    static func stopExportingHeartRate() async throws {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
        try await store.purgeType(
            metric: MetricCatalog.heartRate.id,
            reason: "explicit_stop",
            destination: "local-file",
            atEpoch: Date().timeIntervalSince1970
        )
    }

    static func expireQueuesAndNotify() async throws -> QueueExpiryResult {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
        let now = Date().timeIntervalSince1970
        let result = try await store.expirePending(
            nowEpoch: now,
            destination: "configured destinations"
        )
        guard result.expiredBatches > 0 else { return result }
        let entries = try await store.transact { try $0.loadLedger() }
        try await LedgerHeadSealRecordFile.update(
            entries: entries,
            seal: ledgerHeadSeal(),
            sealedAtEpoch: now,
            url: root.appendingPathComponent("ledger-head-seal.json")
        )
        _ = try await LocalUserNotifier().notify(
            UserNotice(kind: .queueExpired, destination: "Configured destinations")
        )
        return result
    }

    /// UX-26: seal leftover open runs after process death, then tell the person.
    static func recoverInterruptedExports() async throws -> String? {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
        let now = Date().timeIntervalSince1970
        let sealed = try await InterruptedRunRecovery.seal(store: store, nowEpoch: now)
        guard let first = sealed.min(by: { $0.startedAtEpoch < $1.startedAtEpoch }) else {
            return nil
        }
        let snapshots = StatusSnapshotLocation.readAll()
        let label = snapshots.first { $0.destinationID == first.destinationID }?.destinationLabel
            ?? first.destinationID
        let notice = UserNotice(
            kind: .exportInterrupted,
            destinationID: first.destinationID,
            destination: label,
            errorClass: ErrorClass.cancelledBySystem.rawValue,
            startedAtEpoch: first.startedAtEpoch
        )
        _ = try await LocalUserNotifier().notify(notice)
        for run in sealed {
            guard let url = StatusSnapshotLocation.url(destinationID: run.destinationID),
                  var snapshot = try? DestinationSnapshotFile.read(from: url)
            else {
                continue
            }
            snapshot.applyLastOutcome(RunOutcome.Kind.cancelledBySystem.rawValue)
            snapshot.errorClass = ErrorClass.cancelledBySystem.rawValue
            snapshot.writtenAtEpoch = now
            try DestinationSnapshotFile.write(snapshot, to: url)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
        return NoticeCopy.render(notice).body
    }

    static func storedHTTPSTraceparent() -> Bool {
        guard let root = try? applicationSupportRoot(),
              let data = try? Data(contentsOf: root.appendingPathComponent("https-destination.json")),
              let record = try? JSONDecoder().decode(HTTPSVerificationRecord.self, from: data)
        else {
            return false
        }
        return record.propagateTraceparent ?? false
    }

    static func setHTTPSTraceparent(_ enabled: Bool) throws {
        let root = try applicationSupportRoot()
        let url = root.appendingPathComponent("https-destination.json")
        guard let data = try? Data(contentsOf: url),
              var record = try? JSONDecoder().decode(HTTPSVerificationRecord.self, from: data)
        else {
            return
        }
        record.propagateTraceparent = enabled
        try JSONEncoder().encode(record).write(to: url, options: .atomic)
    }

    static func storedCompanionTraceparent() -> Bool {
        UserDefaults.standard.bool(forKey: "ohe.companion.propagateTraceparent")
    }

    static func setCompanionTraceparent(_ enabled: Bool) throws {
        UserDefaults.standard.set(enabled, forKey: "ohe.companion.propagateTraceparent")
        let root = try applicationSupportRoot()
        let url = companionTestReportURL(root: root)
        guard let data = try? Data(contentsOf: url),
              var record = try? JSONDecoder().decode(CompanionVerificationRecord.self, from: data)
        else {
            return
        }
        record.propagateTraceparent = enabled
        try JSONEncoder().encode(record).write(to: url, options: .atomic)
    }

    static func portableConfigurationExport() async throws -> URL {
        let root = try applicationSupportRoot()
        var destinations: [PortableDestinationConfiguration] = []
        let httpsURL = root.appendingPathComponent("https-destination.json")
        if let data = try? Data(contentsOf: httpsURL),
           let record = try? JSONDecoder().decode(
               HTTPSVerificationRecord.self,
               from: data
           ),
           record.report.allowsEnablement {
            let scope = try await destinationScope("https")
            destinations.append(
                try PortableDestinationConfiguration(
                    sourceIdentifier:
                        record.importedLocalIdentifier ?? "https",
                    displayName:
                        URL(string: record.urlString)?.host ?? "HTTPS",
                    kind: .https,
                    endpoint: record.urlString,
                    settings: [
                        "allowInsecureHTTP":
                            record.allowInsecureHTTP ? "true" : "false",
                        "method": "POST",
                    ],
                    exportScope: try PortableDestinationExportScope(
                        metrics: scope.metrics.sorted {
                            $0.rawValue < $1.rawValue
                        },
                        startInclusive: scope.startInclusive,
                        endExclusive: scope.endExclusive
                    )
                )
            )
        }
        let mqttURL = root.appendingPathComponent("mqtt-destination.json")
        if let data = try? Data(contentsOf: mqttURL),
           let record = try? JSONDecoder().decode(
               MQTTVerificationRecord.self,
               from: data
           ),
           record.report.allowsEnablement {
            let scope = try await destinationScope("mqtt")
            destinations.append(
                try PortableDestinationConfiguration(
                    sourceIdentifier:
                        record.importedLocalIdentifier ?? "mqtt",
                    displayName:
                        URL(string: record.urlString)?.host ?? "MQTT",
                    kind: .mqtt,
                    endpoint: record.urlString,
                    settings: [
                        "allowInsecure":
                            record.allowInsecure ? "true" : "false",
                        "clientID": record.clientID,
                        "qos": String(record.qos ?? 1),
                        "topic": record.topic,
                    ],
                    exportScope: try PortableDestinationExportScope(
                        metrics: scope.metrics.sorted {
                            $0.rawValue < $1.rawValue
                        },
                        startInclusive: scope.startInclusive,
                        endExclusive: scope.endExclusive
                    )
                )
            )
        }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-health-exporter.tributary")
        try DestinationConfigurationDocument(destinations: destinations)
            .encoded()
            .write(to: output, options: [.atomic, .completeFileProtection])
        return output
    }

    #if !OHE_OBS25_SIZE_BASELINE
    static func storedOTLPURL() -> String {
        guard let root = try? applicationSupportRoot(),
              let data = try? Data(contentsOf: root.appendingPathComponent("otlp-destination.json")),
              let record = try? JSONDecoder().decode(OTLPDestinationRecord.self, from: data)
        else {
            return ""
        }
        return record.urlString
    }

    static func previewOTLP() async throws -> (preview: String, payload: Data) {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        let events = try await store.transact { try $0.loadJournal() }
        let payload = OTLPPreview.payload(events: events)
        return (OTLPPreview.text(payload: payload), payload)
    }

    static func enableOTLPCollector(
        urlString: String,
        allowInsecureHTTP: Bool,
        previewPayload: Data
    ) async throws -> [String] {
        let settings = try OTLPSettingsGate.enabledSettings(
            urlString: urlString,
            allowInsecureHTTP: allowInsecureHTTP,
            previewCompleted: !previewPayload.isEmpty
        )
        guard let endpoint = settings.endpoint, let host = endpoint.url.host else {
            throw OTLPExportError.endpointRequired
        }
        let root = try applicationSupportRoot()
        let record = OTLPDestinationRecord(
            urlString: endpoint.url.absoluteString,
            allowedHosts: [host],
            allowInsecureHTTP: allowInsecureHTTP,
            previewDigest: ContentSHA256.digest(previewPayload)
        )
        try JSONEncoder().encode(record).write(
            to: root.appendingPathComponent("otlp-destination.json"),
            options: .atomic
        )
        let now = Date().timeIntervalSince1970
        if let snapshotURL = StatusSnapshotLocation.url(destinationID: "otlp") {
            try DestinationSnapshotFile.write(
                DestinationStatusSnapshot(
                    destinationID: "otlp",
                    destinationLabel: host,
                    enabled: true,
                    state: .noExportsYet,
                    unacknowledgedSecurityEventCount: allowInsecureHTTP ? 1 : 0,
                    writtenAtEpoch: now
                ),
                to: snapshotURL
            )
        }
        if allowInsecureHTTP {
            let store = try SQLiteStateStore(
                path: root.appendingPathComponent("state.sqlite").path
            )
            try await store.transact { tx in
                try tx.appendLedger(
                    EgressEntry(
                        destination: host,
                        sampleCount: 0,
                        outcomeKind: "security:insecure_http_enabled",
                        detail: "explicit_user_opt_in otlp",
                        wallTimeEpoch: now
                    )
                )
            }
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
        return destinationStatusLines()
    }

    static func disableOTLPCollector() throws {
        let root = try applicationSupportRoot()
        try? FileManager.default.removeItem(
            at: root.appendingPathComponent("otlp-destination.json")
        )
        if let snapshotURL = StatusSnapshotLocation.url(destinationID: "otlp") {
            try? FileManager.default.removeItem(at: snapshotURL)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
    }

    private static func otlpMetricsDestination(
        tracesEndpoint: HTTPSDestination,
        allowedHosts: Set<String>
    ) throws -> HTTPSDestination {
        var components = URLComponents(
            url: tracesEndpoint.url,
            resolvingAgainstBaseURL: false
        )
        if components?.path.hasSuffix("/v1/traces") == true {
            components?.path.removeLast("traces".count)
            components?.path.append("metrics")
        } else {
            let path = components?.path ?? ""
            components?.path = path.hasSuffix("/") ? "\(path)v1/metrics" : "\(path)/v1/metrics"
        }
        guard let url = components?.url else {
            throw OTLPExportError.endpointRequired
        }
        return try HTTPSDestination(
            urlString: url.absoluteString,
            allowedHosts: allowedHosts,
            allowInsecureHTTP: tracesEndpoint.allowInsecureHTTP
        )
    }

    static func projectOTLP() async throws -> String {
        let root = try applicationSupportRoot()
        guard let data = try? Data(
            contentsOf: root.appendingPathComponent("otlp-destination.json")
        ),
            let record = try? JSONDecoder().decode(OTLPDestinationRecord.self, from: data)
        else {
            throw OTLPExportError.endpointRequired
        }
        let settings = try OTLPSettingsGate.enabledSettings(
            urlString: record.urlString,
            allowInsecureHTTP: record.allowInsecureHTTP,
            previewCompleted: true
        )
        guard let endpoint = settings.endpoint else {
            throw OTLPExportError.endpointRequired
        }
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        let now = Date().timeIntervalSince1970
        let selection = try await store.transact { tx in
            OTLPBacklog.select(events: try tx.loadJournal(), nowEpoch: now)
        }
        if !selection.dropped.isEmpty {
            try await store.transact { tx in
                try tx.markJournalProjected(
                    runIDs: selection.dropped.map(\.runID),
                    atEpoch: now
                )
                try tx.appendLedger(
                    EgressEntry(
                        destination: "otlp",
                        sampleCount: 0,
                        outcomeKind: "telemetry_dropped_backlog_cap",
                        detail: "dropped=\(selection.dropped.count)",
                        wallTimeEpoch: now
                    )
                )
            }
        }
        let metricDestinations = StatusSnapshotLocation.readAll().compactMap {
            snapshot -> OTLPMetricsDestination? in
            guard snapshot.enabled,
                  snapshot.destinationID != "otlp",
                  let lastSuccessEpoch = snapshot.lastSuccessEpoch
            else {
                return nil
            }
            return OTLPMetricsDestination(
                destinationID: snapshot.destinationID,
                lastSuccessEpoch: lastSuccessEpoch
            )
        }
        guard !selection.events.isEmpty || !metricDestinations.isEmpty else {
            return "No unprojected runs."
        }
        let scratch = try protectedPayloadDirectory(named: "scratch", under: root)
        let transport = try SystemHTTPTransport.make(
            probing: endpoint.url,
            allowedHosts: Set(record.allowedHosts),
            allowInsecureHTTP: record.allowInsecureHTTP
        )
        do {
            let exporter = OTLPExporter(
                settings: settings,
                transport: transport,
                meteredPolicy: .fromAllowsMetered(allowsMeteredNetwork(destinationID: "otlp")),
                pathConditions: networkPathConditions()
            )
            let metricsPosted: Bool
            if metricDestinations.isEmpty {
                metricsPosted = false
            } else {
                metricsPosted = try await exporter.exportMetrics(
                    destinations: metricDestinations,
                    nowEpoch: now,
                    endpoint: try otlpMetricsDestination(
                        tracesEndpoint: endpoint,
                        allowedHosts: Set(record.allowedHosts)
                    ),
                    bodyDirectory: scratch
                )
            }
            let tracesPosted = try await exporter.export(
                events: selection.events,
                bodyDirectory: scratch
            )
            let posted = tracesPosted || metricsPosted
            let traceByteCount = tracesPosted
                ? OTLPProjector.traces(events: selection.events).count
                : 0
            let metricsByteCount = metricsPosted
                ? OTLPMetricsProjector.metrics(
                    destinations: metricDestinations,
                    nowEpoch: now
                ).count
                : 0
            let byteCount = traceByteCount + metricsByteCount
            try await store.transact { tx in
                if tracesPosted {
                    try tx.markJournalProjected(
                        runIDs: selection.events.map(\.runID),
                        atEpoch: now
                    )
                }
                try tx.appendLedger(
                    EgressEntry(
                        destination: "otlp",
                        sampleCount: 0,
                        outcomeKind: posted ? "success" : "disabled",
                        byteCount: byteCount,
                        detail: "runs=\(selection.events.count),metrics=\(metricDestinations.count)",
                        wallTimeEpoch: now
                    )
                )
            }
            if posted, let snapshotURL = StatusSnapshotLocation.url(destinationID: "otlp") {
                try DestinationSnapshotFile.write(
                    DestinationStatusSnapshot(
                        destinationID: "otlp",
                        destinationLabel: endpoint.url.host ?? "otlp",
                        enabled: true,
                        state: .healthy,
                        lastOutcome: "success",
                        lastSuccessEpoch: now,
                        lastConfirmedAckEpoch: now,
                        writtenAtEpoch: now
                    ),
                    to: snapshotURL
                )
            }
            WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
            return posted
                ? "Projected \(selection.events.count) run(s) and \(metricDestinations.count) destination gauge set(s)."
                : "OTLP is disabled."
        } catch {
            try await store.transact { tx in
                try tx.appendLedger(
                    EgressEntry(
                        destination: "otlp",
                        sampleCount: 0,
                        outcomeKind: "failed",
                        detail: "projection_failed",
                        wallTimeEpoch: now
                    )
                )
            }
            if let snapshotURL = StatusSnapshotLocation.url(destinationID: "otlp") {
                try DestinationSnapshotFile.write(
                    DestinationStatusSnapshot(
                        destinationID: "otlp",
                        destinationLabel: endpoint.url.host ?? "otlp",
                        enabled: true,
                        state: .failing,
                        lastOutcome: "failed",
                        errorClass: "otlp_projection",
                        writtenAtEpoch: now
                    ),
                    to: snapshotURL
                )
            }
            WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
            throw error
        }
    }
    #endif

    static func wipeEverything() async throws {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
        try await DestructiveWipe.perform(
            store: store,
            secretStores: [
                KeychainSecretStore(service: "app.openhealthexporter.ios.psk"),
                KeychainSecretStore(service: "app.openhealthexporter.ios.https"),
                KeychainSecretStore(service: "app.openhealthexporter.mqtt"),
            ],
            ledgerSeal: resettableLedgerHeadSeal(),
            ledgerSealURL: root.appendingPathComponent("ledger-head-seal.json"),
            atEpoch: Date().timeIntervalSince1970
        )
        try await vault().forget()
        EgressAttemptLog.wipePersistent()
        for name in [
            "exports",
            "scratch",
            "backfill-scratch",
            "demo-exports",
            "demo-scratch",
            "demo-state.sqlite",
            "demo-state.sqlite-shm",
            "demo-state.sqlite-wal",
            "https-destination.json",
            "mqtt-destination.json",
            "mqtt-client.p12",
            "imported-destination-drafts.json",
            "otlp-destination.json",
            "local-file-test.json",
            "companion-test.json",
            "backfill-raw.json",
            "backfill-aggregate.json",
            "backfill-raw-manifest.json",
            "backfill-aggregate-manifest.json",
            "advisory-request-body",
            "exporter-id",
            "wake-ledger.log",
            "health-authorization.json",
            "network-activity.json",
        ] {
            try removeIfPresent(root.appendingPathComponent(name))
        }
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        if let directory = StatusSnapshotLocation.directory() {
            try removeIfPresent(directory)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
    }

    private static func removeIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func verifiedLocalFile(
        root: URL,
        destinationDirectory: URL,
        onProgress: DestinationTestProgress? = nil
    ) throws -> (VerifiedDestination, [TrustEvent]) {
        let reportURL = localFileTestReportURL(root: root)
        if let saved = try? Data(contentsOf: reportURL),
           let report = try? JSONDecoder().decode(DestinationTestReport.self, from: saved),
           report.allowsEnablement {
            return (
                try LocalFileDestinationEnable.resume(
                    directory: destinationDirectory,
                    testReport: report
                ),
                []
            )
        }
        let completed = try LocalFileDestinationEnable.complete(
            directory: destinationDirectory,
            exporterId: try installationID(),
            emittedAt: Date().ISO8601Format(),
            onProgress: onProgress
        )
        try JSONEncoder().encode(completed.report).write(to: reportURL, options: .atomic)
        if let snapshotURL = StatusSnapshotLocation.url(destinationID: "local-file") {
            try DestinationSnapshotFile.recordSecurityEvents(
                completed.events.count,
                destinationID: "local-file",
                destinationLabel: "This iPhone → Archive folder",
                writtenAtEpoch: Date().timeIntervalSince1970,
                at: snapshotURL
            )
        }
        return (completed.destination, completed.events)
    }

    private static func emitTrustNotices(_ events: [TrustEvent]) async throws {
        try await emitTrustNotices(events, destination: "local-file")
    }

    private static func emitTrustNotices(
        _ events: [TrustEvent],
        destination: String
    ) async throws {
        guard !events.isEmpty else { return }
        let notifier = LocalUserNotifier()
        let deliveries = try await TrustNoticePosting.post(
            events: events,
            destination: destination,
            notifier: notifier
        )
        let suppressed = TrustNoticePosting.suppressedCount(deliveries)
        guard suppressed > 0 else { return }
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        try await store.transact { tx in
            try tx.appendLedger(
                EgressEntry(
                    destination: destination,
                    sampleCount: 0,
                    outcomeKind: "security:notifications_denied",
                    detail: "trust_notice_suppressed:\(suppressed)",
                    wallTimeEpoch: Date().timeIntervalSince1970
                )
            )
        }
        for snapshot in StatusSnapshotLocation.readAll() where snapshot.destinationLabel == destination {
            if let snapshotURL = StatusSnapshotLocation.url(destinationID: snapshot.destinationID) {
                try DestinationSnapshotFile.recordSecurityEvents(
                    suppressed,
                    destinationID: snapshot.destinationID,
                    destinationLabel: snapshot.destinationLabel,
                    writtenAtEpoch: Date().timeIntervalSince1970,
                    at: snapshotURL
                )
            }
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
    }

    private static func localFileTestReportURL(root: URL) -> URL {
        root.appendingPathComponent("local-file-test.json")
    }

    static func isLocalFileEnabled() -> Bool {
        guard let root = try? applicationSupportRoot(),
              let data = try? Data(contentsOf: localFileTestReportURL(root: root)),
              let report = try? JSONDecoder().decode(DestinationTestReport.self, from: data)
        else {
            return false
        }
        return report.allowsEnablement
    }

    /// UX-45: hops for the onboarding and Settings explainer. Credential *kinds*
    /// only — never tokens, passwords, or PKCS#12 bytes.
    static func dataFlowHops() -> [DataFlowHop] {
        guard let root = try? applicationSupportRoot() else { return [] }
        var hops: [DataFlowHop] = []
        if isLocalFileEnabled() {
            hops.append(
                DataFlowHop(
                    id: "local-file",
                    host: "Files on this iPhone",
                    transport: "Local files",
                    credential: DataFlowHop.noNetwork
                )
            )
        }
        if let data = try? Data(contentsOf: root.appendingPathComponent("https-destination.json")),
           let record = try? JSONDecoder().decode(HTTPSVerificationRecord.self, from: data),
           record.report.allowsEnablement
        {
            hops.append(
                DataFlowHop(
                    id: "https",
                    host: dataFlowHost(record.urlString),
                    transport: record.allowInsecureHTTP ? "HTTP" : "HTTPS",
                    credential: record.hasBearer ? DataFlowHop.bearerToken : DataFlowHop.noCredential
                )
            )
        }
        if let data = try? Data(contentsOf: root.appendingPathComponent("mqtt-destination.json")),
           let record = try? JSONDecoder().decode(MQTTVerificationRecord.self, from: data),
           record.report.allowsEnablement
        {
            let credential: String
            if record.hasClientPKCS12 == true {
                credential = DataFlowHop.clientCertificate
            } else if record.username != nil || record.hasPassword == true {
                credential = DataFlowHop.usernamePassword
            } else {
                credential = DataFlowHop.noCredential
            }
            hops.append(
                DataFlowHop(
                    id: "mqtt",
                    host: dataFlowHost(record.urlString),
                    transport: record.allowInsecure ? "MQTT" : "MQTTS",
                    credential: credential
                )
            )
        }
        if let data = try? Data(contentsOf: companionTestReportURL(root: root)),
           let record = try? JSONDecoder().decode(CompanionVerificationRecord.self, from: data),
           record.report.allowsEnablement
        {
            hops.append(
                DataFlowHop(
                    id: "companion",
                    host: record.serviceName,
                    transport: "Mac companion",
                    credential: DataFlowHop.pairing
                )
            )
        }
        #if !OHE_OBS25_SIZE_BASELINE
        if let data = try? Data(contentsOf: root.appendingPathComponent("otlp-destination.json")),
           let record = try? JSONDecoder().decode(OTLPDestinationRecord.self, from: data),
           let host = URL(string: record.urlString)?.host
        {
            hops.append(
                DataFlowHop(
                    id: "otlp",
                    host: host,
                    transport: "OTLP HTTP",
                    credential: DataFlowHop.noCredential
                )
            )
        }
        #endif
        return hops
    }

    static func dataFlowTypeCount() async -> Int {
        (try? await selectedMetrics())?.count ?? 0
    }

    private static func dataFlowHost(_ urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host, !host.isEmpty else {
            return urlString
        }
        if let port = url.port {
            return "\(host):\(port)"
        }
        return host
    }

    static func wipeInventory() async -> WipeInventory {
        let hops = dataFlowHops()
        let destinations = hops.filter { $0.id != "otlp" }
        let credentials = hops.filter {
            $0.credential != DataFlowHop.noNetwork
                && $0.credential != DataFlowHop.noCredential
        }
        guard let root = try? applicationSupportRoot() else {
            return WipeInventory(
                destinationCount: destinations.count,
                credentialCount: credentials.count
            )
        }
        let store: SQLiteStateStore
        do {
            store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
        } catch {
            return WipeInventory(
                destinationCount: destinations.count,
                credentialCount: credentials.count
            )
        }
        let pending = (try? await store.transact { try $0.pendingBatches() }) ?? []
        let journal = (try? await store.transact { try $0.loadJournal() }) ?? []
        let ledger = (try? await store.transact { try $0.loadLedger() }) ?? []
        return WipeInventory.build(
            destinationCount: destinations.count,
            credentialCount: credentials.count,
            pending: pending,
            journal: journal,
            ledger: ledger
        )
    }

    static func wakeLedger() throws -> WakeLedger {
        let root = try applicationSupportRoot()
        return WakeLedger(path: root.appendingPathComponent("wake-ledger.log").path)
    }

    @discardableResult
    static func observeAuthorizationChanges() async throws -> Bool {
        let root = try applicationSupportRoot()
        let metrics = try await selectedMetrics()
        guard !metrics.isEmpty else { return false }
        let grant = HealthAuthorizationGrant(
            id: "core-activity",
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

        let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
        for change in changes {
            for metric in change.grant.metrics {
                try await store.purgeType(
                    metric: metric,
                    reason: "authorization_revoked:\(change.grant.id)",
                    destination: "local-file",
                    atEpoch: change.observedAtEpoch
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

    static func reenableCoreActivityAfterAuthorizationRequest() async throws {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
        for metric in try await selectedMetrics() {
            try await store.reenableType(
                metric: metric,
                reason: "user_requested_core_activity"
            )
        }
    }

    static func startHealthObservers() async throws -> HealthKitObserverCoordinator {
        let coordinator = HealthKitObserverCoordinator(
            wakeLedger: try wakeLedger()
        )
        let metrics = try await selectedMetrics()
        guard !metrics.isEmpty else { return coordinator }
        try await coordinator.start(
            metrics: metrics
        ) { metric in
            try? await observeAuthorizationChanges()
            await ObserverExportGate.shared.enqueue(metric)
        }
        return coordinator
    }

    private static func companionTestReportURL(root: URL) -> URL {
        root.appendingPathComponent("companion-test.json")
    }

    private static func ledgerHeadSeal() -> any LedgerHeadSeal {
        resettableLedgerHeadSeal()
    }

    private static func resettableLedgerHeadSeal() -> any ResettableLedgerHeadSeal {
        #if targetEnvironment(simulator)
        SecureEnclaveLedgerSeal(useSecureEnclave: false, permanent: true)
        #else
        SecureEnclaveLedgerSeal()
        #endif
    }

    static func vault() throws -> PairingVault {
        let root = try applicationSupportRoot()
        return PairingVault(
            store: KeychainSecretStore(service: "app.openhealthexporter.ios.psk"),
            recordFile: root.appendingPathComponent("pairing.json")
        )
    }

    static func forgetCompanion() async throws {
        let root = try applicationSupportRoot()
        try await vault().forget()
        try? FileManager.default.removeItem(at: companionTestReportURL(root: root))
        let event = TrustEvent.trustLost
        if let snapshotURL = StatusSnapshotLocation.url(destinationID: "companion") {
            try DestinationSnapshotFile.recordSecurityEvents(
                1,
                destinationID: "companion",
                destinationLabel: "Mac companion",
                enabled: false,
                state: .blocked,
                writtenAtEpoch: Date().timeIntervalSince1970,
                at: snapshotURL
            )
        }
        try await emitTrustNotices([event], destination: "companion")
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
    }
}
