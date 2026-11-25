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
/// system side. Destination construction goes through AppDestinationSetup.
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

    var healthDestinationIDs: [String] { DestinationRepository.healthDestinationIDs }

    func plannedDestinations(trigger: RunTrigger) -> [String] {
        ExportPlan.destinations(
            for: trigger,
            among: healthDestinationIDs,
            isEnabled: destinations.isEnabled,
            allowsExport: destinations.allowsExport
        )
    }

    func destinationScope(_ destinationID: String) async throws -> DestinationExportScope {
        try await destinations.scope(destinationID)
    }

    func destinationLabel(_ destinationID: String) -> String {
        DestinationRepository.label(destinationID)
    }

    func synchronizeDestinationExportRole(_ destinationID: String) {
        destinations.synchronizeExportRole(destinationID)
    }

    func requestScopeAuthorizationIfConfigured(_ destinationID: String) async throws {
        try await AppHealth.service.requestReadAccess(for: try await destinationScope(destinationID))
    }

    func notifyIfFailed(
        _ kind: RunOutcome.Kind,
        destinationID: String,
        destinationLabel: String
    ) async {
        await status.notifyIfFailed(kind, destinationID: destinationID, destinationLabel: destinationLabel)
    }

    func rescheduleOverdueNotification(snapshotURL: URL) async {
        guard let snapshot = try? DestinationSnapshotFile.read(from: snapshotURL) else { return }
        await status.rescheduleOverdueNotification(for: snapshot)
    }

    func applyDestinationOutcomes(
        _ rows: [DestinationRunRow],
        to destinationIDs: [String]
    ) {
        outcomes.apply(rows, to: destinationIDs)
    }

    /// The one shared store for the process (#26).
    func stateStore(_ root: URL) throws -> SQLiteStateStore {
        try StateStoreHost.store(path: root.appendingPathComponent("state.sqlite").path)
    }

    func localExportFolder(root: URL) throws -> SecurityScopedAccess {
        try AppDestinations.folder.access(root: root)
    }

    func reloadStatusWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
    }

    // MARK: Destinations for a run

    func makeAutomaticRunDestination(
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
            let (verified, _) = try AppDestinationSetup.verifiedLocalFile(
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
            let (verified, emission) = try await AppDestinationSetup.verifiedHTTPS(
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
                    destination: try await AppDestinationSetup.verifiedMQTT(root: root),
                    scope: scope,
                    role: role,
                    snapshotURL: snapshotURL
                ),
                nil
            )
        case "companion":
            if trigger.attemptsCompanionTransport {
                let session = try await AppFiles.vault().load()
                let (verified, emission) = try await AppDestinationSetup.verifiedCompanion(
                    session: session,
                    onTestProgress: nil
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

    func drainPendingDeliveries(
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

    // MARK: Demo and single-destination runs

    /// Writes the sample dataset to its own folder under Application Support, never to
    /// the configured archive (#58). It needs no destination and no typed confirmation.
    func runDemoDataset(at date: Date = Date()) async throws -> [String] {
        let root = try AppFiles.applicationSupportRoot()
        let sqliteURL = root.appendingPathComponent("demo-state.sqlite")
        let dest = DemoExportLocation.directory(under: root)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let scratch = try AppFiles.protectedPayloadDirectory(named: "demo-scratch", under: root)
        let store = try StateStoreHost.store(path: sqliteURL.path)
        let (verified, events) = try AppDestinationSetup.verifiedLocalFile(destinationDirectory: dest)
        try await AppDestinationSetup.service.emitTrustNotices(events, destination: "local-file")
        let context = TemporalContext.utcHost
        let stamp = date.ISO8601Format()
        let exporterId = try AppFiles.installationID()
        var envelope = WireEnvelope(
            exporterId: exporterId,
            seq: 1,
            emittedAt: stamp,
            observedAt: stamp,
            demo: true
        )
        envelope.reason = "manual"
        let source = DemoSampleSource(seed: 1, samplesPerMetric: 4, now: date)
        let characteristics = DemoCharacteristicSource()
        var lines: [String] = [DemoCopy.banner]
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
        return lines
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
