// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppServices
import CompanionWire
import CoreDomain
import CorrectnessEngine
import DestinationTrust
import EnginePorts
import FileWriteKit
import Foundation
import NetEgress
#if !OHE_OBS25_SIZE_BASELINE
import OTLPExport
#endif
import SinkCompanion
import SinkHTTP
import SinkLocalFile
import SinkMQTT
import StorageSQLite
import Watchdog
import WidgetKit

// MARK: Storage adapters

/// The setup sidecars in Application Support. The MQTT client certificate and the
/// OTLP record live beside the verification records.
struct DestinationSetupFileStore: DestinationSetupFiles {
    let root: @Sendable () throws -> URL

    static let mqttClientCertificate = "mqtt-client.p12"
    static let otlpRecord = "otlp-destination.json"

    func httpsRecord(_ destinationID: String) -> HTTPSVerificationRecord? {
        read(HTTPSVerificationRecord.self, DestinationSidecar.httpsRecord(destinationID: destinationID).filename)
    }

    func writeHTTPSRecord(_ record: HTTPSVerificationRecord, destinationID: String) throws {
        try write(record, DestinationSidecar.httpsRecord(destinationID: destinationID).filename)
    }

    func mqttRecord() -> MQTTVerificationRecord? {
        read(MQTTVerificationRecord.self, DestinationSidecar.mqttRecord.filename)
    }

    func writeMQTTRecord(_ record: MQTTVerificationRecord) throws {
        try write(record, DestinationSidecar.mqttRecord.filename)
    }

    func writeMQTTClientCertificate(_ pkcs12: Data?) throws {
        let url = try root().appendingPathComponent(Self.mqttClientCertificate)
        if let pkcs12 {
            try pkcs12.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func companionRecord() -> CompanionVerificationRecord? {
        read(CompanionVerificationRecord.self, DestinationSidecar.companionTestReport.filename)
    }

    func writeCompanionRecord(_ record: CompanionVerificationRecord) throws {
        try write(record, DestinationSidecar.companionTestReport.filename)
    }

    func removeCompanionRecord() {
        remove(DestinationSidecar.companionTestReport.filename)
    }

    func localFileTestReport() -> DestinationTestReport? {
        read(DestinationTestReport.self, DestinationSidecar.localFileTestReport.filename)
    }

    func writeLocalFileTestReport(_ report: DestinationTestReport) throws {
        try write(report, DestinationSidecar.localFileTestReport.filename)
    }

    func removeLocalFileTestReport() {
        remove(DestinationSidecar.localFileTestReport.filename)
    }

    func otlpRecord() -> OTLPDestinationRecord? {
        read(OTLPDestinationRecord.self, Self.otlpRecord)
    }

    func writeOTLPRecord(_ record: OTLPDestinationRecord) throws {
        try write(record, Self.otlpRecord)
    }

    func removeOTLPRecord() {
        remove(Self.otlpRecord)
    }

    private func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let root = try? root(),
              let data = try? Data(contentsOf: root.appendingPathComponent(name))
        else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, _ name: String) throws {
        try JSONEncoder().encode(value).write(
            to: try root().appendingPathComponent(name),
            options: .atomic
        )
    }

    private func remove(_ name: String) {
        guard let root = try? root() else { return }
        try? FileManager.default.removeItem(at: root.appendingPathComponent(name))
    }
}

/// Status snapshots in the shared container, and the widget that reads them.
struct SharedContainerSetupSnapshots: SetupStatusSnapshots {
    func readAll() -> [DestinationStatusSnapshot] {
        StatusSnapshotLocation.readAll()
    }

    func recordSecurityEvents(
        _ count: Int,
        destinationID: String,
        destinationLabel: String?,
        enabled: Bool?,
        state: DestinationDisplayState?,
        writtenAtEpoch: TimeInterval
    ) throws {
        guard let url = StatusSnapshotLocation.url(destinationID: destinationID) else { return }
        try DestinationSnapshotFile.recordSecurityEvents(
            count,
            destinationID: destinationID,
            destinationLabel: destinationLabel,
            enabled: enabled,
            state: state,
            writtenAtEpoch: writtenAtEpoch,
            at: url
        )
    }

    func write(_ snapshot: DestinationStatusSnapshot) throws {
        guard let url = StatusSnapshotLocation.url(destinationID: snapshot.destinationID) else { return }
        try DestinationSnapshotFile.write(snapshot, to: url)
    }

    func remove(destinationID: String) {
        guard let url = StatusSnapshotLocation.url(destinationID: destinationID) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func reloadStatusWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
    }
}

// MARK: Setup flows

/// Adding and verifying destinations (#42). The probes, Keychain reads and sinks live
/// here; what is decided and saved lives in `DestinationSetupService`.
enum AppDestinationSetup {
    private static let root: @Sendable () throws -> URL = { try HarnessExport.applicationSupportRoot() }

    static let files = DestinationSetupFileStore(root: root)

    static let service = DestinationSetupService(
        repository: AppDestinations.repository,
        files: files,
        snapshots: SharedContainerSetupSnapshots(),
        secrets: { KeychainSecretStore(service: $0) },
        notifier: LocalUserNotifier(),
        store: {
            try StateStoreHost.store(path: root().appendingPathComponent("state.sqlite").path)
        },
        authorizeScope: { try await AppHealth.service.requestReadAccess(for: $0) },
        forgetPairing: { try await HarnessExport.vault().forget() },
        now: { Date() }
    )

    // MARK: HTTPS and Home Assistant

    static func prepareHomeAssistantWebhook(
        baseURLString: String,
        webhookID: String,
        allowInsecureHTTP: Bool,
        importedLocalIdentifier: String?,
        confirmedLeafSPKISha256: String?,
        onProgress: DestinationTestProgress?
    ) async throws -> DestinationConfirmationCard {
        let endpoint = try HomeAssistantWebhookPreset.endpoint(
            baseURLString: baseURLString,
            webhookID: webhookID
        )
        return try await prepareHTTPS(
            urlString: endpoint.absoluteString,
            allowInsecureHTTP: allowInsecureHTTP,
            bearer: nil,
            destinationID: "home-assistant",
            destinationLabel: "Home Assistant",
            webhookID: webhookID,
            persistedURLString: try HomeAssistantWebhookPreset.baseURL(from: endpoint).absoluteString,
            importedLocalIdentifier: importedLocalIdentifier,
            confirmedLeafSPKISha256: confirmedLeafSPKISha256,
            onProgress: onProgress
        )
    }

    /// Probes the server and stages a draft. An untrusted certificate throws
    /// `TrustConfirmation.required` before any canary; the retry passes the fingerprint
    /// the person confirmed (#66).
    static func prepareHTTPS(
        urlString: String,
        allowInsecureHTTP: Bool,
        bearer: String?,
        destinationID: String,
        destinationLabel: String,
        webhookID: String?,
        persistedURLString: String?,
        importedLocalIdentifier: String?,
        confirmedLeafSPKISha256: String?,
        onProgress: DestinationTestProgress?
    ) async throws -> DestinationConfirmationCard {
        let host = try DestinationSetupService.host(of: urlString)
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
        let probe = try await HarnessExport.withThermalCompression {
            try await HTTPSDestinationEnable.probe(
                destination: destination,
                transport: transport,
                exporterID: try HarnessExport.installationID(),
                emittedAt: now,
                meteredPolicy: .fromAllowsMetered(
                    HarnessExport.allowsMeteredNetwork(destinationID: destinationID)
                ),
                pathConditions: HarnessExport.networkPathConditions(),
                confirmedLeafSPKISha256: confirmedLeafSPKISha256,
                onProgress: onProgress
            )
        }
        return await service.stageHTTPS(PendingHTTPSDestination(
            probe: DestinationProbeResult(
                destinationURL: probe.destination.url,
                report: probe.report,
                identity: probe.identity,
                preview: probe.preview,
                pendingEvents: probe.pendingEvents
            ),
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
    }

    /// Rebuilds the saved HTTPS or Home Assistant destination, pinned to the
    /// certificate confirmed at setup.
    static func verifiedHTTPS(
        destinationID: String,
        root: URL
    ) async throws -> (VerifiedDestination, TraceparentEmission) {
        let data = try Data(
            contentsOf: DestinationSidecar.httpsRecord(destinationID: destinationID).url(in: root)
        )
        let saved = try JSONDecoder().decode(HTTPSVerificationRecord.self, from: data)
        let allowedHosts = Set(saved.allowedHosts)
        let keychain = KeychainSecretStore(service: DestinationRepository.keychainService(destinationID))
        let bearer: String? = saved.hasBearer
            ? String(decoding: try await keychain.load(SecretHandle(rawValue: "bearer")), as: UTF8.self)
            : nil
        let destinationURLString: String
        if destinationID == "home-assistant" {
            let webhookID = String(
                decoding: try await keychain.load(SecretHandle(rawValue: "webhook-id")),
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
        let transport: any HTTPTransport = saved.pin.map {
            PinningHTTPTransport(inner: base, pin: $0)
        } ?? base
        let emission = TraceparentEmission(enabled: saved.propagateTraceparent ?? false)
        var setup = DestinationSetup()
        try setup.resumeEnabled(testReport: saved.report)
        let verified = try setup.enable(
            sink: HTTPSSink(
                destination: destination,
                transport: transport,
                traceparent: emission,
                meteredPolicy: .fromAllowsMetered(
                    HarnessExport.allowsMeteredNetwork(destinationID: destinationID)
                ),
                pathConditions: HarnessExport.networkPathConditions()
            )
        )
        return (verified, emission)
    }

    // MARK: MQTT

    static func prepareMQTT(
        urlString: String,
        allowInsecure: Bool,
        clientID: String,
        topic: String,
        clientPKCS12: Data?,
        clientPKCS12Password: String?,
        username: String?,
        password: String?,
        qos: UInt8,
        importedLocalIdentifier: String?,
        confirmedIdentity: TLSIdentity?,
        onProgress: DestinationTestProgress?
    ) async throws -> DestinationConfirmationCard {
        let host = try DestinationSetupService.host(of: urlString)
        let allowedHosts: Set<String> = [host]
        let exporterID = try HarnessExport.installationID()
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
        let sink: MQTTSink
        switch MQTTProbeTrust.forConfirmed(confirmedIdentity, firstSeen: now) {
        case let .pinned(pin):
            sink = try MQTTSink.overNetwork(destination: destination, pin: pin)
        case .captureUntrustedIdentity:
            sink = try MQTTSink.overNetwork(
                destination: destination,
                pin: nil,
                capturesUntrustedIdentity: true
            )
        }
        let probe = try await MQTTDestinationEnable.probe(
            destination: destination,
            pipe: sink.pipe,
            exporterID: try HarnessExport.installationID(),
            emittedAt: now,
            meteredPolicy: .fromAllowsMetered(HarnessExport.allowsMeteredNetwork(destinationID: "mqtt")),
            pathConditions: HarnessExport.networkPathConditions(),
            confirmedLeafSPKISha256: confirmedIdentity?.leafSPKISha256,
            onProgress: onProgress
        )
        return await service.stageMQTT(PendingMQTTDestination(
            probe: DestinationProbeResult(
                destinationURL: probe.destination.url,
                report: probe.report,
                identity: probe.identity,
                preview: probe.preview,
                pendingEvents: probe.pendingEvents
            ),
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
    }

    static func verifiedMQTT(root: URL) async throws -> VerifiedDestination {
        let data = try Data(contentsOf: DestinationSidecar.mqttRecord.url(in: root))
        let saved = try JSONDecoder().decode(MQTTVerificationRecord.self, from: data)
        let pkcs12 = (saved.hasClientPKCS12 == true)
            ? try Data(contentsOf: root.appendingPathComponent(DestinationSetupFileStore.mqttClientCertificate))
            : nil
        let password: String? = saved.hasPassword == true
            ? String(
                decoding: try await KeychainSecretStore(
                    service: IdentifierRoot.qualified("mqtt")
                ).load(SecretHandle(rawValue: "mqtt_password")),
                as: UTF8.self
            )
            : nil
        let destination = try MQTTDestination(
            urlString: saved.urlString,
            allowedHosts: Set(saved.allowedHosts),
            allowInsecure: saved.allowInsecure,
            clientID: saved.clientID,
            topic: saved.topic,
            qos: try MQTTDestination.qos(configurationValue: saved.qos ?? 1),
            username: saved.username,
            password: password,
            clientPKCS12: pkcs12,
            clientPKCS12Password: try await AppDestinations.records.mqttPKCS12Password(from: saved, root: root),
            exporterID: try HarnessExport.installationID()
        )
        var sink = try MQTTSink.overNetwork(destination: destination, pin: saved.pin)
        sink.meteredPolicy = .fromAllowsMetered(HarnessExport.allowsMeteredNetwork(destinationID: "mqtt"))
        sink.pathConditions = HarnessExport.networkPathConditions()
        var setup = DestinationSetup()
        try setup.resumeEnabled(testReport: saved.report)
        return try setup.enable(sink: sink)
    }

    // MARK: Local folder

    static func enableLocalFile(onProgress: DestinationTestProgress?) async throws -> [String] {
        try ExportScopeGate.requireConfigured(try await AppDestinations.repository.scope("local-file"))
        let root = try HarnessExport.applicationSupportRoot()
        let folderAccess = try AppDestinations.folder.access(root: root)
        defer { withExtendedLifetime(folderAccess) {} }
        service.forgetLocalFileTest()
        let (_, events) = try verifiedLocalFile(
            destinationDirectory: folderAccess.url,
            onProgress: onProgress
        )
        try await service.emitTrustNotices(events, destination: "local-file")
        try await service.requestScopeAuthorization("local-file")
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
        return AppStatus.status.destinationStatusLines()
    }

    static func verifiedLocalFile(
        destinationDirectory: URL,
        onProgress: DestinationTestProgress? = nil
    ) throws -> (VerifiedDestination, [TrustEvent]) {
        if let report = service.resumableLocalFileReport() {
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
            exporterId: try HarnessExport.installationID(),
            emittedAt: Date().ISO8601Format(),
            onProgress: onProgress
        )
        try service.recordLocalFileTest(
            completed.report,
            events: completed.events,
            destinationLabel: "This \(DeviceNoun.current) → Archive folder"
        )
        return (completed.destination, completed.events)
    }

    // MARK: Mac companion

    static func verifiedCompanion(
        session: PairingSession,
        onTestProgress: DestinationTestProgress?
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
        let emission = TraceparentEmission(enabled: AppDestinations.repository.companionTraceparent())
        let meteredPolicy = MeteredNetworkPolicy.fromAllowsMetered(
            HarnessExport.allowsMeteredNetwork(destinationID: "companion")
        )
        if let report = service.resumableCompanionReport(
            serviceName: session.serviceName,
            macInstallationID: session.macInstallationID
        ) {
            let verified = try CompanionDestinationEnable.resume(
                deliveryPipe: deliveryPipe,
                installationID: session.localInstallationID,
                testReport: report,
                traceparent: emission,
                meteredPolicy: meteredPolicy,
                pathConditions: HarnessExport.networkPathConditions()
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
            meteredPolicy: meteredPolicy,
            pathConditions: HarnessExport.networkPathConditions(),
            onProgress: onTestProgress
        )
        try await service.recordCompanionTest(
            CompanionVerificationRecord(
                serviceName: session.serviceName,
                macInstallationID: session.macInstallationID,
                report: completed.report,
                propagateTraceparent: emission.header(seed: "preview") != nil
            ),
            events: completed.events
        )
        return (completed.destination, emission)
    }

    // MARK: Portable configuration

    static func portableConfigurationExport() async throws -> URL {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-health-exporter.tributary")
        try await service.portableConfigurationDocument()
            .write(to: output, options: [.atomic, .completeFileProtection])
        return output
    }

    // MARK: OTLP

    #if !OHE_OBS25_SIZE_BASELINE
    static func previewOTLP() async throws -> (preview: String, payload: Data) {
        let root = try HarnessExport.applicationSupportRoot()
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
        try await service.enableOTLP(
            endpoint: endpoint.url,
            host: host,
            allowInsecureHTTP: allowInsecureHTTP,
            previewPayload: previewPayload
        )
        return AppStatus.status.destinationStatusLines()
    }

    static func otlpMetricsDestination(
        tracesEndpoint: HTTPSDestination,
        allowedHosts: Set<String>
    ) throws -> HTTPSDestination {
        guard let url = DestinationSetupService.otlpMetricsURL(tracesURL: tracesEndpoint.url) else {
            throw OTLPExportError.endpointRequired
        }
        return try HTTPSDestination(
            urlString: url.absoluteString,
            allowedHosts: allowedHosts,
            allowInsecureHTTP: tracesEndpoint.allowInsecureHTTP
        )
    }
    #endif
}
