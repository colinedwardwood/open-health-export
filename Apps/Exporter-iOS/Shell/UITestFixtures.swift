// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CompanionReceive
import CoreDomain
import FileWriteKit
import Foundation
import NetEgress
import Watchdog

#if DEBUG
/// Launch-environment hooks for UI tests, gathered in one place so they can move
/// behind a UI_TESTING build configuration without touching the screens (#43).
enum UITestFixtures {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// `OHE_RESET_FIRST_RUN=1` clears the disclosure acknowledgement so first run
    /// starts again. A launch argument can't do this: it lands in the read-only
    /// argument domain, where first run's own write would never take effect.
    static func applyLaunchResets() {
        // Destinations and reports survive across cases in one simulator; the harness
        // applies the same reset when it is the root.
        if environment["OHE_RESET_SEEDED_SURFACES"] == "1" {
            try? UITestFixtures.resetSeededSurfaces()
        }
        // `OHE_SEED_DESTINATION_STATUS=<scenario>`: destination snapshots for Status,
        // the same fixtures the harness cases use.
        if let scenario = environment["OHE_SEED_DESTINATION_STATUS"] {
            try? UITestFixtures.seedDestinationStatus(scenario: scenario)
        }
        if seedsICloudFolder {
            ICloudFolderAcknowledgement.app.clear()
        }
        if environment["OHE_RESET_FIRST_RUN"] == "1" {
            UserDefaults.standard.removeObject(forKey: SettingKey.disclosureAcknowledged.rawValue)
        }
    }

    /// `OHE_SEED_LOCAL_EXPORT_FOLDER=1`: first run uses a seeded folder in place of
    /// the Files picker, which UI tests can't drive.
    static var seedsLocalExportFolder: Bool {
        environment["OHE_SEED_LOCAL_EXPORT_FOLDER"] == "1"
    }

    /// `OHE_FAIL_DATA_SAVE=1`: saving the Data screen's types fails, so UI tests reach
    /// its error without a broken database.
    static var failsDataSave: Bool {
        environment["OHE_FAIL_DATA_SAVE"] == "1"
    }

    struct InjectedFailure: Error {}

    /// `OHE_SEED_ICLOUD_FOLDER=1`: the folder button offers a folder whose path is under
    /// `Mobile Documents`, as iCloud Drive's is, so UI tests reach the iCloud warning
    /// without the Files picker. It lives in the app container, which needs no scope.
    static var seedsICloudFolder: Bool {
        environment["OHE_SEED_ICLOUD_FOLDER"] == "1"
    }

    static func iCloudFixtureFolder() throws -> URL {
        let folder = try AppFiles.applicationSupportRoot()
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/ohe-icloud-fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Saves a fixture folder the way the picker would, without a security scope.
    static func chooseFixtureFolder(_ url: URL) throws -> String {
        try AppDestinations.folder.saveUnscopedFolder(url)
        AppDestinations.records.remove(.localFileTestReport)
        return url.lastPathComponent
    }

    /// `OHE_UNLOCK_STATE=locked|unlocked|revoked|sourceBuild` forces the unlock state
    /// (#68), so UI tests cover each without a StoreKit sandbox.
    nonisolated static var unlockState: UnlockState? {
        ProcessInfo.processInfo.environment["OHE_UNLOCK_STATE"].flatMap(UnlockState.init(rawValue:))
    }

    /// `OHE_OPEN_URL` is delivered through the same router a tapped notification uses.
    @MainActor
    static func applyOpenURL(to model: AppModel) {
        if let raw = environment["OHE_OPEN_URL"], let url = URL(string: raw) {
            model.route(url)
        }
    }

    // MARK: Seeds

    /// Each case starts from the shipped advisory defaults, an empty network ledger and
    /// no destination records, so a default-configuration case sees what a new install
    /// sees. Snapshot files and destination reports survive across cases in one
    /// simulator; leaving them would put a prior case's banners and hops on this one.
    static func resetSeededSurfaces() throws {
        for key in [
            SettingKey.advisoryEnabled.rawValue,
            SettingKey.advisoryLastAttemptEpoch.rawValue,
            SettingKey.advisoryLastVerifiedEpoch.rawValue,
            SettingKey.advisoryLastSeenSeq.rawValue,
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        EgressAttemptLog.wipePersistent()
        if let directory = StatusSnapshotLocation.directory() {
            try? FileManager.default.removeItem(at: directory)
        }
        for destinationID in DestinationRepository.healthDestinationIDs {
            UserDefaults.standard.removeObject(forKey: SettingsStore.exportRoleKey(destinationID))
        }
        if let root = try? AppFiles.applicationSupportRoot() {
            for name in [
                "local-file-test.json",
                "local-export-folder.bookmark",
                "https-destination.json",
                "home-assistant-destination.json",
                "mqtt-destination.json",
                "mqtt-client.p12",
                "otlp-destination.json",
                "companion-test.json",
                "pairing.json",
                "imported-destination-drafts.json",
            ] {
                try? FileManager.default.removeItem(at: root.appendingPathComponent(name))
            }
        }
    }

    /// Reaching success, stale and failed for real needs a destination, a network and a
    /// clock that has moved on by days, none of which a UI test has. Seeding the
    /// snapshot exercises the same read path the app uses in the field.
    static func seedDestinationStatus(scenario: String) throws {
        let now = Date().timeIntervalSince1970
        for snapshot in DestinationStatusUIFixtures.snapshots(scenario: scenario, nowEpoch: now) {
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
    }

    /// The only way to get a configured archive folder in the product is the Files
    /// picker, which XCUITest cannot drive. This seeds a real directory inside the app
    /// container and records a real bookmark for it, so everything past folder selection
    /// is the production path.
    static func seedLocalExportFolder() throws -> String {
        let root = try AppFiles.applicationSupportRoot()
        let folder = root.appendingPathComponent("seeded-archive", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bookmark = try SecurityScopedBookmark.create(fromAccessibleURL: folder)
        try FileWriteKit.writeAtomically(bookmark, to: DestinationSidecar.localFolderBookmark.url(in: root))
        try? FileManager.default.removeItem(at: DestinationSidecar.localFileTestReport.url(in: root))
        return folder.lastPathComponent
    }
}
#endif
