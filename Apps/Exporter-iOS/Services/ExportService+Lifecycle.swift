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

/// Queue expiry, recovery, stops and holds, wakes and the wipe.
extension ExportService {
    func stopExportingHeartRate() async throws {
        let store = try stateStore(try AppFiles.applicationSupportRoot())
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
        let root = try AppFiles.applicationSupportRoot()
        let store = try stateStore(root)
        let now = Date().timeIntervalSince1970
        let enabled = healthDestinationIDs.filter { destinations.isEnabled($0) }
        let result = try await store.expirePending(
            nowEpoch: now,
            destination: ExportPlan.owedDestinationLabel(enabled)
        )
        guard result.expiredBatches > 0 else { return result }
        let entries = try await store.transact { try $0.loadLedger() }
        try await LedgerHeadSealRecordFile.update(
            entries: entries,
            seal: AppFiles.ledgerHeadSeal(),
            sealedAtEpoch: now,
            url: root.appendingPathComponent("ledger-head-seal.json")
        )
        _ = try await LocalUserNotifier().notify(
            UserNotice(
                kind: .queueExpired,
                destination: ExportPlan.expiryNoticeLabel(enabled.map(destinationLabel))
            )
        )
        return result
    }

    /// #63: the seven-day clock runs at launch, on foreground and on every background
    /// wake. A failure is recorded (#62) instead of discarded.
    func expireQueuesRecordingFailure(trigger: RunTrigger) async {
        do {
            _ = try await expireQueuesAndNotify()
            AppStatus.launchFailures.resolve(.queueExpiry)
        } catch {
            await AppStatus.launchFailures.record(.queueExpiry, error: error, trigger: trigger)
        }
    }

    func recoverInterruptedExportsRecordingFailure(trigger: RunTrigger) async {
        do {
            _ = try await recoverInterruptedExports()
            AppStatus.launchFailures.resolve(.interruptedRecovery)
        } catch {
            await AppStatus.launchFailures.record(.interruptedRecovery, error: error, trigger: trigger)
        }
    }

    /// UX-26: seal leftover open runs after process death, then tell the person.
    func recoverInterruptedExports() async throws -> String? {
        let store = try stateStore(try AppFiles.applicationSupportRoot())
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
        let store = try stateStore(try AppFiles.applicationSupportRoot())
        return try await store.transact { try $0.loadAnchorHolds() }
    }

    /// QA-17: the user chose to send the history again. Recording the decision is what
    /// releases the hold; the run reads it rather than inferring intent from a retry.
    func authoriseAnchorReexport(metric: MetricID) async throws {
        let store = try stateStore(try AppFiles.applicationSupportRoot())
        try await store.transact { tx in
            guard var hold = try tx.loadAnchorHold(metric: metric) else { return }
            hold.decision = .reexportAuthorized
            try tx.upsertAnchorHold(hold)
        }
    }

    /// QA-17's other answer: stop this type rather than pay to send its history again.
    func stopExportingHeldType(metric: MetricID) async throws {
        let store = try stateStore(try AppFiles.applicationSupportRoot())
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
        guard let root = try? AppFiles.applicationSupportRoot() else { return false }
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
        let root = try AppFiles.applicationSupportRoot()
        let store = try stateStore(root)
        try await DestructiveWipe.perform(
            store: store,
            secretStores: [
                KeychainSecretStore(service: IdentifierRoot.qualified("ios.psk")),
                KeychainSecretStore(service: IdentifierRoot.qualified("ios.https")),
                KeychainSecretStore(service: IdentifierRoot.qualified("ios.home-assistant")),
                KeychainSecretStore(service: IdentifierRoot.qualified("mqtt")),
            ],
            ledgerSeal: AppFiles.resettableLedgerHeadSeal(),
            ledgerSealURL: root.appendingPathComponent("ledger-head-seal.json"),
            atEpoch: Date().timeIntervalSince1970
        )
        try await AppFiles.vault().forget()
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
