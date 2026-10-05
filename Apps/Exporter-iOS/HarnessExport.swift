// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

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
    static func prepareHomeAssistantWebhook(
        baseURLString: String,
        webhookID: String,
        allowInsecureHTTP: Bool,
        importedLocalIdentifier: String? = nil,
        confirmedLeafSPKISha256: String? = nil,
        onProgress: DestinationTestProgress? = nil
    ) async throws -> DestinationConfirmationCard {
        try await AppDestinationSetup.prepareHomeAssistantWebhook(
            baseURLString: baseURLString,
            webhookID: webhookID,
            allowInsecureHTTP: allowInsecureHTTP,
            importedLocalIdentifier: importedLocalIdentifier,
            confirmedLeafSPKISha256: confirmedLeafSPKISha256,
            onProgress: onProgress
        )
    }

    // #42: forwarder; remove when the product UI calls the service.
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
        try await AppDestinationSetup.prepareHTTPS(
            urlString: urlString,
            allowInsecureHTTP: allowInsecureHTTP,
            bearer: bearer,
            destinationID: destinationID,
            destinationLabel: destinationLabel,
            webhookID: webhookID,
            persistedURLString: persistedURLString,
            importedLocalIdentifier: importedLocalIdentifier,
            confirmedLeafSPKISha256: confirmedLeafSPKISha256,
            onProgress: onProgress
        )
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func confirmPendingHTTPSDestination(propagateTraceparent: Bool = false) async throws -> [String] {
        try await AppDestinationSetup.service.confirmHTTPS(propagateTraceparent: propagateTraceparent)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func cancelPendingHTTPSDestination() {
        Task { await AppDestinationSetup.service.cancelHTTPS() }
    }

    // #42: forwarder; remove when the product UI calls the service.
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
        try await AppDestinationSetup.prepareMQTT(
            urlString: urlString,
            allowInsecure: allowInsecure,
            clientID: clientID,
            topic: topic,
            clientPKCS12: clientPKCS12,
            clientPKCS12Password: clientPKCS12Password,
            username: username,
            password: password,
            qos: qos,
            importedLocalIdentifier: importedLocalIdentifier,
            confirmedIdentity: confirmedIdentity,
            onProgress: onProgress
        )
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func confirmPendingMQTTDestination() async throws -> [String] {
        try await AppDestinationSetup.service.confirmMQTT()
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func cancelPendingMQTTDestination() {
        Task { await AppDestinationSetup.service.cancelMQTT() }
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
    private static func verifiedCompanionDestination(
        session: PairingSession,
        root: URL,
        onTestProgress: DestinationTestProgress? = nil
    ) async throws -> (VerifiedDestination, TraceparentEmission) {
        try await AppDestinationSetup.verifiedCompanion(session: session, onTestProgress: onTestProgress)
    }

    // #42: forwarder; remove when the product UI calls the service.
    private static func verifiedMQTTDestination(root: URL) async throws -> VerifiedDestination {
        try await AppDestinationSetup.verifiedMQTT(root: root)
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

    // #42: forwarder; remove when the product UI calls the service.
    private static func verifiedHTTPSDestination(
        destinationID: String,
        root: URL
    ) async throws -> (VerifiedDestination, TraceparentEmission) {
        try await AppDestinationSetup.verifiedHTTPS(destinationID: destinationID, root: root)
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func enableLocalFileDestination(
        onProgress: DestinationTestProgress? = nil
    ) async throws -> [String] {
        try await AppDestinationSetup.enableLocalFile(onProgress: onProgress)
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

    // #42: forwarder; remove when the product UI calls the service.
    static func portableConfigurationExport() async throws -> URL {
        try await AppDestinationSetup.portableConfigurationExport()
    }

    #if !OHE_OBS25_SIZE_BASELINE
    // #42: forwarder; remove when the product UI calls the service.
    static func storedOTLPURL() -> String {
        AppDestinationSetup.service.storedOTLPURL()
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func previewOTLP() async throws -> (preview: String, payload: Data) {
        try await AppDestinationSetup.previewOTLP()
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func enableOTLPCollector(
        urlString: String,
        allowInsecureHTTP: Bool,
        previewPayload: Data
    ) async throws -> [String] {
        try await AppDestinationSetup.enableOTLPCollector(
            urlString: urlString,
            allowInsecureHTTP: allowInsecureHTTP,
            previewPayload: previewPayload
        )
    }

    // #42: forwarder; remove when the product UI calls the service.
    static func disableOTLPCollector() throws {
        AppDestinationSetup.service.disableOTLP()
    }

    // #42: forwarder; remove when the product UI calls the service.
    private static func otlpMetricsDestination(
        tracesEndpoint: HTTPSDestination,
        allowedHosts: Set<String>
    ) throws -> HTTPSDestination {
        try AppDestinationSetup.otlpMetricsDestination(tracesEndpoint: tracesEndpoint, allowedHosts: allowedHosts)
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

    // #42: forwarder; remove when the product UI calls the service.
    private static func verifiedLocalFile(
        root: URL,
        destinationDirectory: URL,
        onProgress: DestinationTestProgress? = nil
    ) throws -> (VerifiedDestination, [TrustEvent]) {
        try AppDestinationSetup.verifiedLocalFile(destinationDirectory: destinationDirectory, onProgress: onProgress)
    }

    // #42: forwarder; remove when the product UI calls the service.
    private static func emitTrustNotices(_ events: [TrustEvent]) async throws {
        try await AppDestinationSetup.service.emitTrustNotices(events, destination: "local-file")
    }

    // #42: forwarder; remove when the product UI calls the service.
    private static func emitTrustNotices(
        _ events: [TrustEvent],
        destination: String
    ) async throws {
        try await AppDestinationSetup.service.emitTrustNotices(events, destination: destination)
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

    // #42: forwarder; remove when the product UI calls the service.
    static func forgetCompanion() async throws {
        try await AppDestinationSetup.service.forgetCompanion()
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
