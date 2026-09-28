// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CorrectnessEngine
import DestinationTrust
import DiagnosticBundle
import EnginePorts
import Foundation
import NetEgress

/// The verified destinations the data-flow explainer names, reduced to what it may
/// show: hosts, protocols and whether a credential exists. Never the secrets.
public struct DataFlowSources: Sendable, Equatable {
    public struct Web: Sendable, Equatable {
        public var urlString: String
        public var allowInsecureHTTP: Bool
        public var hasBearer: Bool

        public init(urlString: String, allowInsecureHTTP: Bool, hasBearer: Bool = false) {
            self.urlString = urlString
            self.allowInsecureHTTP = allowInsecureHTTP
            self.hasBearer = hasBearer
        }
    }

    public struct MQTT: Sendable, Equatable {
        public var urlString: String
        public var allowInsecure: Bool
        public var hasClientCertificate: Bool
        public var hasUsernameOrPassword: Bool

        public init(
            urlString: String,
            allowInsecure: Bool,
            hasClientCertificate: Bool,
            hasUsernameOrPassword: Bool
        ) {
            self.urlString = urlString
            self.allowInsecure = allowInsecure
            self.hasClientCertificate = hasClientCertificate
            self.hasUsernameOrPassword = hasUsernameOrPassword
        }
    }

    /// Enabled archive folder; the inner value is the folder's name when known.
    public var localFolder: String??
    public var https: Web?
    public var homeAssistant: Web?
    public var mqtt: MQTT?
    public var companionServiceName: String?
    public var otlpURLString: String?

    public init(
        localFolder: String?? = nil,
        https: Web? = nil,
        homeAssistant: Web? = nil,
        mqtt: MQTT? = nil,
        companionServiceName: String? = nil,
        otlpURLString: String? = nil
    ) {
        self.localFolder = localFolder
        self.https = https
        self.homeAssistant = homeAssistant
        self.mqtt = mqtt
        self.companionServiceName = companionServiceName
        self.otlpURLString = otlpURLString
    }
}

/// What the app and the device say about themselves when compiling a diagnostic
/// bundle. Gathered by the app, which is where device details are readable.
public struct DiagnosticEnvironment: Sendable, Equatable {
    public var appVersion: String
    public var osVersion: String
    public var deviceModel: String
    public var localeIdentifier: String
    public var utcOffsetMinutes: Int

    public init(
        appVersion: String,
        osVersion: String,
        deviceModel: String,
        localeIdentifier: String,
        utcOffsetMinutes: Int
    ) {
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.localeIdentifier = localeIdentifier
        self.utcOffsetMinutes = utcOffsetMinutes
    }
}

/// The journal rows a diagnostic bundle may include, and which parts could not be read.
public struct DiagnosticJournal: Sendable, Equatable {
    public var events: [RunEvent]
    public var degraded: [String]

    public init(events: [RunEvent], degraded: [String]) {
        self.events = events
        self.degraded = degraded
    }
}

/// What the app tells people about where their data goes and what it did (#42): the
/// data-flow explainer, the wipe inventory, the network-activity ledger, the build's
/// provenance and the diagnostic bundle.
public struct TransparencyService: Sendable {
    private let sources: @Sendable () -> DataFlowSources?
    private let selectedTypeCount: @Sendable () async -> Int
    private let store: @Sendable () throws -> any StateStore
    private let networkActivityURL: @Sendable () throws -> URL
    private let diagnosticJournal: @Sendable (_ maxRuns: Int, _ windowSeconds: TimeInterval) throws -> DiagnosticJournal
    private let marketingVersion: String
    private let build: BuildIdentity
    private let now: @Sendable () -> Date
    private let formatDate: @Sendable (Date) -> String

    public init(
        sources: @escaping @Sendable () -> DataFlowSources?,
        selectedTypeCount: @escaping @Sendable () async -> Int,
        store: @escaping @Sendable () throws -> any StateStore,
        networkActivityURL: @escaping @Sendable () throws -> URL,
        diagnosticJournal: @escaping @Sendable (Int, TimeInterval) throws -> DiagnosticJournal,
        marketingVersion: String,
        build: BuildIdentity = .current,
        now: @escaping @Sendable () -> Date,
        formatDate: @escaping @Sendable (Date) -> String
    ) {
        self.sources = sources
        self.selectedTypeCount = selectedTypeCount
        self.store = store
        self.networkActivityURL = networkActivityURL
        self.diagnosticJournal = diagnosticJournal
        self.marketingVersion = marketingVersion
        self.build = build
        self.now = now
        self.formatDate = formatDate
    }

    // MARK: Data flow

    /// UX-45: hops for the onboarding and Settings explainer. Credential *kinds*
    /// only — never tokens, passwords, or PKCS#12 bytes.
    public func dataFlowHops() -> [DataFlowHop] {
        guard let sources = sources() else { return [] }
        return Self.dataFlowHops(sources)
    }

    public static func dataFlowHops(_ sources: DataFlowSources) -> [DataFlowHop] {
        var hops: [DataFlowHop] = []
        if let folder = sources.localFolder {
            hops.append(
                DataFlowHop(
                    id: "local-file",
                    host: folder.map { "Files · \($0)" } ?? "Files",
                    transport: "Local files",
                    credential: DataFlowHop.noNetwork
                )
            )
        }
        if let https = sources.https {
            hops.append(
                DataFlowHop(
                    id: "https",
                    host: dataFlowHost(https.urlString),
                    transport: https.allowInsecureHTTP ? "HTTP" : "HTTPS",
                    credential: https.hasBearer ? DataFlowHop.bearerToken : DataFlowHop.noCredential
                )
            )
        }
        if let webhook = sources.homeAssistant {
            hops.append(
                DataFlowHop(
                    id: "home-assistant",
                    host: dataFlowHost(webhook.urlString),
                    transport: webhook.allowInsecureHTTP ? "HTTP webhook" : "HTTPS webhook",
                    credential: DataFlowHop.webhookSecret
                )
            )
        }
        if let mqtt = sources.mqtt {
            let credential: String
            if mqtt.hasClientCertificate {
                credential = DataFlowHop.clientCertificate
            } else if mqtt.hasUsernameOrPassword {
                credential = DataFlowHop.usernamePassword
            } else {
                credential = DataFlowHop.noCredential
            }
            hops.append(
                DataFlowHop(
                    id: "mqtt",
                    host: dataFlowHost(mqtt.urlString),
                    transport: mqtt.allowInsecure ? "MQTT" : "MQTTS",
                    credential: credential
                )
            )
        }
        if let serviceName = sources.companionServiceName {
            hops.append(
                DataFlowHop(
                    id: "companion",
                    host: serviceName,
                    transport: "Mac companion",
                    credential: DataFlowHop.pairing
                )
            )
        }
        if let otlp = sources.otlpURLString, let host = URL(string: otlp)?.host {
            hops.append(
                DataFlowHop(
                    id: "otlp",
                    host: host,
                    transport: "OTLP HTTP",
                    credential: DataFlowHop.noCredential
                )
            )
        }
        return hops
    }

    /// Host and, when not the default, port: the part of a URL the explainer names.
    public static func dataFlowHost(_ urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host, !host.isEmpty else {
            return urlString
        }
        if let port = url.port {
            return "\(host):\(port)"
        }
        return host
    }

    public func dataFlowTypeCount() async -> Int {
        await selectedTypeCount()
    }

    /// What "Erase everything" will remove, counted before the person confirms.
    public func wipeInventory() async -> WipeInventory {
        let hops = dataFlowHops()
        let destinationCount = hops.filter { $0.id != "otlp" }.count
        let credentialCount = hops.filter {
            $0.credential != DataFlowHop.noNetwork
                && $0.credential != DataFlowHop.noCredential
        }.count
        guard let store = try? store() else {
            return WipeInventory(
                destinationCount: destinationCount,
                credentialCount: credentialCount
            )
        }
        let pending = (try? await store.transact { try $0.pendingBatches() }) ?? []
        let journal = (try? await store.transact { try $0.loadJournal() }) ?? []
        let ledger = (try? await store.transact { try $0.loadLedger() }) ?? []
        return WipeInventory.build(
            destinationCount: destinationCount,
            credentialCount: credentialCount,
            pending: pending,
            journal: journal,
            ledger: ledger
        )
    }

    // MARK: Network activity and provenance

    /// Starts persisting the self-reported egress log, so every later attempt is kept.
    public func attachNetworkActivityLedger() {
        guard let url = try? networkActivityURL() else { return }
        let now = self.now
        EgressAttemptLog.attachPersistent(
            EgressAttemptLog.PersistentStore(
                url: url,
                nowEpoch: { now().timeIntervalSince1970 }
            )
        )
    }

    public func networkActivityLines() -> [String] {
        attachNetworkActivityLedger()
        return Self.networkActivityLines(
            rows: EgressAttemptLog.persistentSnapshot(),
            sourceCommit: build.sourceCommit,
            formatDate: formatDate
        )
    }

    public static func networkActivityLines(
        rows: [NetworkActivityRow],
        sourceCommit: String,
        formatDate: (Date) -> String
    ) -> [String] {
        var lines = [EgressAttemptLog.selfReportedCaveat(sourceCommit: sourceCommit)]
        guard !rows.isEmpty else {
            lines.append(EgressAttemptLog.emptyCopy)
            return lines
        }
        for row in rows {
            let first = formatDate(Date(timeIntervalSince1970: row.firstSeenEpoch))
            let last = formatDate(Date(timeIntervalSince1970: row.lastSeenEpoch))
            lines.append("\(row.host) · \(row.count) · \(row.bytes) bytes · \(first) → \(last)")
        }
        return lines
    }

    public func buildProvenanceLines() -> [String] {
        var lines = [BuildIdentity.versionLine(version: marketingVersion, commit: build.sourceCommit)]
        if let link = BuildIdentity.sourceLink(commit: build.sourceCommit) {
            lines.append(link)
        }
        return lines
    }

    // MARK: Diagnostics

    /// The redacted diagnostic bundle: a readable preview and the exact bytes shared.
    public func diagnosticBundle(
        environment: DiagnosticEnvironment,
        minimumRuns: Int = 30,
        windowHours: Int = 24
    ) throws -> (preview: String, payload: Data) {
        let assembler = BundleAssembler(
            maxRuns: minimumRuns,
            windowSeconds: TimeInterval(windowHours) * 60 * 60
        )
        let journal = try diagnosticJournal(assembler.maxRuns, assembler.windowSeconds)
        let payload = try assembler.assemble(
            header: DiagnosticHeader(
                appVersion: environment.appVersion,
                osVersion: environment.osVersion,
                deviceModel: environment.deviceModel,
                localeIdentifier: environment.localeIdentifier,
                utcOffsetMinutes: environment.utcOffsetMinutes,
                generatedAt: now().ISO8601Format(),
                degraded: journal.degraded,
                sourceCommit: build.sourceCommit,
                buildHash: build.buildHash
            ),
            events: journal.events
        )
        let text = String(decoding: payload, as: UTF8.self)
        let prettyText: String
        if let object = try? JSONSerialization.jsonObject(with: payload),
           JSONSerialization.isValidJSONObject(object),
           let pretty = try? JSONSerialization.data(
               withJSONObject: object,
               options: [.prettyPrinted, .sortedKeys]
           ),
           let decoded = String(data: pretty, encoding: .utf8)
        {
            prettyText = decoded
        } else {
            prettyText = text
        }
        let lines = assembler.previewLines(events: journal.events)
        let preview = lines.isEmpty ? prettyText : lines.joined(separator: "\n") + "\n\n" + prettyText
        return (preview, payload)
    }
}
