// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public enum PortableDestinationKind: String, Sendable, Codable, CaseIterable {
    case localFile
    case https
    case homeAssistant
    case mqtt
    case companion
}

public enum PortableCredentialDisposition: String, Sendable, Codable {
    /// The only disposition supported by the file format. Credential-bearing exports
    /// require a separate product and threat-model decision (SEC-18).
    case omitted
}

public enum DestinationConfigurationPortabilityError: Error, Sendable, Equatable, LocalizedError {
    case emptyIdentifier
    case emptyDisplayName
    case emptyEndpoint
    case unsupportedSchemaVersion(Int)
    case duplicateIdentifier(String)
    case unsupportedField(String)
    case unsupportedSetting(kind: PortableDestinationKind, key: String)
    case credentialsInEndpoint
    case confirmationMismatch
    case invalidScopeDateRange
    case unsupportedDestinationKind(PortableDestinationKind)

    public var errorDescription: String? {
        switch self {
        case .emptyIdentifier:
            "The destination identifier is empty."
        case .emptyDisplayName:
            "The destination name is empty."
        case .emptyEndpoint:
            "The destination address is empty."
        case .unsupportedSchemaVersion:
            "This configuration file uses a schema version this app does not support."
        case .duplicateIdentifier:
            "The configuration file lists the same destination twice."
        case .unsupportedField, .unsupportedSetting:
            "The configuration file contains a field or setting this app does not import."
        case .credentialsInEndpoint:
            "The destination address includes credentials. Remove them and add credentials in the app."
        case .confirmationMismatch:
            "The import confirmation phrase did not match."
        case .invalidScopeDateRange:
            "The export date range is invalid."
        case .unsupportedDestinationKind:
            "This destination kind does not have a setup path."
        }
    }
}

public struct PortableDestinationExportScope: Sendable, Codable, Equatable {
    public var metrics: [MetricID]
    public var startInclusive: Date?
    public var endExclusive: Date?

    public init(
        metrics: [MetricID] = [],
        startInclusive: Date? = nil,
        endExclusive: Date? = nil
    ) throws {
        if let startInclusive, let endExclusive, endExclusive <= startInclusive {
            throw DestinationConfigurationPortabilityError.invalidScopeDateRange
        }
        self.metrics = metrics
        self.startInclusive = startInclusive
        self.endExclusive = endExclusive
    }

    fileprivate func validate() throws {
        if let startInclusive, let endExclusive, endExclusive <= startInclusive {
            throw DestinationConfigurationPortabilityError.invalidScopeDateRange
        }
    }

    fileprivate func canonicalized() -> Self {
        var copy = self
        copy.metrics = Array(Set(metrics)).sorted { $0.rawValue < $1.rawValue }
        return copy
    }
}

/// A deliberately credential-free, transport-neutral representation of one destination.
///
/// `settings` is an allow-listed set of non-secret values. Headers, bearer tokens,
/// usernames, passwords, pairing material, certificate bytes, and security-scoped
/// bookmarks cannot be represented by this type.
public struct PortableDestinationConfiguration: Sendable, Codable, Equatable {
    public var sourceIdentifier: String
    public var displayName: String
    public var kind: PortableDestinationKind
    public var endpoint: String
    public var settings: [String: String]
    public var exportScope: PortableDestinationExportScope
    public var credentials: PortableCredentialDisposition

    public init(
        sourceIdentifier: String,
        displayName: String,
        kind: PortableDestinationKind,
        endpoint: String,
        settings: [String: String] = [:],
        exportScope: PortableDestinationExportScope? = nil
    ) throws {
        self.sourceIdentifier = sourceIdentifier
        self.displayName = displayName
        self.kind = kind
        self.endpoint = endpoint
        self.settings = settings
        self.exportScope = try exportScope ?? PortableDestinationExportScope()
        credentials = .omitted
        try validate()
    }

    fileprivate func validate() throws {
        guard !sourceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DestinationConfigurationPortabilityError.emptyIdentifier
        }
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DestinationConfigurationPortabilityError.emptyDisplayName
        }
        guard !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DestinationConfigurationPortabilityError.emptyEndpoint
        }
        guard credentials == .omitted else {
            throw DestinationConfigurationPortabilityError.unsupportedField("credentials")
        }
        try exportScope.validate()
        if let components = URLComponents(string: endpoint),
           components.user != nil
            || components.password != nil
            || components.query != nil
            || components.fragment != nil {
            throw DestinationConfigurationPortabilityError.credentialsInEndpoint
        }
        for key in settings.keys where !Self.allowedSettings(for: kind).contains(key) {
            throw DestinationConfigurationPortabilityError.unsupportedSetting(kind: kind, key: key)
        }
    }

    private static func allowedSettings(for kind: PortableDestinationKind) -> Set<String> {
        switch kind {
        case .localFile:
            ["filenameTemplate", "format", "rotation"]
        case .https:
            ["method", "bodyTemplate", "timeoutSeconds", "allowInsecureHTTP"]
        case .homeAssistant:
            ["mode", "allowInsecureHTTP"]
        case .mqtt:
            [
                "clientID", "topic", "qos", "retain", "cleanSession",
                "keepAliveSeconds", "allowInsecure",
            ]
        case .companion:
            ["serviceName"]
        }
    }

    fileprivate func canonicalized() -> Self {
        var copy = self
        copy.exportScope = exportScope.canonicalized()
        return copy
    }
}

/// The deterministic contents of a `.tributary` file.
public struct DestinationConfigurationDocument: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 1
    public static let format = "org.open-health-exporter.destination-config"

    public var format: String
    public var schemaVersion: Int
    public var destinations: [PortableDestinationConfiguration]

    public init(destinations: [PortableDestinationConfiguration]) throws {
        format = Self.format
        schemaVersion = Self.currentSchemaVersion
        self.destinations = destinations
        try validate()
    }

    fileprivate func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DestinationConfigurationPortabilityError.unsupportedSchemaVersion(schemaVersion)
        }
        guard format == Self.format else {
            throw DestinationConfigurationPortabilityError.unsupportedField("format")
        }
        var identifiers = Set<String>()
        for destination in destinations {
            try destination.validate()
            guard identifiers.insert(destination.sourceIdentifier).inserted else {
                throw DestinationConfigurationPortabilityError.duplicateIdentifier(
                    destination.sourceIdentifier
                )
            }
        }
    }

    /// Stable bytes: no generated timestamp, sorted object keys, destinations, or metrics.
    public func encoded() throws -> Data {
        try validate()
        var canonical = self
        canonical.destinations = destinations
            .map { $0.canonicalized() }
            .sorted { $0.sourceIdentifier < $1.sourceIdentifier }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(canonical)
    }

    public static func reviewImport(_ data: Data) throws -> DestinationConfigurationImportReview {
        try rejectUnknownFields(in: data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let document = try decoder.decode(Self.self, from: data)
        try document.validate()
        return DestinationConfigurationImportReview(
            destinations: document.destinations
                .map { $0.canonicalized() }
                .sorted { $0.sourceIdentifier < $1.sourceIdentifier }
        )
    }

    private static func rejectUnknownFields(in data: Data) throws {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let root = json as? [String: Any] else {
            throw DestinationConfigurationPortabilityError.unsupportedField("<root>")
        }
        let rootKeys: Set<String> = ["format", "schemaVersion", "destinations"]
        if let key = root.keys.first(where: { !rootKeys.contains($0) }) {
            throw DestinationConfigurationPortabilityError.unsupportedField(key)
        }
        guard let destinations = root["destinations"] as? [[String: Any]] else { return }
        let destinationKeys: Set<String> = [
            "sourceIdentifier", "displayName", "kind", "endpoint", "settings",
            "exportScope", "credentials",
        ]
        for destination in destinations {
            if let key = destination.keys.first(where: { !destinationKeys.contains($0) }) {
                throw DestinationConfigurationPortabilityError.unsupportedField(key)
            }
            if let scope = destination["exportScope"] as? [String: Any] {
                let scopeKeys: Set<String> = ["metrics", "startInclusive", "endExclusive"]
                if let key = scope.keys.first(where: { !scopeKeys.contains($0) }) {
                    throw DestinationConfigurationPortabilityError.unsupportedField(
                        "exportScope.\(key)"
                    )
                }
            }
        }
    }
}

/// Parsed imports are inert review data. Confirmation can only produce new disabled
/// drafts; it cannot name an existing local record to update or enable.
public struct DestinationConfigurationImportReview: Sendable, Equatable {
    public static let confirmationPhrase = "import as disabled destinations"

    public let destinations: [PortableDestinationConfiguration]

    fileprivate init(destinations: [PortableDestinationConfiguration]) {
        self.destinations = destinations
    }

    public func confirm(
        typedConfirmation: String
    ) throws -> ConfirmedDestinationConfigurationImport {
        guard typedConfirmation == Self.confirmationPhrase else {
            throw DestinationConfigurationPortabilityError.confirmationMismatch
        }
        return ConfirmedDestinationConfigurationImport(
            drafts: destinations.map(DestinationConfigurationDraft.init(configuration:))
        )
    }
}

public struct DestinationConfigurationDraft: Sendable, Equatable {
    public enum State: String, Sendable, Equatable {
        case disabledRequiresTest
    }

    public let configuration: PortableDestinationConfiguration
    public let state: State

    fileprivate init(configuration: PortableDestinationConfiguration) {
        self.configuration = configuration
        state = .disabledRequiresTest
    }
}

public struct ConfirmedDestinationConfigurationImport: Sendable, Equatable {
    public let drafts: [DestinationConfigurationDraft]

    fileprivate init(drafts: [DestinationConfigurationDraft]) {
        self.drafts = drafts
    }
}

public struct PortableDestinationSetupInputs: Sendable, Equatable {
    public let slotIdentifier: String
    public let endpoint: String
    public let allowInsecure: Bool
    public let clientID: String?
    public let topic: String?
    public let qos: UInt8?
}

public enum PortableDestinationMaterializer {
    public static func materialize(
        _ configuration: PortableDestinationConfiguration
    ) throws -> PortableDestinationSetupInputs {
        let supported: Set<String>
        switch configuration.kind {
        case .https:
            supported = ["allowInsecureHTTP", "method"]
            if let method = configuration.settings["method"],
               method.uppercased() != "POST" {
                throw DestinationConfigurationPortabilityError.unsupportedSetting(
                    kind: .https,
                    key: "method"
                )
            }
            try rejectUnsupported(
                configuration.settings,
                supported: supported,
                kind: .https
            )
            return PortableDestinationSetupInputs(
                slotIdentifier: "https",
                endpoint: configuration.endpoint,
                allowInsecure:
                    configuration.settings["allowInsecureHTTP"] == "true",
                clientID: nil,
                topic: nil,
                qos: nil
            )
        case .mqtt:
            supported = ["allowInsecure", "clientID", "qos", "topic", "cleanSession"]
            try rejectUnsupported(
                configuration.settings,
                supported: supported,
                kind: .mqtt
            )
            let qos = UInt8(configuration.settings["qos"] ?? "") ?? 1
            guard qos <= 1 else {
                throw DestinationConfigurationPortabilityError.unsupportedSetting(
                    kind: .mqtt,
                    key: "qos"
                )
            }
            if let cleanSession = configuration.settings["cleanSession"],
               cleanSession != "true" {
                throw DestinationConfigurationPortabilityError.unsupportedSetting(
                    kind: .mqtt,
                    key: "cleanSession"
                )
            }
            return PortableDestinationSetupInputs(
                slotIdentifier: "mqtt",
                endpoint: configuration.endpoint,
                allowInsecure:
                    configuration.settings["allowInsecure"] == "true",
                clientID: configuration.settings["clientID"],
                topic: configuration.settings["topic"],
                qos: qos
            )
        case .localFile, .homeAssistant, .companion:
            throw DestinationConfigurationPortabilityError
                .unsupportedDestinationKind(configuration.kind)
        }
    }

    private static func rejectUnsupported(
        _ settings: [String: String],
        supported: Set<String>,
        kind: PortableDestinationKind
    ) throws {
        if let key = settings.keys.sorted().first(
            where: { !supported.contains($0) }
        ) {
            throw DestinationConfigurationPortabilityError.unsupportedSetting(
                kind: kind,
                key: key
            )
        }
    }
}
