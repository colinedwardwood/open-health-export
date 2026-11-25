// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import CorrectnessEngine
import DestinationTrust
import EnginePorts
import Foundation
import MetricCatalog
import NetEgress
import TestSupport
import Testing
import Watchdog
import WireFormat

// MARK: Fakes

private final class SetupState: @unchecked Sendable {
    let lock = NSLock()
    var https: [String: HTTPSVerificationRecord] = [:]
    var mqtt: MQTTVerificationRecord?
    var clientCertificate: Data?
    var clientCertificateWrites = 0
    var companion: CompanionVerificationRecord?
    var localFileReport: DestinationTestReport?
    var otlp: OTLPDestinationRecord?
    var snapshots: [String: DestinationStatusSnapshot] = [:]
    var widgetReloads = 0
    var scopes: [String: DestinationExportScope] = [:]
    var authorizedScopes: [String] = []
    var pairingForgotten = false
    var secretStores: [String: MemorySecretStore] = [:]

    func with<T>(_ body: (SetupState) throws -> T) rethrows -> T {
        try lock.withLock { try body(self) }
    }

    func secrets(_ service: String) -> MemorySecretStore {
        with {
            if let store = $0.secretStores[service] { return store }
            let store = MemorySecretStore()
            $0.secretStores[service] = store
            return store
        }
    }
}

private struct MemorySetupFiles: DestinationSetupFiles {
    let state: SetupState
    func httpsRecord(_ destinationID: String) -> HTTPSVerificationRecord? { state.with { $0.https[destinationID] } }
    func writeHTTPSRecord(_ record: HTTPSVerificationRecord, destinationID: String) throws {
        state.with { $0.https[destinationID] = record }
    }
    func mqttRecord() -> MQTTVerificationRecord? { state.with { $0.mqtt } }
    func writeMQTTRecord(_ record: MQTTVerificationRecord) throws { state.with { $0.mqtt = record } }
    func writeMQTTClientCertificate(_ pkcs12: Data?) throws {
        state.with {
            $0.clientCertificate = pkcs12
            $0.clientCertificateWrites += 1
        }
    }
    func companionRecord() -> CompanionVerificationRecord? { state.with { $0.companion } }
    func writeCompanionRecord(_ record: CompanionVerificationRecord) throws { state.with { $0.companion = record } }
    func removeCompanionRecord() { state.with { $0.companion = nil } }
    func localFileTestReport() -> DestinationTestReport? { state.with { $0.localFileReport } }
    func writeLocalFileTestReport(_ report: DestinationTestReport) throws { state.with { $0.localFileReport = report } }
    func removeLocalFileTestReport() { state.with { $0.localFileReport = nil } }
    func otlpRecord() -> OTLPDestinationRecord? { state.with { $0.otlp } }
    func writeOTLPRecord(_ record: OTLPDestinationRecord) throws { state.with { $0.otlp = record } }
    func removeOTLPRecord() { state.with { $0.otlp = nil } }
}

/// Mirrors DestinationSnapshotFile.recordSecurityEvents over memory.
private struct MemorySetupSnapshots: SetupStatusSnapshots {
    let state: SetupState
    func readAll() -> [DestinationStatusSnapshot] {
        state.with { $0.snapshots.values.sorted { $0.destinationLabel < $1.destinationLabel } }
    }
    func recordSecurityEvents(
        _ count: Int,
        destinationID: String,
        destinationLabel: String?,
        enabled: Bool?,
        state displayState: DestinationDisplayState?,
        writtenAtEpoch: TimeInterval
    ) throws {
        guard count > 0 else { return }
        state.with {
            var snapshot = $0.snapshots[destinationID] ?? DestinationStatusSnapshot(
                destinationID: destinationID,
                destinationLabel: destinationLabel,
                enabled: true,
                state: .noExportsYet,
                unacknowledgedSecurityEventCount: 0,
                writtenAtEpoch: writtenAtEpoch
            )
            snapshot.unacknowledgedSecurityEventCount += count
            if let enabled { snapshot.enabled = enabled }
            if let displayState { snapshot.state = displayState }
            snapshot.writtenAtEpoch = writtenAtEpoch
            $0.snapshots[destinationID] = snapshot
        }
    }
    func write(_ snapshot: DestinationStatusSnapshot) throws {
        state.with { $0.snapshots[snapshot.destinationID] = snapshot }
    }
    func remove(destinationID: String) { state.with { $0.snapshots[destinationID] = nil } }
    func reloadStatusWidget() { state.with { $0.widgetReloads += 1 } }
}

private final class RecordingUserNotifier: UserNotifier, @unchecked Sendable {
    private let lock = NSLock()
    private var _notices: [UserNotice] = []
    let delivery: NoticeDelivery
    init(_ delivery: NoticeDelivery = .posted) { self.delivery = delivery }
    var notices: [UserNotice] { lock.withLock { _notices } }
    func notify(_ notice: UserNotice) async throws -> NoticeDelivery {
        lock.withLock { _notices.append(notice) }
        return delivery
    }
}

private struct UnusedRecords: DestinationRecordStorage {
    func verification(_ destinationID: String) -> DestinationVerificationSummary? { nil }
    func setPropagateTraceparent(_ enabled: Bool, destinationID: String) throws {}
    func exists(_ sidecar: DestinationSidecar) -> Bool { false }
    func remove(_ sidecar: DestinationSidecar) {}
}

private struct UnusedPreferences: DestinationPreferenceStorage {
    func exportRole(_ destinationID: String) -> String? { nil }
    func setExportRole(_ rawValue: String, destinationID: String) {}
    func allowsMeteredNetwork(_ destinationID: String) -> Bool { false }
    func companionPropagatesTraceparent() -> Bool { false }
    func setCompanionPropagatesTraceparent(_ enabled: Bool) {}
}

private struct UnusedSnapshots: DestinationSnapshotStorage {
    func exportRole(_ destinationID: String) -> DestinationExportRole? { nil }
    func applyExportRole(_ role: DestinationExportRole, destinationID: String, at now: Date) throws {}
}

private struct UnusedFolder: LocalExportFolderStorage {
    func saveFolder(_ url: URL) throws {}
    func accessibleFolderName() -> String? { nil }
}

private struct MemoryScopes: DestinationScopeStorage {
    let state: SetupState
    func loadScope(_ destinationID: String) async throws -> DestinationExportScope? {
        state.with { $0.scopes[destinationID] }
    }
    func saveScope(_ scope: DestinationExportScope) async throws {
        state.with { $0.scopes[scope.destinationID] = scope }
    }
    func reenable(_ metric: MetricID, reason: String) async throws {}
}

private let setupNow = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01T00:00:00Z
private let heartRate = MetricCatalog.heartRate.id

private struct Harness {
    let state = SetupState()
    let notifier: RecordingUserNotifier
    let store = MemoryStateStore()
    let service: DestinationSetupService

    init(delivery: NoticeDelivery = .posted) {
        let state = self.state
        let store = self.store
        notifier = RecordingUserNotifier(delivery)
        service = DestinationSetupService(
            repository: DestinationRepository(
                records: UnusedRecords(),
                preferences: UnusedPreferences(),
                snapshots: UnusedSnapshots(),
                scopes: MemoryScopes(state: state),
                folder: UnusedFolder(),
                now: { setupNow }
            ),
            files: MemorySetupFiles(state: state),
            snapshots: MemorySetupSnapshots(state: state),
            secrets: { state.secrets($0) },
            notifier: notifier,
            store: { store },
            authorizeScope: { scope in state.with { $0.authorizedScopes.append(scope.destinationID) } },
            forgetPairing: { state.with { $0.pairingForgotten = true } },
            now: { setupNow }
        )
    }

    func configureScope(_ destinationID: String) throws {
        let scope = try DestinationExportScope(
            destinationID: destinationID,
            metrics: [heartRate],
            startInclusive: setupNow.addingTimeInterval(-86_400)
        )
        state.with { $0.scopes[destinationID] = scope }
    }

    var ledger: [EgressEntry] { store.transaction.ledger }
}

private let passedHTTPSReport = DestinationTestReport(
    verdict: .passed,
    steps: [
        DestinationTestStepReport(name: .tlsHandshake, outcome: .passed),
        DestinationTestStepReport(name: .sendCanary, outcome: .passed),
    ]
)

private let identity = TLSIdentity(
    leafSPKISha256: String(repeating: "a", count: 64),
    issuerSPKISha256: String(repeating: "b", count: 64),
    tlsVersion: "1.3",
    cipherSuite: "TLS_AES_128_GCM_SHA256",
    leafSubject: "CN=nas.local",
    leafIssuer: "CN=nas.local",
    notBefore: "2026-01-01",
    notAfter: "2027-01-01",
    resolvedAddress: "192.168.1.20",
    addressClass: .privateRFC1918,
    trustAnchorKind: TLSIdentity.untrustedAnchor
)

private func probe(
    url: String = "https://nas.local/ingest",
    identity: TLSIdentity? = identity,
    events: [TrustEvent] = [.canaryConfirmed, .pinRecorded(groupedFingerprint: "AAAA")]
) -> DestinationProbeResult {
    DestinationProbeResult(
        destinationURL: URL(string: url)!,
        report: passedHTTPSReport,
        identity: identity,
        preview: Data("{\"preview\":true}".utf8),
        pendingEvents: events
    )
}

private func pendingHTTPS(
    destinationID: String = "https",
    label: String = "HTTPS destination",
    allowInsecureHTTP: Bool = false,
    bearer: String? = "secret-token",
    webhookID: String? = nil,
    persistedURLString: String? = nil,
    probe result: DestinationProbeResult = probe()
) -> PendingHTTPSDestination {
    PendingHTTPSDestination(
        probe: result,
        destinationID: destinationID,
        destinationLabel: label,
        host: "nas.local",
        allowedHosts: ["nas.local"],
        allowInsecureHTTP: allowInsecureHTTP,
        bearer: bearer,
        webhookID: webhookID,
        persistedURLString: persistedURLString,
        firstSeen: "2026-01-01T00:00:00Z",
        importedLocalIdentifier: nil
    )
}

private func pendingMQTT(
    allowInsecure: Bool = false,
    password: String? = "broker-pass",
    pkcs12: Data? = Data([1, 2, 3]),
    pkcs12Password: String? = "p12-pass"
) -> PendingMQTTDestination {
    PendingMQTTDestination(
        probe: probe(url: "mqtts://broker.local:8883", events: [.canaryConfirmed]),
        host: "broker.local",
        allowedHosts: ["broker.local"],
        allowInsecure: allowInsecure,
        clientID: "phone",
        topic: "health/export",
        qos: 1,
        clientPKCS12: pkcs12,
        clientPKCS12Password: pkcs12Password,
        username: "me",
        password: password,
        firstSeen: "2026-01-01T00:00:00Z",
        importedLocalIdentifier: "imported-7"
    )
}

// MARK: Pure rules

@Test func setupHostIsLowercasedAndRequired() throws {
    #expect(try DestinationSetupService.host(of: "https://NAS.Local:8443/x") == "nas.local")
    #expect(throws: EgressError.invalidURL) { try DestinationSetupService.host(of: "not a url") }
    #expect(throws: EgressError.invalidURL) { try DestinationSetupService.host(of: "file:///tmp/x") }
}

@Test func setupCardCallsATransportUnencryptedOnlyWhenOptedIn() {
    let noTLS = probe(url: "http://nas.local/x", identity: nil)
    #expect(DestinationSetupService.card(host: "nas.local", probe: noTLS, allowInsecure: true).insecureWithoutTLS)
    #expect(!DestinationSetupService.card(host: "nas.local", probe: noTLS, allowInsecure: false).insecureWithoutTLS)
    #expect(!DestinationSetupService.card(host: "nas.local", probe: probe(), allowInsecure: true).insecureWithoutTLS)
}

@Test func setupConfirmedLinesAreTheCardThenEachStep() {
    let pending = pendingHTTPS()
    let lines = DestinationSetupService.confirmedLines(
        card: pending.confirmationCard,
        report: passedHTTPSReport
    )
    #expect(lines.first == ConfirmationCopy.title)
    #expect(lines.contains("SPKI      SHA-256 \(identity.groupedLeafFingerprint)"))
    #expect(Array(lines.suffix(2)) == ["tlsHandshake: passed", "sendCanary: passed"])
}

@Test func setupHTTPSRecordKeepsDescriptorsNotSecrets() throws {
    let record = pendingHTTPS(bearer: "secret-token").record(propagateTraceparent: true)
    #expect(record.urlString == "https://nas.local/ingest")
    #expect(record.hasBearer)
    #expect(record.bearerDescriptor?.characterCount == 12)
    #expect(record.bearerDescriptor?.addedOnDay == "2026-01-01")
    #expect(record.webhookDescriptor?.appearance == .absent)
    #expect(record.leafSPKISha256 == identity.leafSPKISha256)
    #expect(record.propagateTraceparent == true)
    let json = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
    #expect(!json.contains("secret-token"))
}

@Test func setupHomeAssistantRecordSavesTheBaseURLNotTheWebhook() {
    let record = pendingHTTPS(
        destinationID: "home-assistant",
        bearer: nil,
        webhookID: "hook-123",
        persistedURLString: "https://ha.local:8123",
        probe: probe(url: "https://ha.local:8123/api/webhook/hook-123")
    ).record(propagateTraceparent: false)
    #expect(record.urlString == "https://ha.local:8123")
    #expect(!record.hasBearer)
    #expect(record.webhookDescriptor?.appearance == .webhookID)
}

@Test func setupMQTTRecordNeverHoldsThePKCS12Password() {
    let record = pendingMQTT().record()
    #expect(record.clientPKCS12Password == nil)
    #expect(record.hasClientPKCS12 == true)
    #expect(record.hasClientPKCS12Password == true)
    #expect(record.hasPassword == true)
    #expect(record.passwordDescriptor?.appearance == .password)
    #expect(record.pkcs12PasswordDescriptor?.appearance == .pkcs12Password)
    #expect(record.urlString == "mqtts://broker.local:8883")
    #expect(record.importedLocalIdentifier == "imported-7")
}

@Test func setupRecordsDecodeTheFormatsAlreadyOnDisk() throws {
    // An MQTT record from before firstSeen, descriptors and the Keychain move.
    let legacyMQTT = Data("""
    {"urlString":"mqtts://broker.local","allowedHosts":["broker.local"],"allowInsecure":false,
     "clientID":"phone","topic":"t","report":{"verdict":"passed","steps":[]},
     "clientPKCS12Password":"old","leafSPKISha256":"aa","issuerSPKISha256":"bb"}
    """.utf8)
    let mqtt = try JSONDecoder().decode(MQTTVerificationRecord.self, from: legacyMQTT)
    #expect(mqtt.clientPKCS12Password == "old")
    #expect(mqtt.pin?.firstSeen == "1970-01-01T00:00:00Z")
    #expect(mqtt.pin?.policy == .leaf)

    let https = pendingHTTPS().record(propagateTraceparent: false)
    let roundTrip = try JSONDecoder().decode(
        HTTPSVerificationRecord.self,
        from: JSONEncoder().encode(https)
    )
    #expect(roundTrip == https)
    #expect(roundTrip.pin?.leafSPKISha256 == identity.leafSPKISha256)
    #expect(roundTrip.pin?.firstSeen == "2026-01-01T00:00:00Z")

    var unpinned = https
    unpinned.issuerSPKISha256 = nil
    #expect(unpinned.pin == nil)
}

@Test func setupMQTTProbeTrustPinsOnlyAConfirmedIdentity() {
    #expect(MQTTProbeTrust.forConfirmed(nil, firstSeen: "t") == .captureUntrustedIdentity)
    #expect(MQTTProbeTrust.forConfirmed(identity, firstSeen: "t") == .pinned(PinRecord(
        leafSPKISha256: identity.leafSPKISha256,
        issuerSPKISha256: identity.issuerSPKISha256,
        firstSeen: "t",
        policy: .leaf
    )))
}

@Test func setupOTLPMetricsSitBesideTheTracesEndpoint() {
    func metrics(_ traces: String) -> String? {
        DestinationSetupService.otlpMetricsURL(tracesURL: URL(string: traces)!)?.absoluteString
    }
    #expect(metrics("https://otel.local/v1/traces") == "https://otel.local/v1/metrics")
    #expect(metrics("https://otel.local/otlp/") == "https://otel.local/otlp/v1/metrics")
    #expect(metrics("https://otel.local/otlp") == "https://otel.local/otlp/v1/metrics")
    #expect(metrics("https://otel.local") == "https://otel.local/v1/metrics")
}

// MARK: Pending drafts

@Test func setupDraftIsTakenOnceAndCancelDropsIt() async throws {
    let harness = Harness()
    try harness.configureScope("https")
    let card = await harness.service.stageHTTPS(pendingHTTPS())
    #expect(card.host == "nas.local")
    _ = try await harness.service.confirmHTTPS()
    await #expect(throws: SetupError.verificationRequired) {
        try await harness.service.confirmHTTPS()
    }

    _ = await harness.service.stageHTTPS(pendingHTTPS())
    await harness.service.cancelHTTPS()
    await #expect(throws: SetupError.verificationRequired) {
        try await harness.service.confirmHTTPS()
    }
}

@Test func setupANewProbeReplacesTheEarlierDraft() async throws {
    let harness = Harness()
    try harness.configureScope("home-assistant")
    _ = await harness.service.stageHTTPS(pendingHTTPS(destinationID: "https"))
    _ = await harness.service.stageHTTPS(pendingHTTPS(destinationID: "home-assistant", label: "Home Assistant"))
    _ = try await harness.service.confirmHTTPS()
    #expect(harness.state.with { $0.https["home-assistant"] } != nil)
    #expect(harness.state.with { $0.https["https"] } == nil)
}

// MARK: Confirming

@Test func setupConfirmHTTPSSavesSecretsRecordStatusAndAsksHealth() async throws {
    let harness = Harness()
    try harness.configureScope("https")
    _ = await harness.service.stageHTTPS(pendingHTTPS())
    let lines = try await harness.service.confirmHTTPS(propagateTraceparent: true)

    #expect(lines.first == ConfirmationCopy.title)
    let record = try #require(harness.state.with { $0.https["https"] })
    #expect(record.propagateTraceparent == true)
    let keychain = harness.state.secrets(DestinationRepository.keychainService("https"))
    #expect(try await keychain.load(SecretHandle(rawValue: "bearer")) == Array("secret-token".utf8))
    await #expect(throws: SecretStoreError.notFound) {
        try await keychain.load(SecretHandle(rawValue: "webhook-id"))
    }
    // Two probe events plus the enablement.
    #expect(harness.state.with { $0.snapshots["https"]?.unacknowledgedSecurityEventCount } == 3)
    #expect(harness.notifier.notices.count == 3)
    #expect(harness.state.with { $0.authorizedScopes } == ["https"])
    #expect(harness.ledger.isEmpty)
}

@Test func setupConfirmHTTPSRemovesASecretTheNewSetupDoesNotHave() async throws {
    let harness = Harness()
    try harness.configureScope("https")
    let keychain = harness.state.secrets(DestinationRepository.keychainService("https"))
    try await keychain.store(Array("old".utf8), handle: SecretHandle(rawValue: "bearer"))
    _ = await harness.service.stageHTTPS(pendingHTTPS(bearer: nil))
    _ = try await harness.service.confirmHTTPS()
    await #expect(throws: SecretStoreError.notFound) {
        try await keychain.load(SecretHandle(rawValue: "bearer"))
    }
    #expect(harness.state.with { $0.https["https"]?.hasBearer } == false)
}

@Test func setupConfirmRefusesAnUnconfiguredScopeAndSavesNothing() async throws {
    let harness = Harness()
    _ = await harness.service.stageHTTPS(pendingHTTPS())
    await #expect(throws: ExportScopeViolation.scopeNotConfigured(destinationID: "https")) {
        try await harness.service.confirmHTTPS()
    }
    #expect(harness.state.with { $0.https.isEmpty })
    #expect(harness.notifier.notices.isEmpty)
}

@Test func setupConfirmInsecureHTTPRecordsTheOptInInTheLedger() async throws {
    let harness = Harness()
    try harness.configureScope("https")
    _ = await harness.service.stageHTTPS(pendingHTTPS(
        allowInsecureHTTP: true,
        probe: probe(url: "http://nas.local/x", identity: nil, events: [.canaryConfirmed])
    ))
    let lines = try await harness.service.confirmHTTPS()
    #expect(lines.contains("nas.local is using an unencrypted transport by explicit opt-in."))
    #expect(harness.ledger.map(\.outcomeKind) == ["security:insecure_http_enabled"])
    #expect(harness.ledger.first?.destination == "nas.local")
    #expect(harness.ledger.first?.wallTimeEpoch == setupNow.timeIntervalSince1970)
}

@Test func setupConfirmMQTTChecksScopeBeforeTakingTheDraft() async throws {
    let harness = Harness()
    _ = await harness.service.stageMQTT(pendingMQTT())
    await #expect(throws: ExportScopeViolation.scopeNotConfigured(destinationID: "mqtt")) {
        try await harness.service.confirmMQTT()
    }
    // The draft survives the refusal, so configuring a scope lets it be confirmed.
    try harness.configureScope("mqtt")
    let lines = try await harness.service.confirmMQTT()
    #expect(lines.last == "sendCanary: passed")
}

@Test func setupConfirmMQTTSavesCertificateSecretsAndRecord() async throws {
    let harness = Harness()
    try harness.configureScope("mqtt")
    _ = await harness.service.stageMQTT(pendingMQTT(allowInsecure: true))
    _ = try await harness.service.confirmMQTT()
    #expect(harness.state.with { $0.clientCertificate } == Data([1, 2, 3]))
    let keychain = harness.state.secrets(IdentifierRoot.qualified("mqtt"))
    #expect(try await keychain.load(SecretHandle(rawValue: "mqtt_password")) == Array("broker-pass".utf8))
    #expect(try await keychain.load(SecretHandle(rawValue: "mqtt_pkcs12_password")) == Array("p12-pass".utf8))
    #expect(harness.state.with { $0.mqtt?.clientPKCS12Password } == nil)
    #expect(harness.state.with { $0.snapshots["mqtt"]?.destinationLabel } == "broker.local")
    #expect(harness.ledger.map(\.outcomeKind) == ["security:insecure_mqtt_enabled"])
    #expect(harness.state.with { $0.authorizedScopes } == ["mqtt"])
}

@Test func setupConfirmMQTTWithoutACertificateRemovesTheOldOne() async throws {
    let harness = Harness()
    try harness.configureScope("mqtt")
    harness.state.with { $0.clientCertificate = Data([9]) }
    _ = await harness.service.stageMQTT(pendingMQTT(password: nil, pkcs12: nil, pkcs12Password: nil))
    _ = try await harness.service.confirmMQTT()
    #expect(harness.state.with { $0.clientCertificate } == nil)
    #expect(harness.state.with { $0.clientCertificateWrites } == 1)
    #expect(harness.state.with { $0.mqtt?.hasPassword } == false)
}

// MARK: Trust notices

@Test func setupDeniedTrustNoticesAreRecordedOnTheMatchingDestination() async throws {
    let harness = Harness(delivery: .skippedAuthorizationDenied)
    harness.state.with {
        $0.snapshots["https"] = DestinationStatusSnapshot(
            destinationID: "https",
            destinationLabel: "HTTPS destination",
            enabled: true,
            state: .healthy,
            writtenAtEpoch: 0
        )
        $0.snapshots["mqtt"] = DestinationStatusSnapshot(
            destinationID: "mqtt",
            destinationLabel: "broker.local",
            enabled: true,
            state: .healthy,
            writtenAtEpoch: 0
        )
    }
    try await harness.service.emitTrustNotices(
        [.canaryConfirmed, .destinationEnabled],
        destination: "HTTPS destination"
    )
    #expect(harness.ledger.map(\.detail) == ["trust_notice_suppressed:2"])
    #expect(harness.state.with { $0.snapshots["https"]?.unacknowledgedSecurityEventCount } == 2)
    #expect(harness.state.with { $0.snapshots["mqtt"]?.unacknowledgedSecurityEventCount } == 0)
    #expect(harness.state.with { $0.widgetReloads } == 1)
}

@Test func setupPostedTrustNoticesLeaveNoLedgerTrace() async throws {
    let harness = Harness()
    try await harness.service.emitTrustNotices([.canaryConfirmed], destination: "local-file")
    try await harness.service.emitTrustNotices([], destination: "local-file")
    #expect(harness.notifier.notices.count == 1)
    #expect(harness.ledger.isEmpty)
    #expect(harness.state.with { $0.widgetReloads } == 0)
}

// MARK: Local folder and companion

@Test func setupLocalFileResumesOnlyAPassedTest() throws {
    let harness = Harness()
    #expect(harness.service.resumableLocalFileReport() == nil)
    harness.state.with { $0.localFileReport = .failed(at: .writeCanary) }
    #expect(harness.service.resumableLocalFileReport() == nil)
    try harness.service.recordLocalFileTest(
        .passedLocalFile,
        events: [.canaryConfirmed, .destinationEnabled],
        destinationLabel: "This iPhone → Archive folder"
    )
    #expect(harness.service.resumableLocalFileReport() == .passedLocalFile)
    #expect(harness.state.with { $0.snapshots["local-file"]?.unacknowledgedSecurityEventCount } == 2)
    harness.service.forgetLocalFileTest()
    #expect(harness.service.resumableLocalFileReport() == nil)
}

@Test func setupCompanionResumesOnlyTheSameMac() async throws {
    let harness = Harness()
    try await harness.service.recordCompanionTest(
        CompanionVerificationRecord(
            serviceName: "Studio",
            macInstallationID: "mac-1",
            report: passedHTTPSReport,
            propagateTraceparent: false
        ),
        events: [.canaryConfirmed]
    )
    #expect(harness.service.resumableCompanionReport(serviceName: "Studio", macInstallationID: "mac-1") != nil)
    #expect(harness.service.resumableCompanionReport(serviceName: "Studio", macInstallationID: "mac-2") == nil)
    #expect(harness.service.resumableCompanionReport(serviceName: "Other", macInstallationID: "mac-1") == nil)
    #expect(harness.state.with { $0.snapshots["companion"]?.destinationLabel } == "Mac companion · Studio")
    #expect(harness.notifier.notices.map(\.destination) == ["Studio"])
}

@Test func setupForgetCompanionBlocksItAndSaysTrustWasLost() async throws {
    let harness = Harness()
    harness.state.with {
        $0.companion = CompanionVerificationRecord(
            serviceName: "Studio",
            macInstallationID: "mac-1",
            report: passedHTTPSReport,
            propagateTraceparent: nil
        )
    }
    try await harness.service.forgetCompanion()
    #expect(harness.state.with { $0.pairingForgotten })
    #expect(harness.state.with { $0.companion } == nil)
    let snapshot = try #require(harness.state.with { $0.snapshots["companion"] })
    #expect(!snapshot.enabled)
    #expect(snapshot.state == .blocked)
    #expect(snapshot.unacknowledgedSecurityEventCount == 1)
    #expect(harness.notifier.notices.map(\.kind) == [.destinationTrustLost])
}

// MARK: OTLP

@Test func setupOTLPEnableAndDisable() async throws {
    let harness = Harness()
    #expect(harness.service.storedOTLPURL() == "")
    let payload = Data("preview".utf8)
    try await harness.service.enableOTLP(
        endpoint: URL(string: "http://otel.local:4318/v1/traces")!,
        host: "otel.local",
        allowInsecureHTTP: true,
        previewPayload: payload
    )
    #expect(harness.service.storedOTLPURL() == "http://otel.local:4318/v1/traces")
    #expect(harness.state.with { $0.otlp?.previewDigest } == ContentSHA256.digest(payload))
    let snapshot = try #require(harness.state.with { $0.snapshots["otlp"] })
    #expect(snapshot.unacknowledgedSecurityEventCount == 1)
    #expect(snapshot.state == .noExportsYet)
    #expect(harness.ledger.map(\.detail) == ["explicit_user_opt_in otlp"])

    harness.service.disableOTLP()
    #expect(harness.service.storedOTLPURL() == "")
    #expect(harness.state.with { $0.snapshots["otlp"] } == nil)
    #expect(harness.state.with { $0.widgetReloads } == 2)
}

// MARK: Portable configuration

@Test func setupPortableConfigurationListsOnlyEnabledDestinationsWithoutSecrets() async throws {
    let harness = Harness()
    try harness.configureScope("https")
    try harness.configureScope("mqtt")
    harness.state.with {
        $0.https["https"] = pendingHTTPS().record(propagateTraceparent: false)
        var failed = pendingHTTPS(destinationID: "home-assistant").record(propagateTraceparent: false)
        failed.report = .failed(at: .sendCanary)
        $0.https["home-assistant"] = failed
        $0.mqtt = pendingMQTT().record()
    }
    let configurations = try await harness.service.portableConfigurations()
    #expect(configurations.map(\.kind) == [.https, .mqtt])
    #expect(configurations[0].displayName == "nas.local")
    #expect(configurations[0].settings == ["allowInsecureHTTP": "false", "method": "POST"])
    #expect(configurations[1].sourceIdentifier == "imported-7")
    #expect(configurations[1].settings["qos"] == "1")
    #expect(configurations[1].exportScope.metrics == [heartRate])

    let document = String(decoding: try await harness.service.portableConfigurationDocument(), as: UTF8.self)
    #expect(!document.contains("secret-token"))
    #expect(!document.contains("broker-pass"))
}
