// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppServices
import CoreDomain
import CorrectnessEngine
import DestinationTrust
import EnginePorts
import FileWriteKit
import Foundation
import NetEgress
import StorageSQLite
import Watchdog
import WidgetKit

// The saved verification records (HTTPSVerificationRecord, MQTTVerificationRecord,
// CompanionVerificationRecord) live in AppServices/DestinationSetupService.swift.

enum LocalExportFolderError: LocalizedError {
    case notSelected
    case inaccessible

    var errorDescription: String? {
        switch self {
        case .notSelected:
            "Choose an archive folder in Files before enabling local export."
        case .inaccessible:
            "The archive folder is no longer accessible. Choose it again in Files."
        }
    }
}

// MARK: Storage adapters

/// The JSON sidecars in Application Support.
struct DestinationRecordFiles: DestinationRecordStorage {
    let root: @Sendable () throws -> URL

    func verification(_ destinationID: String) -> DestinationVerificationSummary? {
        switch destinationID {
        case "local-file":
            return read(DestinationTestReport.self, .localFileTestReport).map {
                DestinationVerificationSummary(allowsEnablement: $0.allowsEnablement)
            }
        case "https", "home-assistant":
            return read(HTTPSVerificationRecord.self, .httpsRecord(destinationID: destinationID)).map {
                DestinationVerificationSummary(
                    allowsEnablement: $0.report.allowsEnablement,
                    propagateTraceparent: $0.propagateTraceparent ?? false,
                    bearer: $0.bearerDescriptor,
                    webhook: $0.webhookDescriptor
                )
            }
        case "mqtt":
            return read(MQTTVerificationRecord.self, .mqttRecord).map {
                DestinationVerificationSummary(
                    allowsEnablement: $0.report.allowsEnablement,
                    password: $0.passwordDescriptor,
                    pkcs12Password: $0.pkcs12PasswordDescriptor
                )
            }
        case "companion":
            return read(CompanionVerificationRecord.self, .companionTestReport).map {
                DestinationVerificationSummary(
                    allowsEnablement: $0.report.allowsEnablement,
                    propagateTraceparent: $0.propagateTraceparent ?? false
                )
            }
        default:
            return nil
        }
    }

    func setPropagateTraceparent(_ enabled: Bool, destinationID: String) throws {
        let root = try root()
        switch destinationID {
        case "https", "home-assistant":
            let url = DestinationSidecar.httpsRecord(destinationID: destinationID).url(in: root)
            guard let data = try? Data(contentsOf: url),
                  var record = try? JSONDecoder().decode(HTTPSVerificationRecord.self, from: data)
            else { return }
            record.propagateTraceparent = enabled
            try JSONEncoder().encode(record).write(to: url, options: .atomic)
        case "companion":
            let url = DestinationSidecar.companionTestReport.url(in: root)
            guard let data = try? Data(contentsOf: url),
                  var record = try? JSONDecoder().decode(CompanionVerificationRecord.self, from: data)
            else { return }
            record.propagateTraceparent = enabled
            try JSONEncoder().encode(record).write(to: url, options: .atomic)
        default:
            return
        }
    }

    func exists(_ sidecar: DestinationSidecar) -> Bool {
        guard let root = try? root() else { return false }
        return FileManager.default.fileExists(atPath: sidecar.url(in: root).path)
    }

    func remove(_ sidecar: DestinationSidecar) {
        guard let root = try? root() else { return }
        try? FileManager.default.removeItem(at: sidecar.url(in: root))
    }

    /// Moves a PKCS#12 password still held in the pre-Keychain JSON into the Keychain and
    /// rewrites the record without it; otherwise loads it from the Keychain if one is saved.
    func mqttPKCS12Password(
        from saved: MQTTVerificationRecord,
        root: URL
    ) async throws -> String? {
        let store = KeychainSecretStore(service: IdentifierRoot.qualified("mqtt"))
        let handle = SecretHandle(rawValue: "mqtt_pkcs12_password")
        if let leftover = saved.clientPKCS12Password, !leftover.isEmpty {
            try await store.store(Array(leftover.utf8), handle: handle)
            var migrated = saved
            migrated.clientPKCS12Password = nil
            migrated.hasClientPKCS12Password = true
            if migrated.pkcs12PasswordDescriptor == nil
                || migrated.pkcs12PasswordDescriptor?.appearance == .absent
            {
                migrated.pkcs12PasswordDescriptor = StoredCredentialDescriptor.capturing(
                    leftover,
                    appearance: .pkcs12Password,
                    addedOnDay: saved.firstSeen ?? ""
                )
            }
            try JSONEncoder().encode(migrated).write(
                to: DestinationSidecar.mqttRecord.url(in: root),
                options: .atomic
            )
            return leftover
        }
        if saved.hasClientPKCS12Password == true {
            return String(decoding: try await store.load(handle), as: UTF8.self)
        }
        return nil
    }

    private func read<T: Decodable>(_ type: T.Type, _ sidecar: DestinationSidecar) -> T? {
        guard let root = try? root(),
              let data = try? Data(contentsOf: sidecar.url(in: root))
        else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// Per-destination switches in the app's preferences (keys in SettingsStore).
struct PreferencesDestinationSettings: DestinationPreferenceStorage {
    func exportRole(_ destinationID: String) -> String? {
        UserDefaults.standard.string(forKey: SettingsStore.exportRoleKey(destinationID))
    }

    func setExportRole(_ rawValue: String, destinationID: String) {
        UserDefaults.standard.set(rawValue, forKey: SettingsStore.exportRoleKey(destinationID))
    }

    func allowsMeteredNetwork(_ destinationID: String) -> Bool {
        UserDefaults.standard.bool(forKey: SettingsStore.allowsMeteredNetworkKey(destinationID))
    }

    func companionPropagatesTraceparent() -> Bool {
        UserDefaults.standard.bool(forKey: SettingKey.companionPropagateTraceparent.rawValue)
    }

    func setCompanionPropagatesTraceparent(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: SettingKey.companionPropagateTraceparent.rawValue)
    }
}

/// The widget's status snapshots in the shared container.
struct WidgetDestinationSnapshots: DestinationSnapshotStorage {
    func exportRole(_ destinationID: String) -> DestinationExportRole? {
        guard let url = StatusSnapshotLocation.url(destinationID: destinationID),
              let snapshot = try? DestinationSnapshotFile.read(from: url)
        else { return nil }
        return snapshot.exportRole
    }

    func applyExportRole(_ role: DestinationExportRole, destinationID: String, at now: Date) throws {
        guard let url = StatusSnapshotLocation.url(destinationID: destinationID),
              var snapshot = try? DestinationSnapshotFile.read(from: url)
        else { return }
        snapshot.applyExportRole(role)
        snapshot.writtenAtEpoch = now.timeIntervalSince1970
        try DestinationSnapshotFile.write(snapshot, to: url)
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
    }
}

/// Scopes in the state store.
struct StateStoreDestinationScopes: DestinationScopeStorage {
    let root: @Sendable () throws -> URL

    func loadScope(_ destinationID: String) async throws -> DestinationExportScope? {
        try await store().transact { tx in
            try tx.loadDestinationScope(destinationID: destinationID)
        }
    }

    func saveScope(_ scope: DestinationExportScope) async throws {
        try await store().transact { try $0.upsertDestinationScope(scope) }
    }

    func reenable(_ metric: MetricID, reason: String) async throws {
        try await store().reenableType(metric: metric, reason: reason)
    }

    private func store() throws -> SQLiteStateStore {
        try StateStoreHost.store(path: root().appendingPathComponent("state.sqlite").path)
    }
}

/// The picked archive folder as a security-scoped bookmark.
struct BookmarkedExportFolder: LocalExportFolderStorage {
    let root: @Sendable () throws -> URL

    func saveFolder(_ url: URL) throws {
        let root = try root()
        let bookmark = try SecurityScopedBookmark.create(from: url)
        try FileWriteKit.writeAtomically(
            bookmark,
            to: DestinationSidecar.localFolderBookmark.url(in: root)
        )
    }

    func accessibleFolderName() -> String? {
        guard let root = try? root(), let access = try? access(root: root) else { return nil }
        return access.url.lastPathComponent
    }

    /// Opens the folder for writing, refreshing a stale bookmark on the way.
    func access(root: URL) throws -> SecurityScopedAccess {
        let bookmarkURL = DestinationSidecar.localFolderBookmark.url(in: root)
        guard let bookmark = try? Data(contentsOf: bookmarkURL) else {
            throw LocalExportFolderError.notSelected
        }
        let resolved = try SecurityScopedBookmark.resolve(bookmark)
        let access: SecurityScopedAccess
        #if DEBUG
        // A seeded folder lives inside the app container and therefore has no scope to
        // start. Narrowed to that case so a genuinely inaccessible picked folder still
        // reports as inaccessible in DEBUG builds.
        if resolved.url.path.hasPrefix(root.path) {
            access = SecurityScopedAccess.unscoped(url: resolved.url)
        } else {
            do {
                access = try SecurityScopedAccess(url: resolved.url)
            } catch {
                throw LocalExportFolderError.inaccessible
            }
        }
        #else
        do {
            access = try SecurityScopedAccess(url: resolved.url)
        } catch {
            throw LocalExportFolderError.inaccessible
        }
        #endif
        if resolved.isStale {
            let refreshed = try SecurityScopedBookmark.create(
                fromAccessibleURL: access.url
            )
            try FileWriteKit.writeAtomically(refreshed, to: bookmarkURL)
        }
        return access
    }
}

enum AppDestinations {
    private static let root: @Sendable () throws -> URL = { try HarnessExport.applicationSupportRoot() }

    static let records = DestinationRecordFiles(root: root)
    static let folder = BookmarkedExportFolder(root: root)
    static let repository = DestinationRepository(
        records: records,
        preferences: PreferencesDestinationSettings(),
        snapshots: WidgetDestinationSnapshots(),
        scopes: StateStoreDestinationScopes(root: root),
        folder: folder,
        now: { Date() },
        // #68: automatic runs need the unlock; manual export never does.
        unlockState: { PurchaseStore.cachedState() }
    )
}
