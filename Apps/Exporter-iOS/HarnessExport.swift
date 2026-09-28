// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppServices
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
    var destinationID: String
    var destinationLabel: String
    var host: String
    var allowedHosts: [String]
    var allowInsecureHTTP: Bool
    var bearer: String?
    var webhookID: String?
    var persistedURLString: String?
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

/// Internal (not private) so DestinationRecordFiles in Services/AppDestinations.swift can read it.
struct MQTTVerificationRecord: Codable {
    var urlString: String
    var allowedHosts: [String]
    var allowInsecure: Bool
    var clientID: String
    var topic: String
    var qos: UInt8?
    var report: DestinationTestReport
    var hasClientPKCS12: Bool?
    var hasClientPKCS12Password: Bool?
    /// Pre-Keychain JSON copies. Read on launch, then rewritten off disk.
    var clientPKCS12Password: String?
    var username: String?
    var hasPassword: Bool?
    var passwordDescriptor: StoredCredentialDescriptor?
    var pkcs12PasswordDescriptor: StoredCredentialDescriptor?
    var leafSPKISha256: String?
    var issuerSPKISha256: String?
    var firstSeen: String?
    var importedLocalIdentifier: String?
}

enum HarnessExport {
    static let healthDestinationIDs = [
        "local-file", "https", "home-assistant", "mqtt", "companion",
    ]

    /// UX-29: the 413 shorten-window action writes `ohe.exportWindowHours`; HealthKit
    /// pages follow that owned setting so the next batch is smaller.
    // #42: forwarder; remove when the product UI calls the service.
    static func samplePageLimit() -> Int { AppExport.service.samplePageLimit() }

    // #42: forwarder; remove when the product UI calls the service.
    static func gzipLevel() -> Int32 { AppExport.service.gzipLevel() }

    // #42: forwarder; remove when the product UI calls the service.
    static func withThermalCompression<T>(
        _ body: () async throws -> T
    ) async rethrows -> T {
        try await AppExport.service.withThermalCompression(body)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func freshnessCadenceSeconds() -> TimeInterval { AppExport.service.freshnessCadenceSeconds() }

    // #42: forwarder; remove when the product UI calls the service.
    static func isLowPowerDeferred() -> Bool { AppExport.service.isLowPowerDeferred() }

    // #42: forwarder; remove when the product UI calls the service.
    static func isThermalDeferred() -> Bool { AppExport.service.isThermalDeferred() }

    // #42: forwarder; remove when the product UI calls the service.
    static func allowsMeteredNetwork(destinationID: String) -> Bool {
        AppDestinations.repository.allowsMeteredNetwork(destinationID)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func networkPathConditions() -> NetworkPathConditions { AppExport.service.networkPathConditions() }

    // #42: forwarder; remove when the product UI calls the service.
    static func attachNetworkActivityLedger() {
        AppStatus.transparency.attachNetworkActivityLedger()
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func networkActivityLines() -> [String] {
        AppStatus.transparency.networkActivityLines()
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func buildProvenanceLines() -> [String] {
        AppStatus.transparency.buildProvenanceLines()
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func destinationScope(_ destinationID: String) async throws -> DestinationExportScope {
        try await AppDestinations.repository.scope(destinationID)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func destinationScopes() async throws -> [DestinationExportScope] {
        try await AppDestinations.repository.allScopes()
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func selectedMetrics() async throws -> [MetricID] {
        try await AppDestinations.repository.selectedMetrics()
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func isDestinationEnabled(_ destinationID: String) -> Bool {
        AppDestinations.repository.isEnabled(destinationID)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func destinationExportRole(_ destinationID: String) -> DestinationExportRole {
        AppDestinations.repository.exportRole(destinationID)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func allowsExport(_ destinationID: String, trigger: RunTrigger) -> Bool {
        AppDestinations.repository.allowsExport(destinationID, trigger: trigger)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func hasAutomaticExport(trigger: RunTrigger) -> Bool {
        AppDestinations.repository.hasAutomaticExport(trigger: trigger)
    }

    // #42: forwarder; remove when the product UI calls the service.
    private static func destinationLabel(_ destinationID: String) -> String {
        DestinationRepository.label(destinationID)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func setDestinationExportRole(
        _ role: DestinationExportRole,
        destinationID: String
    ) throws {
        try AppDestinations.repository.setExportRole(role, destinationID: destinationID)
    }

    // #42: forwarder; remove when the product UI calls the service.
    private static func synchronizeDestinationExportRole(_ destinationID: String) {
        AppDestinations.repository.synchronizeExportRole(destinationID)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func synchronizeDestinationExportRoles() {
        AppDestinations.repository.synchronizeExportRoles()
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func hasDestinationConfiguration(_ destinationID: String) -> Bool {
        AppDestinations.repository.hasConfiguration(destinationID)
    }

    // #42: forwarder; remove when the product UI calls the service.
    private static func requestScopeAuthorizationIfConfigured(_ destinationID: String) async throws { try await AppHealth.service.requestReadAccess(for: try await destinationScope(destinationID)) }

    // #42: forwarder; remove when the product UI calls the service.
    static func saveDestinationScope(_ scope: DestinationExportScope) async throws {
        try await AppDestinations.repository.saveScope(scope)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func applyDestinationScope(
        _ scope: DestinationExportScope,
        previousMetrics: Set<MetricID>
    ) async throws {
        try await AppDestinations.repository.applyScope(scope, previousMetrics: previousMetrics)
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

    // #42: forwarder; remove when the product UI calls the service.
    static func deferWakeIfMigrationPending(trigger: RunTrigger) -> Bool { AppExport.service.deferWakeIfMigrationPending(trigger: trigger) }

    // #42: forwarder; remove when the product UI calls the service.
    static func runOnePageEachMetric(
        metrics: [MetricID]? = nil,
        trigger: RunTrigger = .manual,
        onProgress: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> [String] {
        try await AppExport.service.runOnePageEachMetric(metrics: metrics, trigger: trigger, onProgress: onProgress)
    }

    // #42: forwarder; remove when the product UI calls the service.
    private static func rescheduleOverdueNotification(snapshotURL: URL) async {
        guard let snapshot = try? DestinationSnapshotFile.read(from: snapshotURL) else { return }
        await AppStatus.status.rescheduleOverdueNotification(for: snapshot)
    }

    // #42: forwarder; remove when the product UI calls the service.
    private static func notifyIfFailed(
        _ kind: RunOutcome.Kind,
        destinationID: String,
        destinationLabel: String
    ) async {
        await AppStatus.status.notifyIfFailed(kind, destinationID: destinationID, destinationLabel: destinationLabel)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func applyBackfillOutcomes(
        _ rows: [DestinationRunRow],
        to destinationIDs: [String]
    ) {
        AppExport.service.applyBackfillOutcomes(rows, to: destinationIDs)
    }

    /// Marks one destination's own status as failed, for the case where the run
    /// never reached it: its last outcome must not inherit the combined result of
    /// the destinations that did run.
    // #42: forwarder; remove when the product UI calls the service.
    private static func recordDestinationFailureSnapshot(
        _ destinationID: String,
        errorClass: ErrorClass
    ) {
        AppStatus.status.recordDestinationFailureSnapshot(destinationID, errorClass: errorClass)
    }

    /// A run that threw before any destination could report for itself. Naming the
    /// archive folder here was a guess: it told users the wrong destination had
    /// failed, and told them anything at all when that folder was not even enabled.
    /// One notice still goes out, against the destination that has evidence of the
    /// failure, or the first one this trigger was allowed to use. Returns the label
    /// that notice used, so on-screen text can say the same thing.
    @discardableResult
    // #42: forwarder; remove when the product UI calls the service.
    static func notifyRunFailure(trigger: RunTrigger) async -> String? {
        await AppStatus.status.notifyRunFailure(
            planned: healthDestinationIDs.filter { isDestinationEnabled($0) && allowsExport($0, trigger: trigger) },
            label: destinationLabel
        )
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func notifyDestinationFailure(
        destinationID: String,
        destinationLabel: String
    ) async {
        await AppStatus.status.notifyDestinationFailure(destinationID: destinationID, destinationLabel: destinationLabel)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func runFullReconcile(
        metrics: [MetricID]? = nil,
        trigger: RunTrigger = .manual,
        onProgress: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> [String] {
        try await AppExport.service.runFullReconcile(metrics: metrics, trigger: trigger, onProgress: onProgress)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func runBackfill(
        mode: BackfillMode,
        onProgress: (@Sendable (String) async -> Void)? = nil
    ) async throws -> [String] {
        try await AppExport.service.runBackfill(mode: mode, onProgress: onProgress)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func queueEvictionGaps() async throws -> [GapRecord] { try await AppExport.service.queueEvictionGaps() }

    // #42: forwarder; remove when the product UI calls the service.
    static func recordNotificationSuppressionIfNeeded() async throws {
        try await AppStatus.status.recordNotificationSuppressionIfNeeded(forcedDenied: AppStatus.seededNotificationsDenied)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func reExportQueueGap(_ gap: GapRecord) async throws -> RunOutcome.Kind { try await AppExport.service.reExportQueueGap(gap) }

    // #42: forwarder; remove when the product UI calls the service.
    static func runDemoDataset(typedDestinationName: String) async throws -> [String] {
        try await AppExport.service.runDemoDataset(typedDestinationName: typedDestinationName)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func runCompanion(
        session: PairingSession,
        onTestProgress: DestinationTestProgress? = nil,
        onProgress: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> [String] {
        try await AppExport.service.runCompanion(session: session, onTestProgress: onTestProgress, onProgress: onProgress)
    }

    static func applicationSupportRoot() throws -> URL {
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
    // #42: forwarder; remove when the product UI calls the service.
    static func diagnosticBundle(
        minimumRuns: Int = 30,
        windowHours: Int = 24
    ) throws -> (preview: String, payload: Data) {
        try AppStatus.transparency.diagnosticBundle(environment: AppStatus.diagnosticEnvironment(), minimumRuns: minimumRuns, windowHours: windowHours)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func destinationStatusLines() -> [String] {
        AppStatus.status.destinationStatusLines()
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func freshnessDisclosureLines() -> [(id: String, text: String)] {
        AppStatus.status.freshnessDisclosureLines()
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func destinationChangeBannerDetail() -> String? {
        AppStatus.status.destinationChangeBannerDetail()
    }

    /// QA-15 / R-23: the in-app rung. Staleness is computed at read time, so a destination
    /// that succeeded once and then went quiet still surfaces without a server.
    // #42: forwarder; remove when the product UI calls the service.
    static func overdueBannerDetail() -> String? {
        AppStatus.status.overdueBannerDetail()
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func anchorHolds() async throws -> [AnchorHold] { try await AppExport.service.anchorHolds() }

    // #42: forwarder; remove when the product UI calls the service.
    static func authoriseAnchorReexport(metric: MetricID) async throws { try await AppExport.service.authoriseAnchorReexport(metric: metric) }

    // #42: forwarder; remove when the product UI calls the service.
    static func stopExportingHeldType(metric: MetricID) async throws { try await AppExport.service.stopExportingHeldType(metric: metric) }

    #if DEBUG
    /// Snapshot files and hold rows survive across XCUITest cases in one simulator.
    /// Resetting them at launch is what keeps one case's banners off the next audit.
    /// R-114's demo quickstart needs a configured archive folder, and the only way to get
    /// one in the product is the Files picker, which XCUITest cannot drive. Without this
    /// the quickstart test could never reach the export at all: it failed on
    /// `LocalExportFolderError.notSelected` in milliseconds and then sat waiting out its
    /// ten-minute budget, so the budget it exists to prove was never measured.
    ///
    /// Seeds a real directory inside the app container and records a real bookmark for it,
    /// so everything past folder selection is the production path.
    static func seedLocalExportFolderForUITests() throws -> String {
        let root = try applicationSupportRoot()
        let folder = root.appendingPathComponent("seeded-archive", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bookmark = try SecurityScopedBookmark.create(fromAccessibleURL: folder)
        try FileWriteKit.writeAtomically(bookmark, to: localExportFolderBookmarkURL(root: root))
        try? FileManager.default.removeItem(at: localFileTestReportURL(root: root))
        return folder.lastPathComponent
    }

    static func resetSeededSurfacesForUITests() throws {
        // Each case starts from the shipped advisory defaults and an empty network
        // ledger, so a default-configuration case sees what a new install sees.
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
        for destinationID in healthDestinationIDs {
            UserDefaults.standard.removeObject(
                forKey: SettingsStore.exportRoleKey(destinationID)
            )
        }
        // Destination reports survive across XCUITest cases in one simulator.
        // Leaving them would put hops on first-run disclosure after a prior case
        // enabled local-file.
        if let root = try? applicationSupportRoot() {
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

    static func clearAnchorHoldsForUITests() async throws {
        let root = try applicationSupportRoot()
        let store = try StateStoreHost.store(path: root.appendingPathComponent("state.sqlite").path)
        try await store.transact { tx in
            for hold in try tx.loadAnchorHolds() {
                try tx.clearAnchorHold(metric: hold.metric)
            }
        }
    }

    /// QA-14 wants the success, stale and failed surfaces asserted. Reaching them for
    /// real needs a destination, a network and a clock that has moved on by days, none
    /// of which a UI test has. Seeding the snapshot exercises the same read path the
    /// app uses in the field.
    static func seedDestinationStatusForUITests(scenario: String) throws {
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

    /// A hold can only arise from state the simulator has no way to produce — a cursor
    /// that went missing behind a real HealthKit history. Seeding one is the only way a
    /// UI test can assert what the user sees when it happens.
    static func seedAnchorHoldForUITests(metric: MetricID) async throws {
        let root = try applicationSupportRoot()
        let store = try StateStoreHost.store(path: root.appendingPathComponent("state.sqlite").path)
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

    // #42: forwarder; remove when the product UI calls the service.
    static func ledgerLines() async throws -> [String] {
        try await AppStatus.history.ledgerLines()
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func ledgerIntegrityLine() async throws -> String {
        try await AppStatus.history.ledgerIntegrityLine()
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func historyEvents() async throws -> [RunEvent] {
        try await AppStatus.history.historyEvents()
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func historyLines() async throws -> [String] {
        try await AppStatus.history.historyLines()
    }

    #if DEBUG
    static func prepareHistoryPayloadSeedForUITests() async throws {
        let root = try applicationSupportRoot()
        let payloadURL = root
            .appendingPathComponent("history-payloads", isDirectory: true)
            .appendingPathComponent("ui-seed.ndjson")
        try FileManager.default.createDirectory(
            at: payloadURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let body = "{\"uuid\":\"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa\"}\n"
        try Data(body.utf8).write(to: payloadURL)
        let store = try StateStoreHost.store(path: root.appendingPathComponent("state.sqlite").path)
        let event = RunEvent(
            runID: RunID(rawValue: "run-heartRate"),
            outcomeKind: "failed",
            detail: "destinationUnreachable",
            trigger: .shortcut,
            samplesRead: 4,
            samplesCommitted: 4,
            samplesAcked: 0,
            wallTimeEpoch: Date().timeIntervalSince1970,
            errorClass: "destinationUnreachable",
            facts: RunHistoryFacts(
                destinationID: "https",
                metric: "heartRate",
                windowStartDay: "2026-01-01",
                windowEndDay: "2026-01-02",
                byteCount: body.utf8.count,
                durationMillis: 40,
                payloadSHA256: "seed",
                redactedPayload: RunHistoryDetail.redactedPayload(
                    metric: "heartRate",
                    records: 4,
                    byteCount: body.utf8.count,
                    windowStartDay: "2026-01-01",
                    windowEndDay: "2026-01-02"
                ),
                payloadPath: payloadURL.path
            )
        )
        try await store.transact { try $0.appendJournal(event) }
    }
    #endif

    // #42: forwarder; remove when the product UI calls the service.
    static func sentThroughDay(metric: MetricID) async throws -> String? {
        try await AppStatus.history.sentThroughDay(metric: metric)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func indexHorizonDay() async throws -> String? {
        try await AppStatus.history.indexHorizonDay()
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func wakeAttributionLine() async throws -> String {
        try await AppStatus.status.wakeAttributionLine()
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func acknowledgeDestinationChanges() throws {
        try AppStatus.status.acknowledgeDestinationChanges()
    }

    // #42: forwarder; remove when the product UI calls the service.
    private static func httpsDestinationRecordURL(
        root: URL,
        destinationID: String
    ) -> URL {
        DestinationSidecar.httpsRecord(destinationID: destinationID).url(in: root)
    }

    // #42: forwarder; remove when the product UI calls the service.
    private static func httpsKeychainService(_ destinationID: String) -> String {
        DestinationRepository.keychainService(destinationID)
    }

    static func prepareHomeAssistantWebhook(
        baseURLString: String,
        webhookID: String,
        allowInsecureHTTP: Bool,
        importedLocalIdentifier: String? = nil,
        confirmedLeafSPKISha256: String? = nil,
        onProgress: DestinationTestProgress? = nil
    ) async throws -> DestinationConfirmationCard {
        let endpoint = try HomeAssistantWebhookPreset.endpoint(
            baseURLString: baseURLString,
            webhookID: webhookID
        )
        return try await prepareHTTPSDestination(
            urlString: endpoint.absoluteString,
            allowInsecureHTTP: allowInsecureHTTP,
            bearer: nil,
            destinationID: "home-assistant",
            destinationLabel: "Home Assistant",
            webhookID: webhookID,
            persistedURLString:
                try HomeAssistantWebhookPreset.baseURL(
                    from: endpoint
                ).absoluteString,
            importedLocalIdentifier: importedLocalIdentifier,
            confirmedLeafSPKISha256: confirmedLeafSPKISha256,
            onProgress: onProgress
        )
    }

    static func prepareHTTPSDestination(
        urlString: String,
        allowInsecureHTTP: Bool,
        bearer: String?,
        destinationID: String = "https",
        destinationLabel: String = "HTTPS destination",
        webhookID: String? = nil,
        persistedURLString: String? = nil,
        importedLocalIdentifier: String? = nil,
        confirmedLeafSPKISha256: String? = nil,
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
                meteredPolicy: .fromAllowsMetered(
                    allowsMeteredNetwork(destinationID: destinationID)
                ),
                pathConditions: networkPathConditions(),
                confirmedLeafSPKISha256: confirmedLeafSPKISha256,
                onProgress: onProgress
            )
        }
        await PendingDestination.shared.setHTTPS(PendingHTTPS(
            probe: probe,
            destinationID: destinationID,
            destinationLabel: destinationLabel,
            host: host,
            allowedHosts: allowedHosts.sorted(),
            allowInsecureHTTP: allowInsecureHTTP,
            bearer: bearer,
            webhookID: webhookID,
            persistedURLString: persistedURLString,
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
        guard let pending = await PendingDestination.shared.takeHTTPS() else {
            throw SetupError.verificationRequired
        }
        try ExportScopeGate.requireConfigured(
            try await destinationScope(pending.destinationID)
        )
        let probe = pending.probe
        let events = probe.pendingEvents + [.destinationEnabled]
        let record = HTTPSVerificationRecord(
            urlString:
                pending.persistedURLString
                    ?? probe.destination.url.absoluteString,
            allowedHosts: pending.allowedHosts,
            allowInsecureHTTP: pending.allowInsecureHTTP,
            report: probe.report,
            leafSPKISha256: probe.identity?.leafSPKISha256,
            issuerSPKISha256: probe.identity?.issuerSPKISha256,
            firstSeen: pending.firstSeen,
            hasBearer: pending.bearer != nil,
            bearerDescriptor: StoredCredentialDescriptor.capturing(
                pending.bearer,
                appearance: .bearerToken,
                addedOnDay: pending.firstSeen
            ),
            webhookDescriptor: StoredCredentialDescriptor.capturing(
                pending.webhookID,
                appearance: .webhookID,
                addedOnDay: pending.firstSeen
            ),
            propagateTraceparent: propagateTraceparent,
            importedLocalIdentifier: pending.importedLocalIdentifier
        )
        let root = try applicationSupportRoot()
        let bearerStore = KeychainSecretStore(
            service: httpsKeychainService(pending.destinationID)
        )
        let bearerHandle = SecretHandle(rawValue: "bearer")
        if let bearer = pending.bearer {
            try await bearerStore.store(Array(bearer.utf8), handle: bearerHandle)
        } else {
            try? await bearerStore.delete(bearerHandle)
        }
        let webhookHandle = SecretHandle(rawValue: "webhook-id")
        if let webhookID = pending.webhookID {
            try await bearerStore.store(
                Array(webhookID.utf8),
                handle: webhookHandle
            )
        } else {
            try? await bearerStore.delete(webhookHandle)
        }
        try JSONEncoder().encode(record).write(
            to: httpsDestinationRecordURL(
                root: root,
                destinationID: pending.destinationID
            ),
            options: .atomic
        )
        if let snapshotURL = StatusSnapshotLocation.url(
            destinationID: pending.destinationID
        ) {
            try DestinationSnapshotFile.recordSecurityEvents(
                events.count,
                destinationID: pending.destinationID,
                destinationLabel: pending.destinationLabel,
                writtenAtEpoch: Date().timeIntervalSince1970,
                at: snapshotURL
            )
        }
        try await emitTrustNotices(events, destination: pending.destinationLabel)
        try await requestScopeAuthorizationIfConfigured(pending.destinationID)
        if pending.allowInsecureHTTP {
            let store = try StateStoreHost.store(path: root.appendingPathComponent("state.sqlite").path)
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
        confirmedIdentity: TLSIdentity? = nil,
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
        let now = Date().ISO8601Format()
        // #66: the first attempt may only read the broker's certificate. Once the person
        // has confirmed an untrusted one, the retry is pinned to exactly that certificate.
        let sink: MQTTSink
        if let confirmedIdentity {
            sink = try MQTTSink.overNetwork(
                destination: destination,
                pin: PinRecord(
                    leafSPKISha256: confirmedIdentity.leafSPKISha256,
                    issuerSPKISha256: confirmedIdentity.issuerSPKISha256,
                    firstSeen: now,
                    policy: .leaf
                )
            )
        } else {
            sink = try MQTTSink.overNetwork(
                destination: destination,
                pin: nil,
                capturesUntrustedIdentity: true
            )
        }
        let probe = try await MQTTDestinationEnable.probe(
            destination: destination,
            pipe: sink.pipe,
            exporterID: try installationID(),
            emittedAt: now,
            meteredPolicy: .fromAllowsMetered(allowsMeteredNetwork(destinationID: "mqtt")),
            pathConditions: networkPathConditions(),
            confirmedLeafSPKISha256: confirmedIdentity?.leafSPKISha256,
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
            hasClientPKCS12Password: pending.clientPKCS12Password != nil,
            clientPKCS12Password: nil,
            username: pending.username,
            hasPassword: pending.password != nil,
            passwordDescriptor: StoredCredentialDescriptor.capturing(
                pending.password,
                appearance: .password,
                addedOnDay: pending.firstSeen
            ),
            pkcs12PasswordDescriptor: StoredCredentialDescriptor.capturing(
                pending.clientPKCS12Password,
                appearance: .pkcs12Password,
                addedOnDay: pending.firstSeen
            ),
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
            service: IdentifierRoot.qualified("mqtt")
        )
        let passwordHandle = SecretHandle(rawValue: "mqtt_password")
        if let password = pending.password {
            try await passwordStore.store(Array(password.utf8), handle: passwordHandle)
        } else {
            try? await passwordStore.delete(passwordHandle)
        }
        let pkcs12PasswordHandle = SecretHandle(rawValue: "mqtt_pkcs12_password")
        if let pkcs12Password = pending.clientPKCS12Password {
            try await passwordStore.store(Array(pkcs12Password.utf8), handle: pkcs12PasswordHandle)
        } else {
            try? await passwordStore.delete(pkcs12PasswordHandle)
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
            let store = try StateStoreHost.store(path: root.appendingPathComponent("state.sqlite").path)
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

    // #42: forwarder; remove when the product UI calls the service.
    static func storedCredentialSummaries() -> (
        httpsBearer: String?,
        homeAssistantWebhook: String?,
        mqttPassword: String?,
        mqttPKCS12Password: String?
    ) {
        let summaries = AppDestinations.repository.credentialSummaries()
        return (
            summaries.httpsBearer,
            summaries.homeAssistantWebhook,
            summaries.mqttPassword,
            summaries.mqttPKCS12Password
        )
    }

    // #42: forwarder; remove when the product UI calls the service.
    private static func mqttPKCS12Password(
        from saved: MQTTVerificationRecord,
        root: URL
    ) async throws -> String? {
        try await AppDestinations.records.mqttPKCS12Password(from: saved, root: root)
    }

    private static func verifiedCompanionDestination(
        session: PairingSession,
        root: URL,
        onTestProgress: DestinationTestProgress? = nil
    ) async throws -> (VerifiedDestination, TraceparentEmission) {
        let psk = try CompanionPSK.preSharedKey(from: session.secret)
        let discovered = try await CompanionDiscovery().find(
            pairedName: session.serviceName,
            for: .seconds(8)
        )
        let options = NWByteStream.Options(
            requireTLS13: true,
            failFastOnWaiting: true,
            preSharedKey: psk
        )
        let deliveryPipe = ByteStreamCompanionPipe(
            stream: NWByteStream(service: discovered, options: options)
        )
        let emission = TraceparentEmission(enabled: storedCompanionTraceparent())
        let verificationURL = companionTestReportURL(root: root)
        if let data = try? Data(contentsOf: verificationURL),
           let saved = try? JSONDecoder().decode(CompanionVerificationRecord.self, from: data),
           saved.serviceName == session.serviceName,
           saved.macInstallationID == session.macInstallationID,
           saved.report.allowsEnablement
        {
            let verified = try CompanionDestinationEnable.resume(
                deliveryPipe: deliveryPipe,
                installationID: session.localInstallationID,
                testReport: saved.report,
                traceparent: emission,
                meteredPolicy: .fromAllowsMetered(
                    allowsMeteredNetwork(destinationID: "companion")
                ),
                pathConditions: networkPathConditions()
            )
            return (verified, emission)
        }
        let testPipe = ByteStreamCompanionPipe(
            stream: NWByteStream(service: discovered, options: options)
        )
        let completed = try await CompanionDestinationEnable.complete(
            testPipe: testPipe,
            deliveryPipe: deliveryPipe,
            installationID: session.localInstallationID,
            emittedAt: Date().ISO8601Format(),
            traceparent: emission,
            meteredPolicy: .fromAllowsMetered(
                allowsMeteredNetwork(destinationID: "companion")
            ),
            pathConditions: networkPathConditions(),
            onProgress: onTestProgress
        )
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
        return (completed.destination, emission)
    }

    private static func verifiedMQTTDestination(root: URL) async throws -> VerifiedDestination {
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
                    service: IdentifierRoot.qualified("mqtt")
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
            clientPKCS12Password: try await mqttPKCS12Password(from: saved, root: root),
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
        return try setup.enable(sink: sink)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func runMQTTDestination(
        onProgress: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> [String] {
        try await AppExport.service.runMQTTDestination(onProgress: onProgress)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func runHTTPSDestination(
        destinationID: String = "https",
        destinationLabel: String = "HTTPS destination",
        onProgress: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> [String] {
        try await AppExport.service.runHTTPSDestination(
            destinationID: destinationID,
            destinationLabel: destinationLabel,
            onProgress: onProgress
        )
    }

    private static func verifiedHTTPSDestination(
        destinationID: String,
        root: URL
    ) async throws -> (VerifiedDestination, TraceparentEmission) {
        let data = try Data(
            contentsOf: httpsDestinationRecordURL(
                root: root,
                destinationID: destinationID
            )
        )
        let saved = try JSONDecoder().decode(HTTPSVerificationRecord.self, from: data)
        let allowedHosts = Set(saved.allowedHosts)
        let bearer: String?
        if saved.hasBearer {
            bearer = String(
                decoding: try await KeychainSecretStore(
                    service: httpsKeychainService(destinationID)
                ).load(SecretHandle(rawValue: "bearer")),
                as: UTF8.self
            )
        } else {
            bearer = nil
        }
        let destinationURLString: String
        if destinationID == "home-assistant" {
            let webhookID = String(
                decoding: try await KeychainSecretStore(
                    service: httpsKeychainService(destinationID)
                ).load(SecretHandle(rawValue: "webhook-id")),
                as: UTF8.self
            )
            destinationURLString = try HomeAssistantWebhookPreset.endpoint(
                baseURLString: saved.urlString,
                webhookID: webhookID
            ).absoluteString
        } else {
            destinationURLString = saved.urlString
        }
        let destination = try HTTPSDestination(
            urlString: destinationURLString,
            allowedHosts: allowedHosts,
            allowInsecureHTTP: saved.allowInsecureHTTP,
            authorizationBearer: bearer
        )
        let base = BackgroundTaskHTTPTransport(inner: try SystemHTTPTransport.make(
            probing: destination.url,
            allowedHosts: allowedHosts,
            allowInsecureHTTP: saved.allowInsecureHTTP
        ))
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
                meteredPolicy: .fromAllowsMetered(
                    allowsMeteredNetwork(destinationID: destinationID)
                ),
                pathConditions: networkPathConditions()
            )
        )
        return (verified, emission)
    }

    static func enableLocalFileDestination(
        onProgress: DestinationTestProgress? = nil
    ) async throws -> [String] {
        try ExportScopeGate.requireConfigured(try await destinationScope("local-file"))
        let root = try applicationSupportRoot()
        let folderAccess = try localExportFolder(root: root)
        defer { withExtendedLifetime(folderAccess) {} }
        let dest = folderAccess.url
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

    // #42: forwarder; remove when the product UI calls the service.
    static func stopExportingHeartRate() async throws { try await AppExport.service.stopExportingHeartRate() }

    // #42: forwarder; remove when the product UI calls the service.
    static func expireQueuesAndNotify() async throws -> QueueExpiryResult { try await AppExport.service.expireQueuesAndNotify() }

    // #42: forwarder; remove when the product UI calls the service.
    static func recoverInterruptedExports() async throws -> String? { try await AppExport.service.recoverInterruptedExports() }

    // #42: forwarder; remove when the product UI calls the service.
    static func storedHTTPSTraceparent() -> Bool {
        AppDestinations.repository.httpsTraceparent()
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func setHTTPSTraceparent(_ enabled: Bool, destinationID: String = "https") throws {
        try AppDestinations.repository.setHTTPSTraceparent(enabled, destinationID: destinationID)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func storedCompanionTraceparent() -> Bool {
        AppDestinations.repository.companionTraceparent()
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func setCompanionTraceparent(_ enabled: Bool) throws {
        try AppDestinations.repository.setCompanionTraceparent(enabled)
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
        let homeAssistantURL = root.appendingPathComponent(
            "home-assistant-destination.json"
        )
        if let data = try? Data(contentsOf: homeAssistantURL),
           let record = try? JSONDecoder().decode(
               HTTPSVerificationRecord.self,
               from: data
           ),
           record.report.allowsEnablement,
           let baseURL = URL(string: record.urlString) {
            let scope = try await destinationScope("home-assistant")
            destinations.append(
                try PortableDestinationConfiguration(
                    sourceIdentifier:
                        record.importedLocalIdentifier ?? "home-assistant",
                    displayName: baseURL.host ?? "Home Assistant",
                    kind: .homeAssistant,
                    endpoint: baseURL.absoluteString,
                    settings: [
                        "allowInsecureHTTP":
                            record.allowInsecureHTTP ? "true" : "false",
                        "mode": "webhook",
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
        if let data = try? Data(contentsOf: companionTestReportURL(root: root)),
           let record = try? JSONDecoder().decode(
               CompanionVerificationRecord.self,
               from: data
           ),
           record.report.allowsEnablement {
            let scope = try await destinationScope("companion")
            destinations.append(
                try PortableDestinationConfiguration(
                    sourceIdentifier: "companion",
                    displayName: record.serviceName,
                    kind: .companion,
                    endpoint: record.serviceName,
                    settings: ["serviceName": record.serviceName],
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
        let store = try StateStoreHost.store(path: root.appendingPathComponent("state.sqlite").path)
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
            let store = try StateStoreHost.store(path: root.appendingPathComponent("state.sqlite").path)
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
        let store = try StateStoreHost.store(path: root.appendingPathComponent("state.sqlite").path)
        let now = Date().timeIntervalSince1970
        let selection = try await store.transact { tx in
            OTLPBacklog.select(events: try tx.loadJournal(), nowEpoch: now)
        }
        if !selection.localOnly.isEmpty {
            // The parent row carries the run; its per-destination children stay local.
            try await store.transact { tx in
                try tx.markJournalProjected(
                    runIDs: selection.localOnly.map(\.runID),
                    atEpoch: now
                )
            }
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

    // #42: forwarder; remove when the product UI calls the service.
    static func wipeEverything() async throws { try await AppExport.service.wipeEverything() }

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
                destinationLabel: "This \(DeviceNoun.current) → Archive folder",
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
        let store = try StateStoreHost.store(path: root.appendingPathComponent("state.sqlite").path)
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

    // #42: forwarder; remove when the product UI calls the service.
    private static func localFileTestReportURL(root: URL) -> URL {
        DestinationSidecar.localFileTestReport.url(in: root)
    }

    // #42: forwarder; remove when the product UI calls the service.
    private static func localExportFolderBookmarkURL(root: URL) -> URL {
        DestinationSidecar.localFolderBookmark.url(in: root)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func chooseLocalExportFolder(_ url: URL) throws -> String {
        try AppDestinations.repository.chooseLocalExportFolder(url)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func localExportFolderName() -> String? {
        AppDestinations.repository.localExportFolderName()
    }

    // #42: forwarder; remove when the product UI calls the service.
    private static func localExportFolder(root: URL) throws -> SecurityScopedAccess {
        try AppDestinations.folder.access(root: root)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func isLocalFileEnabled() -> Bool {
        AppDestinations.repository.isLocalFileEnabled()
    }

    /// UX-45: hops for the onboarding and Settings explainer. Credential *kinds*
    /// only — never tokens, passwords, or PKCS#12 bytes.
    // #42: forwarder; remove when the product UI calls the service.
    static func dataFlowHops() -> [DataFlowHop] {
        AppStatus.transparency.dataFlowHops()
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func dataFlowTypeCount() async -> Int {
        await AppStatus.transparency.dataFlowTypeCount()
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func wipeInventory() async -> WipeInventory {
        await AppStatus.transparency.wipeInventory()
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func wakeLedger() throws -> WakeLedger { try AppHealth.service.wakeLedger() }

    // #42: forwarder; remove when the product UI calls the service.
    @discardableResult
    static func observeAuthorizationChanges() async throws -> Bool { try await AppHealth.service.observeAuthorizationChanges() }

    // #42: forwarder; remove when the product UI calls the service.
    static func reenableCoreActivityAfterAuthorizationRequest() async throws { try await AppHealth.service.reenableAfterAuthorizationRequest() }

    // #42: forwarder; remove when the product UI calls the service.
    static func startHealthObservers() async throws -> HealthKitObserverCoordinator { try await AppHealth.service.startObservers { await ObserverExportGate.shared.enqueue($0) } }

    // #42: forwarder; remove when the product UI calls the service.
    static func observerRegistrationFailureSummary() -> String? { AppHealth.service.observerRegistrationFailureSummary() }

    // #42: forwarder; remove when the product UI calls the service.
    private static func companionTestReportURL(root: URL) -> URL {
        DestinationSidecar.companionTestReport.url(in: root)
    }

    static func ledgerHeadSeal() -> any LedgerHeadSeal {
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
            store: KeychainSecretStore(service: IdentifierRoot.qualified("ios.psk")),
            recordFile: root.appendingPathComponent("pairing.json")
        )
    }

    #if DEBUG
    static func resetCompanionSlotForUITests() {
        guard let root = try? applicationSupportRoot() else { return }
        try? FileManager.default.removeItem(
            at: root.appendingPathComponent("pairing.json")
        )
        try? FileManager.default.removeItem(at: companionTestReportURL(root: root))
    }
    #endif

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

// #42: ExportService reaches destination setup and storage helpers that still live in
// this file. Each bridge goes when the helper it calls moves to its own service.
extension HarnessExport {
    static func exportVerifiedLocalFile(
        root: URL,
        destinationDirectory: URL
    ) throws -> (VerifiedDestination, [TrustEvent]) {
        try verifiedLocalFile(root: root, destinationDirectory: destinationDirectory)
    }

    static func exportVerifiedHTTPSDestination(
        destinationID: String,
        root: URL
    ) async throws -> (VerifiedDestination, TraceparentEmission) {
        try await verifiedHTTPSDestination(destinationID: destinationID, root: root)
    }

    static func exportVerifiedMQTTDestination(root: URL) async throws -> VerifiedDestination {
        try await verifiedMQTTDestination(root: root)
    }

    static func exportVerifiedCompanionDestination(
        session: PairingSession,
        root: URL,
        onTestProgress: DestinationTestProgress? = nil
    ) async throws -> (VerifiedDestination, TraceparentEmission) {
        try await verifiedCompanionDestination(session: session, root: root, onTestProgress: onTestProgress)
    }

    static func exportEmitTrustNotices(_ events: [TrustEvent]) async throws {
        try await emitTrustNotices(events)
    }

    static func exportProtectedPayloadDirectory(named name: String, under root: URL) throws -> URL {
        try protectedPayloadDirectory(named: name, under: root)
    }

    static func exportResettableLedgerHeadSeal() -> any ResettableLedgerHeadSeal {
        resettableLedgerHeadSeal()
    }
}
