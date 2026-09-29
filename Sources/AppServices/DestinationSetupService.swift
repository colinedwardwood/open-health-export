// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CorrectnessEngine
import DestinationTrust
import EnginePorts
import Foundation
import NetEgress
import Watchdog
import WireFormat

// MARK: Saved verification records (file formats unchanged; moved from the app target)

public struct HTTPSVerificationRecord: Codable, Sendable, Equatable {
    public var urlString: String
    public var allowedHosts: [String]
    public var allowInsecureHTTP: Bool
    public var report: DestinationTestReport
    public var leafSPKISha256: String?
    public var issuerSPKISha256: String?
    public var firstSeen: String
    public var hasBearer: Bool
    public var bearerDescriptor: StoredCredentialDescriptor?
    public var webhookDescriptor: StoredCredentialDescriptor?
    public var propagateTraceparent: Bool?
    public var importedLocalIdentifier: String?

    public init(
        urlString: String,
        allowedHosts: [String],
        allowInsecureHTTP: Bool,
        report: DestinationTestReport,
        leafSPKISha256: String?,
        issuerSPKISha256: String?,
        firstSeen: String,
        hasBearer: Bool,
        bearerDescriptor: StoredCredentialDescriptor?,
        webhookDescriptor: StoredCredentialDescriptor?,
        propagateTraceparent: Bool?,
        importedLocalIdentifier: String?
    ) {
        self.urlString = urlString
        self.allowedHosts = allowedHosts
        self.allowInsecureHTTP = allowInsecureHTTP
        self.report = report
        self.leafSPKISha256 = leafSPKISha256
        self.issuerSPKISha256 = issuerSPKISha256
        self.firstSeen = firstSeen
        self.hasBearer = hasBearer
        self.bearerDescriptor = bearerDescriptor
        self.webhookDescriptor = webhookDescriptor
        self.propagateTraceparent = propagateTraceparent
        self.importedLocalIdentifier = importedLocalIdentifier
    }

    /// The certificate the person confirmed at setup; every later send is held to it.
    public var pin: PinRecord? {
        guard let leafSPKISha256, let issuerSPKISha256 else { return nil }
        return PinRecord(
            leafSPKISha256: leafSPKISha256,
            issuerSPKISha256: issuerSPKISha256,
            firstSeen: firstSeen,
            policy: .leaf
        )
    }
}

public struct MQTTVerificationRecord: Codable, Sendable, Equatable {
    public var urlString: String
    public var allowedHosts: [String]
    public var allowInsecure: Bool
    public var clientID: String
    public var topic: String
    public var qos: UInt8?
    public var report: DestinationTestReport
    public var hasClientPKCS12: Bool?
    public var hasClientPKCS12Password: Bool?
    /// Pre-Keychain JSON copies. Read on launch, then rewritten off disk.
    public var clientPKCS12Password: String?
    public var username: String?
    public var hasPassword: Bool?
    public var passwordDescriptor: StoredCredentialDescriptor?
    public var pkcs12PasswordDescriptor: StoredCredentialDescriptor?
    public var leafSPKISha256: String?
    public var issuerSPKISha256: String?
    public var firstSeen: String?
    public var importedLocalIdentifier: String?

    public init(
        urlString: String,
        allowedHosts: [String],
        allowInsecure: Bool,
        clientID: String,
        topic: String,
        qos: UInt8?,
        report: DestinationTestReport,
        hasClientPKCS12: Bool?,
        hasClientPKCS12Password: Bool?,
        clientPKCS12Password: String?,
        username: String?,
        hasPassword: Bool?,
        passwordDescriptor: StoredCredentialDescriptor?,
        pkcs12PasswordDescriptor: StoredCredentialDescriptor?,
        leafSPKISha256: String?,
        issuerSPKISha256: String?,
        firstSeen: String?,
        importedLocalIdentifier: String?
    ) {
        self.urlString = urlString
        self.allowedHosts = allowedHosts
        self.allowInsecure = allowInsecure
        self.clientID = clientID
        self.topic = topic
        self.qos = qos
        self.report = report
        self.hasClientPKCS12 = hasClientPKCS12
        self.hasClientPKCS12Password = hasClientPKCS12Password
        self.clientPKCS12Password = clientPKCS12Password
        self.username = username
        self.hasPassword = hasPassword
        self.passwordDescriptor = passwordDescriptor
        self.pkcs12PasswordDescriptor = pkcs12PasswordDescriptor
        self.leafSPKISha256 = leafSPKISha256
        self.issuerSPKISha256 = issuerSPKISha256
        self.firstSeen = firstSeen
        self.importedLocalIdentifier = importedLocalIdentifier
    }

    /// Records written before `firstSeen` existed pin from the epoch.
    public var pin: PinRecord? {
        guard let leafSPKISha256, let issuerSPKISha256 else { return nil }
        return PinRecord(
            leafSPKISha256: leafSPKISha256,
            issuerSPKISha256: issuerSPKISha256,
            firstSeen: firstSeen ?? "1970-01-01T00:00:00Z",
            policy: .leaf
        )
    }
}

public struct CompanionVerificationRecord: Codable, Sendable, Equatable {
    public var serviceName: String
    public var macInstallationID: String
    public var report: DestinationTestReport
    public var propagateTraceparent: Bool?

    public init(
        serviceName: String,
        macInstallationID: String,
        report: DestinationTestReport,
        propagateTraceparent: Bool?
    ) {
        self.serviceName = serviceName
        self.macInstallationID = macInstallationID
        self.report = report
        self.propagateTraceparent = propagateTraceparent
    }
}

public struct OTLPDestinationRecord: Codable, Sendable, Equatable {
    public var urlString: String
    public var allowedHosts: [String]
    public var allowInsecureHTTP: Bool
    public var previewDigest: String

    public init(urlString: String, allowedHosts: [String], allowInsecureHTTP: Bool, previewDigest: String) {
        self.urlString = urlString
        self.allowedHosts = allowedHosts
        self.allowInsecureHTTP = allowInsecureHTTP
        self.previewDigest = previewDigest
    }
}

// MARK: Pending drafts

/// What a destination probe proved, kept until the person confirms or cancels. Only
/// the parts confirmation needs; the probe's live connection stays with the app.
public struct DestinationProbeResult: Sendable {
    public var destinationURL: URL
    public var report: DestinationTestReport
    public var identity: TLSIdentity?
    public var preview: Data
    public var pendingEvents: [TrustEvent]

    public init(
        destinationURL: URL,
        report: DestinationTestReport,
        identity: TLSIdentity?,
        preview: Data,
        pendingEvents: [TrustEvent]
    ) {
        self.destinationURL = destinationURL
        self.report = report
        self.identity = identity
        self.preview = preview
        self.pendingEvents = pendingEvents
    }
}

/// An HTTPS or Home Assistant destination that passed its probe and waits for the
/// person to confirm the server.
public struct PendingHTTPSDestination: Sendable {
    public var probe: DestinationProbeResult
    public var destinationID: String
    public var destinationLabel: String
    public var host: String
    public var allowedHosts: [String]
    public var allowInsecureHTTP: Bool
    public var bearer: String?
    public var webhookID: String?
    /// Home Assistant saves its base URL; the webhook ID lives in the Keychain.
    public var persistedURLString: String?
    public var firstSeen: String
    public var importedLocalIdentifier: String?

    public init(
        probe: DestinationProbeResult,
        destinationID: String,
        destinationLabel: String,
        host: String,
        allowedHosts: [String],
        allowInsecureHTTP: Bool,
        bearer: String?,
        webhookID: String?,
        persistedURLString: String?,
        firstSeen: String,
        importedLocalIdentifier: String?
    ) {
        self.probe = probe
        self.destinationID = destinationID
        self.destinationLabel = destinationLabel
        self.host = host
        self.allowedHosts = allowedHosts
        self.allowInsecureHTTP = allowInsecureHTTP
        self.bearer = bearer
        self.webhookID = webhookID
        self.persistedURLString = persistedURLString
        self.firstSeen = firstSeen
        self.importedLocalIdentifier = importedLocalIdentifier
    }

    public var confirmationCard: DestinationConfirmationCard {
        DestinationSetupService.card(
            host: host,
            probe: probe,
            allowInsecure: allowInsecureHTTP
        )
    }

    /// The saved record: descriptors of the secrets, never the secrets themselves.
    public func record(propagateTraceparent: Bool) -> HTTPSVerificationRecord {
        HTTPSVerificationRecord(
            urlString: persistedURLString ?? probe.destinationURL.absoluteString,
            allowedHosts: allowedHosts,
            allowInsecureHTTP: allowInsecureHTTP,
            report: probe.report,
            leafSPKISha256: probe.identity?.leafSPKISha256,
            issuerSPKISha256: probe.identity?.issuerSPKISha256,
            firstSeen: firstSeen,
            hasBearer: bearer != nil,
            bearerDescriptor: StoredCredentialDescriptor.capturing(
                bearer,
                appearance: .bearerToken,
                addedOnDay: firstSeen
            ),
            webhookDescriptor: StoredCredentialDescriptor.capturing(
                webhookID,
                appearance: .webhookID,
                addedOnDay: firstSeen
            ),
            propagateTraceparent: propagateTraceparent,
            importedLocalIdentifier: importedLocalIdentifier
        )
    }
}

/// An MQTT destination that passed its probe and waits for confirmation.
public struct PendingMQTTDestination: Sendable {
    public var probe: DestinationProbeResult
    public var host: String
    public var allowedHosts: [String]
    public var allowInsecure: Bool
    public var clientID: String
    public var topic: String
    public var qos: UInt8
    public var clientPKCS12: Data?
    public var clientPKCS12Password: String?
    public var username: String?
    public var password: String?
    public var firstSeen: String
    public var importedLocalIdentifier: String?

    public init(
        probe: DestinationProbeResult,
        host: String,
        allowedHosts: [String],
        allowInsecure: Bool,
        clientID: String,
        topic: String,
        qos: UInt8,
        clientPKCS12: Data?,
        clientPKCS12Password: String?,
        username: String?,
        password: String?,
        firstSeen: String,
        importedLocalIdentifier: String?
    ) {
        self.probe = probe
        self.host = host
        self.allowedHosts = allowedHosts
        self.allowInsecure = allowInsecure
        self.clientID = clientID
        self.topic = topic
        self.qos = qos
        self.clientPKCS12 = clientPKCS12
        self.clientPKCS12Password = clientPKCS12Password
        self.username = username
        self.password = password
        self.firstSeen = firstSeen
        self.importedLocalIdentifier = importedLocalIdentifier
    }

    public var confirmationCard: DestinationConfirmationCard {
        DestinationSetupService.card(host: host, probe: probe, allowInsecure: allowInsecure)
    }

    /// The saved record. The PKCS#12 password goes to the Keychain, so the JSON copy
    /// is always nil.
    public func record() -> MQTTVerificationRecord {
        MQTTVerificationRecord(
            urlString: probe.destinationURL.absoluteString,
            allowedHosts: allowedHosts,
            allowInsecure: allowInsecure,
            clientID: clientID,
            topic: topic,
            qos: qos,
            report: probe.report,
            hasClientPKCS12: clientPKCS12 != nil,
            hasClientPKCS12Password: clientPKCS12Password != nil,
            clientPKCS12Password: nil,
            username: username,
            hasPassword: password != nil,
            passwordDescriptor: StoredCredentialDescriptor.capturing(
                password,
                appearance: .password,
                addedOnDay: firstSeen
            ),
            pkcs12PasswordDescriptor: StoredCredentialDescriptor.capturing(
                clientPKCS12Password,
                appearance: .pkcs12Password,
                addedOnDay: firstSeen
            ),
            leafSPKISha256: probe.identity?.leafSPKISha256,
            issuerSPKISha256: probe.identity?.issuerSPKISha256,
            firstSeen: firstSeen,
            importedLocalIdentifier: importedLocalIdentifier
        )
    }
}

/// The one draft of each kind waiting for confirmation. A new probe replaces the old
/// draft; confirming takes it, so a second confirmation needs a new probe.
public actor PendingDestinationDrafts {
    private var https: PendingHTTPSDestination?
    private var mqtt: PendingMQTTDestination?

    public init() {}

    public func setHTTPS(_ value: PendingHTTPSDestination?) { https = value }

    public func takeHTTPS() -> PendingHTTPSDestination? {
        defer { https = nil }
        return https
    }

    public func setMQTT(_ value: PendingMQTTDestination?) { mqtt = value }

    public func takeMQTT() -> PendingMQTTDestination? {
        defer { mqtt = nil }
        return mqtt
    }
}

// MARK: Trust on first use (#66)

/// How an MQTT probe treats the broker's certificate. The first attempt may only read
/// an untrusted certificate, which surfaces as `TrustConfirmation.required` before any
/// canary is sent; once the person confirms it, the retry is pinned to exactly that
/// certificate.
public enum MQTTProbeTrust: Sendable, Equatable {
    case captureUntrustedIdentity
    case pinned(PinRecord)

    public static func forConfirmed(_ identity: TLSIdentity?, firstSeen: String) -> MQTTProbeTrust {
        guard let identity else { return .captureUntrustedIdentity }
        return .pinned(PinRecord(
            leafSPKISha256: identity.leafSPKISha256,
            issuerSPKISha256: identity.issuerSPKISha256,
            firstSeen: firstSeen,
            policy: .leaf
        ))
    }
}

// MARK: Ports

/// The destination setup files in Application Support. Reads fail soft to nil.
public protocol DestinationSetupFiles: Sendable {
    func httpsRecord(_ destinationID: String) -> HTTPSVerificationRecord?
    func writeHTTPSRecord(_ record: HTTPSVerificationRecord, destinationID: String) throws
    func mqttRecord() -> MQTTVerificationRecord?
    func writeMQTTRecord(_ record: MQTTVerificationRecord) throws
    /// Writes the client certificate, or removes the saved one when nil.
    func writeMQTTClientCertificate(_ pkcs12: Data?) throws
    func companionRecord() -> CompanionVerificationRecord?
    func writeCompanionRecord(_ record: CompanionVerificationRecord) throws
    func removeCompanionRecord()
    func localFileTestReport() -> DestinationTestReport?
    func writeLocalFileTestReport(_ report: DestinationTestReport) throws
    func removeLocalFileTestReport()
    func otlpRecord() -> OTLPDestinationRecord?
    func writeOTLPRecord(_ record: OTLPDestinationRecord) throws
    func removeOTLPRecord()
}

/// The status snapshots setup touches, and the widget that shows them.
public protocol SetupStatusSnapshots: Sendable {
    func readAll() -> [DestinationStatusSnapshot]
    /// Adds security events to a destination's snapshot, creating it when missing;
    /// `enabled` and `state` overwrite when given. A zero count does nothing.
    func recordSecurityEvents(
        _ count: Int,
        destinationID: String,
        destinationLabel: String?,
        enabled: Bool?,
        state: DestinationDisplayState?,
        writtenAtEpoch: TimeInterval
    ) throws
    func write(_ snapshot: DestinationStatusSnapshot) throws
    func remove(destinationID: String)
    func reloadStatusWidget()
}

extension SetupStatusSnapshots {
    func recordSecurityEvents(
        _ count: Int,
        destinationID: String,
        destinationLabel: String?,
        writtenAtEpoch: TimeInterval
    ) throws {
        try recordSecurityEvents(
            count,
            destinationID: destinationID,
            destinationLabel: destinationLabel,
            enabled: nil,
            state: nil,
            writtenAtEpoch: writtenAtEpoch
        )
    }
}

// MARK: Service

/// Adding and verifying destinations (#42): the confirmation card, what is saved when
/// the person confirms, the trust notices setup raises, and the portable configuration
/// export. Probing a server, the Keychain and file paths stay with the app behind ports.
public struct DestinationSetupService: Sendable {
    public let drafts: PendingDestinationDrafts
    private let repository: DestinationRepository
    private let files: any DestinationSetupFiles
    private let snapshots: any SetupStatusSnapshots
    private let secrets: @Sendable (_ service: String) -> any SecretStore
    private let notifier: any UserNotifier
    private let store: @Sendable () throws -> any StateStore
    private let authorizeScope: @Sendable (DestinationExportScope) async throws -> Void
    private let forgetPairing: @Sendable () async throws -> Void
    private let now: @Sendable () -> Date

    public init(
        drafts: PendingDestinationDrafts = PendingDestinationDrafts(),
        repository: DestinationRepository,
        files: any DestinationSetupFiles,
        snapshots: any SetupStatusSnapshots,
        secrets: @escaping @Sendable (_ service: String) -> any SecretStore,
        notifier: any UserNotifier,
        store: @escaping @Sendable () throws -> any StateStore,
        authorizeScope: @escaping @Sendable (DestinationExportScope) async throws -> Void,
        forgetPairing: @escaping @Sendable () async throws -> Void,
        now: @escaping @Sendable () -> Date
    ) {
        self.drafts = drafts
        self.repository = repository
        self.files = files
        self.snapshots = snapshots
        self.secrets = secrets
        self.notifier = notifier
        self.store = store
        self.authorizeScope = authorizeScope
        self.forgetPairing = forgetPairing
        self.now = now
    }

    // MARK: Pure rules

    /// The host a destination is allowed to reach: the URL's own host, lowercased.
    public static func host(of urlString: String) throws -> String {
        guard let host = URL(string: urlString)?.host?.lowercased(), !host.isEmpty else {
            throw EgressError.invalidURL
        }
        return host
    }

    /// A transport without TLS is only described as unencrypted when the person opted in.
    public static func card(
        host: String,
        probe: DestinationProbeResult,
        allowInsecure: Bool
    ) -> DestinationConfirmationCard {
        DestinationConfirmationCard(
            host: host,
            identity: probe.identity,
            preview: probe.preview,
            insecureWithoutTLS: allowInsecure && probe.identity == nil
        )
    }

    /// What the person sees after confirming: the card, then each test step's outcome.
    public static func confirmedLines(
        card: DestinationConfirmationCard,
        report: DestinationTestReport
    ) -> [String] {
        card.lines + report.steps.map { "\($0.name.rawValue): \($0.outcome.rawValue)" }
    }

    /// OTLP metrics go beside the traces endpoint: `/v1/traces` becomes `/v1/metrics`,
    /// and any other path gains `/v1/metrics`.
    public static func otlpMetricsURL(tracesURL: URL) -> URL? {
        var components = URLComponents(url: tracesURL, resolvingAgainstBaseURL: false)
        if components?.path.hasSuffix("/v1/traces") == true {
            components?.path.removeLast("traces".count)
            components?.path.append("metrics")
        } else {
            let path = components?.path ?? ""
            components?.path = path.hasSuffix("/") ? "\(path)v1/metrics" : "\(path)/v1/metrics"
        }
        return components?.url
    }

    // MARK: HTTPS and Home Assistant

    public func stageHTTPS(_ pending: PendingHTTPSDestination) async -> DestinationConfirmationCard {
        await drafts.setHTTPS(pending)
        return pending.confirmationCard
    }

    public func cancelHTTPS() async {
        await drafts.setHTTPS(nil)
    }

    /// Saves the confirmed destination: secrets to the Keychain, the record beside
    /// them, the trust events to status and notifications, then the Health request.
    public func confirmHTTPS(propagateTraceparent: Bool = false) async throws -> [String] {
        guard let pending = await drafts.takeHTTPS() else {
            throw SetupError.verificationRequired
        }
        try ExportScopeGate.requireConfigured(try await repository.scope(pending.destinationID))
        let events = pending.probe.pendingEvents + [.destinationEnabled]
        let record = pending.record(propagateTraceparent: propagateTraceparent)
        let secretStore = secrets(DestinationRepository.keychainService(pending.destinationID))
        try await replace(pending.bearer, handle: "bearer", in: secretStore)
        try await replace(pending.webhookID, handle: "webhook-id", in: secretStore)
        try files.writeHTTPSRecord(record, destinationID: pending.destinationID)
        try snapshots.recordSecurityEvents(
            events.count,
            destinationID: pending.destinationID,
            destinationLabel: pending.destinationLabel,
            writtenAtEpoch: now().timeIntervalSince1970
        )
        try await emitTrustNotices(events, destination: pending.destinationLabel)
        try await requestScopeAuthorization(pending.destinationID)
        if pending.allowInsecureHTTP {
            try await appendSecurityLedger(
                destination: pending.host,
                outcomeKind: "security:insecure_http_enabled",
                detail: "explicit_user_opt_in"
            )
        }
        return Self.confirmedLines(card: pending.confirmationCard, report: pending.probe.report)
    }

    // MARK: MQTT

    public func stageMQTT(_ pending: PendingMQTTDestination) async -> DestinationConfirmationCard {
        await drafts.setMQTT(pending)
        return pending.confirmationCard
    }

    public func cancelMQTT() async {
        await drafts.setMQTT(nil)
    }

    /// The scope is checked before the draft is taken, so a refusal keeps the draft.
    public func confirmMQTT() async throws -> [String] {
        try ExportScopeGate.requireConfigured(try await repository.scope("mqtt"))
        guard let pending = await drafts.takeMQTT() else {
            throw SetupError.verificationRequired
        }
        let events = pending.probe.pendingEvents + [.destinationEnabled]
        let record = pending.record()
        try files.writeMQTTClientCertificate(pending.clientPKCS12)
        let secretStore = secrets(IdentifierRoot.qualified("mqtt"))
        try await replace(pending.password, handle: "mqtt_password", in: secretStore)
        try await replace(pending.clientPKCS12Password, handle: "mqtt_pkcs12_password", in: secretStore)
        try files.writeMQTTRecord(record)
        try snapshots.recordSecurityEvents(
            events.count,
            destinationID: "mqtt",
            destinationLabel: pending.host,
            writtenAtEpoch: now().timeIntervalSince1970
        )
        try await emitTrustNotices(events, destination: pending.host)
        try await requestScopeAuthorization("mqtt")
        if pending.allowInsecure {
            try await appendSecurityLedger(
                destination: pending.host,
                outcomeKind: "security:insecure_mqtt_enabled",
                detail: "explicit_user_opt_in"
            )
        }
        return Self.confirmedLines(card: pending.confirmationCard, report: pending.probe.report)
    }

    // MARK: Local folder

    /// A passed test is resumed rather than rerun.
    public func resumableLocalFileReport() -> DestinationTestReport? {
        files.localFileTestReport().flatMap { $0.allowsEnablement ? $0 : nil }
    }

    public func forgetLocalFileTest() {
        files.removeLocalFileTestReport()
    }

    public func recordLocalFileTest(
        _ report: DestinationTestReport,
        events: [TrustEvent],
        destinationLabel: String
    ) throws {
        try files.writeLocalFileTestReport(report)
        try snapshots.recordSecurityEvents(
            events.count,
            destinationID: "local-file",
            destinationLabel: destinationLabel,
            writtenAtEpoch: now().timeIntervalSince1970
        )
    }

    // MARK: Mac companion

    /// The saved test is reused only for the same Mac, under the same name, and only
    /// when it passed.
    public func resumableCompanionReport(
        serviceName: String,
        macInstallationID: String
    ) -> DestinationTestReport? {
        guard let saved = files.companionRecord(),
              saved.serviceName == serviceName,
              saved.macInstallationID == macInstallationID,
              saved.report.allowsEnablement
        else { return nil }
        return saved.report
    }

    public func recordCompanionTest(
        _ record: CompanionVerificationRecord,
        events: [TrustEvent]
    ) async throws {
        try files.writeCompanionRecord(record)
        try snapshots.recordSecurityEvents(
            events.count,
            destinationID: "companion",
            destinationLabel: "Mac companion · \(record.serviceName)",
            writtenAtEpoch: now().timeIntervalSince1970
        )
        try await emitTrustNotices(events, destination: record.serviceName)
    }

    /// Forgetting the Mac drops its key and test, blocks the destination, and says so.
    public func forgetCompanion() async throws {
        try await forgetPairing()
        files.removeCompanionRecord()
        try snapshots.recordSecurityEvents(
            1,
            destinationID: "companion",
            destinationLabel: "Mac companion",
            enabled: false,
            state: .blocked,
            writtenAtEpoch: now().timeIntervalSince1970
        )
        try await emitTrustNotices([.trustLost], destination: "companion")
        snapshots.reloadStatusWidget()
    }

    // MARK: OTLP

    public func storedOTLPURL() -> String {
        files.otlpRecord()?.urlString ?? ""
    }

    /// Saves a collector whose preview the person has seen. The endpoint was already
    /// validated by the OTLP settings gate.
    public func enableOTLP(
        endpoint: URL,
        host: String,
        allowInsecureHTTP: Bool,
        previewPayload: Data
    ) async throws {
        try files.writeOTLPRecord(OTLPDestinationRecord(
            urlString: endpoint.absoluteString,
            allowedHosts: [host],
            allowInsecureHTTP: allowInsecureHTTP,
            previewDigest: ContentSHA256.digest(previewPayload)
        ))
        let epoch = now().timeIntervalSince1970
        try snapshots.write(DestinationStatusSnapshot(
            destinationID: "otlp",
            destinationLabel: host,
            enabled: true,
            state: .noExportsYet,
            unacknowledgedSecurityEventCount: allowInsecureHTTP ? 1 : 0,
            writtenAtEpoch: epoch
        ))
        if allowInsecureHTTP {
            try await appendSecurityLedger(
                destination: host,
                outcomeKind: "security:insecure_http_enabled",
                detail: "explicit_user_opt_in otlp",
                at: epoch
            )
        }
        snapshots.reloadStatusWidget()
    }

    public func disableOTLP() {
        files.removeOTLPRecord()
        snapshots.remove(destinationID: "otlp")
        snapshots.reloadStatusWidget()
    }

    // MARK: Portable configuration

    /// Every enabled destination's settings and scope, never its credentials (SEC-18).
    public func portableConfigurations() async throws -> [PortableDestinationConfiguration] {
        var destinations: [PortableDestinationConfiguration] = []
        if let record = files.httpsRecord("https"), record.report.allowsEnablement {
            destinations.append(try await PortableDestinationConfiguration(
                sourceIdentifier: record.importedLocalIdentifier ?? "https",
                displayName: URL(string: record.urlString)?.host ?? "HTTPS",
                kind: .https,
                endpoint: record.urlString,
                settings: [
                    "allowInsecureHTTP": record.allowInsecureHTTP ? "true" : "false",
                    "method": "POST",
                ],
                exportScope: portableScope("https")
            ))
        }
        if let record = files.httpsRecord("home-assistant"),
           record.report.allowsEnablement,
           let baseURL = URL(string: record.urlString) {
            destinations.append(try await PortableDestinationConfiguration(
                sourceIdentifier: record.importedLocalIdentifier ?? "home-assistant",
                displayName: baseURL.host ?? "Home Assistant",
                kind: .homeAssistant,
                endpoint: baseURL.absoluteString,
                settings: [
                    "allowInsecureHTTP": record.allowInsecureHTTP ? "true" : "false",
                    "mode": "webhook",
                ],
                exportScope: portableScope("home-assistant")
            ))
        }
        if let record = files.mqttRecord(), record.report.allowsEnablement {
            destinations.append(try await PortableDestinationConfiguration(
                sourceIdentifier: record.importedLocalIdentifier ?? "mqtt",
                displayName: URL(string: record.urlString)?.host ?? "MQTT",
                kind: .mqtt,
                endpoint: record.urlString,
                settings: [
                    "allowInsecure": record.allowInsecure ? "true" : "false",
                    "clientID": record.clientID,
                    "qos": String(record.qos ?? 1),
                    "topic": record.topic,
                ],
                exportScope: portableScope("mqtt")
            ))
        }
        if let record = files.companionRecord(), record.report.allowsEnablement {
            destinations.append(try await PortableDestinationConfiguration(
                sourceIdentifier: "companion",
                displayName: record.serviceName,
                kind: .companion,
                endpoint: record.serviceName,
                settings: ["serviceName": record.serviceName],
                exportScope: portableScope("companion")
            ))
        }
        return destinations
    }

    public func portableConfigurationDocument() async throws -> Data {
        try await DestinationConfigurationDocument(destinations: portableConfigurations()).encoded()
    }

    // MARK: Trust notices

    /// Posts one notice per event. When notifications are denied, the suppression is
    /// recorded in the ledger and as a security event on the destination it concerns.
    public func emitTrustNotices(_ events: [TrustEvent], destination: String) async throws {
        guard !events.isEmpty else { return }
        let deliveries = try await TrustNoticePosting.post(
            events: events,
            destination: destination,
            notifier: notifier
        )
        let suppressed = TrustNoticePosting.suppressedCount(deliveries)
        guard suppressed > 0 else { return }
        try await appendSecurityLedger(
            destination: destination,
            outcomeKind: "security:notifications_denied",
            detail: "trust_notice_suppressed:\(suppressed)"
        )
        for snapshot in snapshots.readAll() where snapshot.destinationLabel == destination {
            try snapshots.recordSecurityEvents(
                suppressed,
                destinationID: snapshot.destinationID,
                destinationLabel: snapshot.destinationLabel,
                writtenAtEpoch: now().timeIntervalSince1970
            )
        }
        snapshots.reloadStatusWidget()
    }

    /// Asks Health for the types this destination's scope names.
    public func requestScopeAuthorization(_ destinationID: String) async throws {
        try await authorizeScope(try await repository.scope(destinationID))
    }

    // MARK: Helpers

    private func portableScope(_ destinationID: String) async throws -> PortableDestinationExportScope {
        let scope = try await repository.scope(destinationID)
        return try PortableDestinationExportScope(
            metrics: scope.metrics.sorted { $0.rawValue < $1.rawValue },
            startInclusive: scope.startInclusive,
            endExclusive: scope.endExclusive
        )
    }

    /// A present secret is stored; an absent one removes whatever an earlier setup left.
    private func replace(_ value: String?, handle: String, in store: any SecretStore) async throws {
        let handle = SecretHandle(rawValue: handle)
        if let value {
            try await store.store(Array(value.utf8), handle: handle)
        } else {
            try? await store.delete(handle)
        }
    }

    private func appendSecurityLedger(
        destination: String,
        outcomeKind: String,
        detail: String,
        at epoch: TimeInterval? = nil
    ) async throws {
        let entry = EgressEntry(
            destination: destination,
            sampleCount: 0,
            outcomeKind: outcomeKind,
            detail: detail,
            wallTimeEpoch: epoch ?? now().timeIntervalSince1970
        )
        try await store().transact { try $0.appendLedger(entry) }
    }
}
