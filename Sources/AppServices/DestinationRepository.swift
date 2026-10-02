// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import EnginePorts
import Foundation
import MetricCatalog
import Watchdog

/// The small files that hold a destination's saved setup, named in one place so the
/// app-side storage and every reader agree on them.
public enum DestinationSidecar: Sendable, Hashable {
    /// The HTTPS or Home Assistant verification record, one per destination ID.
    case httpsRecord(destinationID: String)
    case mqttRecord
    case companionTestReport
    case pairing
    case localFileTestReport
    case localFolderBookmark

    public var filename: String {
        switch self {
        case let .httpsRecord(destinationID): "\(destinationID)-destination.json"
        case .mqttRecord: "mqtt-destination.json"
        case .companionTestReport: "companion-test.json"
        case .pairing: "pairing.json"
        case .localFileTestReport: "local-file-test.json"
        case .localFolderBookmark: "local-export-folder.bookmark"
        }
    }

    public func url(in root: URL) -> URL {
        root.appendingPathComponent(filename)
    }
}

/// What a destination's saved verification says, without any secret in it.
public struct DestinationVerificationSummary: Sendable, Equatable {
    public var allowsEnablement: Bool
    public var propagateTraceparent: Bool
    public var bearer: StoredCredentialDescriptor?
    public var webhook: StoredCredentialDescriptor?
    public var password: StoredCredentialDescriptor?
    public var pkcs12Password: StoredCredentialDescriptor?

    public init(
        allowsEnablement: Bool,
        propagateTraceparent: Bool = false,
        bearer: StoredCredentialDescriptor? = nil,
        webhook: StoredCredentialDescriptor? = nil,
        password: StoredCredentialDescriptor? = nil,
        pkcs12Password: StoredCredentialDescriptor? = nil
    ) {
        self.allowsEnablement = allowsEnablement
        self.propagateTraceparent = propagateTraceparent
        self.bearer = bearer
        self.webhook = webhook
        self.password = password
        self.pkcs12Password = pkcs12Password
    }
}

/// Masked summaries of the credentials the destinations hold (UX-12).
public struct StoredCredentialSummaries: Sendable, Equatable {
    public var httpsBearer: String?
    public var homeAssistantWebhook: String?
    public var mqttPassword: String?
    public var mqttPKCS12Password: String?
}

/// The saved verification sidecars. Reads fail soft: a missing or unreadable file is nil.
public protocol DestinationRecordStorage: Sendable {
    /// The local-file destination's summary comes from its test report; the others from
    /// their verification records.
    func verification(_ destinationID: String) -> DestinationVerificationSummary?
    /// Rewrites the saved record's traceparent flag; a destination with no record is left alone.
    func setPropagateTraceparent(_ enabled: Bool, destinationID: String) throws
    func exists(_ sidecar: DestinationSidecar) -> Bool
    func remove(_ sidecar: DestinationSidecar)
}

/// Per-destination preferences the settings screen writes.
public protocol DestinationPreferenceStorage: Sendable {
    func exportRole(_ destinationID: String) -> String?
    func setExportRole(_ rawValue: String, destinationID: String)
    func allowsMeteredNetwork(_ destinationID: String) -> Bool
    func companionPropagatesTraceparent() -> Bool
    func setCompanionPropagatesTraceparent(_ enabled: Bool)
}

/// The status snapshots the widget reads. They carry the export role too, so a role
/// chosen before preferences existed is still honoured.
public protocol DestinationSnapshotStorage: Sendable {
    func exportRole(_ destinationID: String) -> DestinationExportRole?
    /// Updates the destination's snapshot, if it has one, and tells the widget.
    func applyExportRole(_ role: DestinationExportRole, destinationID: String, at now: Date) throws
}

/// The per-destination health-data grants (SEC-16) in the state store.
public protocol DestinationScopeStorage: Sendable {
    func loadScope(_ destinationID: String) async throws -> DestinationExportScope?
    func saveScope(_ scope: DestinationExportScope) async throws
    func reenable(_ metric: MetricID, reason: String) async throws
}

/// The archive folder the person picked in Files, kept as a security-scoped bookmark.
public protocol LocalExportFolderStorage: Sendable {
    func saveFolder(_ url: URL) throws
    /// The folder's name when its bookmark resolves and it can be opened; otherwise nil.
    func accessibleFolderName() -> String?
}

/// Destination configuration and settings (#42): which destinations are set up and
/// enabled, their export roles and scopes, and the per-destination switches. Views and
/// the export flows ask it; they never read the sidecar files or preferences directly.
public struct DestinationRepository: Sendable {
    /// The destinations that receive health records, in display order.
    public static let healthDestinationIDs = [
        "local-file", "https", "home-assistant", "mqtt", "companion",
    ]

    private let records: any DestinationRecordStorage
    private let preferences: any DestinationPreferenceStorage
    private let snapshots: any DestinationSnapshotStorage
    private let scopes: any DestinationScopeStorage
    private let folder: any LocalExportFolderStorage
    private let now: @Sendable () -> Date
    /// D-08b (#68): whether runs that start on their own are unlocked. Defaults to
    /// unlocked, which is what a source build and every test that isn't about it want.
    private let unlockState: @Sendable () -> UnlockState

    public init(
        records: any DestinationRecordStorage,
        preferences: any DestinationPreferenceStorage,
        snapshots: any DestinationSnapshotStorage,
        scopes: any DestinationScopeStorage,
        folder: any LocalExportFolderStorage,
        now: @escaping @Sendable () -> Date,
        unlockState: @escaping @Sendable () -> UnlockState = { .sourceBuild }
    ) {
        self.records = records
        self.preferences = preferences
        self.snapshots = snapshots
        self.scopes = scopes
        self.folder = folder
        self.now = now
        self.unlockState = unlockState
    }

    // MARK: Pure rules

    public static func label(_ destinationID: String) -> String {
        switch destinationID {
        case "local-file": "Archive folder"
        case "https": "HTTPS destination"
        case "home-assistant": "Home Assistant"
        case "mqtt": "MQTT destination"
        case "companion": "Mac companion"
        default: destinationID
        }
    }

    /// The Keychain service that holds an HTTPS-style destination's secrets.
    public static func keychainService(_ destinationID: String) -> String {
        IdentifierRoot.qualified("ios.\(destinationID)")
    }

    /// A scope keeps only types a person can choose; anything else is dropped, not refused.
    public static func sanitized(_ scope: DestinationExportScope) throws -> DestinationExportScope {
        let allowed = Set(MetricCatalog.selectable.map(\.id))
        return try DestinationExportScope(
            destinationID: scope.destinationID,
            metrics: scope.metrics.intersection(allowed),
            startInclusive: scope.startInclusive,
            endExclusive: scope.endExclusive
        )
    }

    // MARK: Scopes

    /// Absence is deny: a destination with no saved scope gets an empty one.
    public func scope(_ destinationID: String) async throws -> DestinationExportScope {
        try await scopes.loadScope(destinationID)
            ?? DestinationExportScope(destinationID: destinationID)
    }

    public func allScopes() async throws -> [DestinationExportScope] {
        var result: [DestinationExportScope] = []
        for destinationID in Self.healthDestinationIDs {
            result.append(try await scope(destinationID))
        }
        return result
    }

    /// The types any enabled destination may receive, sorted by identifier.
    public func selectedMetrics() async throws -> [MetricID] {
        let union = try await allScopes().reduce(into: Set<MetricID>()) {
            guard isEnabled($1.destinationID) else { return }
            $0.formUnion($1.metrics)
        }
        return union.sorted { $0.rawValue < $1.rawValue }
    }

    public func saveScope(_ scope: DestinationExportScope) async throws {
        try await scopes.saveScope(Self.sanitized(scope))
    }

    /// Saves the scope and re-enables every type the person just added, so a type that
    /// was stopped earlier starts exporting again.
    public func applyScope(
        _ scope: DestinationExportScope,
        previousMetrics: Set<MetricID>
    ) async throws {
        try await saveScope(scope)
        for metric in scope.metrics.subtracting(previousMetrics) {
            try await scopes.reenable(metric, reason: "user_selected")
        }
    }

    // MARK: Enablement

    public func isEnabled(_ destinationID: String) -> Bool {
        switch destinationID {
        case "local-file":
            return isLocalFileEnabled()
        case "https", "home-assistant", "mqtt", "companion":
            return records.verification(destinationID)?.allowsEnablement ?? false
        default:
            return false
        }
    }

    /// A folder that can no longer be opened disables the archive even after a passed test.
    public func isLocalFileEnabled() -> Bool {
        guard folder.accessibleFolderName() != nil,
              let report = records.verification("local-file")
        else { return false }
        return report.allowsEnablement
    }

    public func hasConfiguration(_ destinationID: String) -> Bool {
        switch destinationID {
        case "https", "home-assistant":
            records.exists(.httpsRecord(destinationID: destinationID))
        case "mqtt":
            records.exists(.mqttRecord)
        case "companion":
            records.exists(.companionTestReport) || records.exists(.pairing)
        default:
            false
        }
    }

    // MARK: Export roles

    /// The saved preference wins, then the role the widget snapshot remembers, then
    /// `.designated`.
    public func exportRole(_ destinationID: String) -> DestinationExportRole {
        if let raw = preferences.exportRole(destinationID),
           let stored = DestinationExportRole(rawValue: raw) {
            return stored
        }
        return snapshots.exportRole(destinationID) ?? .designated
    }

    public func setExportRole(_ role: DestinationExportRole, destinationID: String) throws {
        preferences.setExportRole(role.rawValue, destinationID: destinationID)
        try snapshots.applyExportRole(role, destinationID: destinationID, at: now())
    }

    /// Writes each destination's resolved role back to preferences and its snapshot so
    /// the widget and the app agree.
    public func synchronizeExportRole(_ destinationID: String) {
        try? setExportRole(exportRole(destinationID), destinationID: destinationID)
    }

    public func synchronizeExportRoles() {
        for destinationID in Self.healthDestinationIDs {
            synchronizeExportRole(destinationID)
        }
    }

    /// The destination's own role, and the unlock for runs that start on their own:
    /// without it, only Export now and the Control Centre button send anything.
    public func allowsExport(_ destinationID: String, trigger: RunTrigger) -> Bool {
        exportRole(destinationID).allows(trigger)
            && AutomationGate.allows(trigger, state: unlockState())
    }

    /// Whether this trigger would send anything: some destination is enabled and its
    /// role lets this trigger run it.
    public func hasAutomaticExport(trigger: RunTrigger) -> Bool {
        Self.healthDestinationIDs.contains {
            isEnabled($0) && allowsExport($0, trigger: trigger)
        }
    }

    // MARK: Per-destination switches

    /// Metered networks are off unless the person turned them on for this destination.
    public func allowsMeteredNetwork(_ destinationID: String) -> Bool {
        preferences.allowsMeteredNetwork(destinationID)
    }

    public func httpsTraceparent(_ destinationID: String = "https") -> Bool {
        records.verification(destinationID)?.propagateTraceparent ?? false
    }

    public func setHTTPSTraceparent(_ enabled: Bool, destinationID: String = "https") throws {
        try records.setPropagateTraceparent(enabled, destinationID: destinationID)
    }

    public func companionTraceparent() -> Bool {
        preferences.companionPropagatesTraceparent()
    }

    /// The preference is what the next pairing starts from; the saved record is what the
    /// current pairing sends with.
    public func setCompanionTraceparent(_ enabled: Bool) throws {
        preferences.setCompanionPropagatesTraceparent(enabled)
        try records.setPropagateTraceparent(enabled, destinationID: "companion")
    }

    public func credentialSummaries() -> StoredCredentialSummaries {
        func present(_ descriptor: StoredCredentialDescriptor?) -> String? {
            guard let descriptor, descriptor.appearance != .absent else { return nil }
            return descriptor.summary
        }
        let mqtt = records.verification("mqtt")
        return StoredCredentialSummaries(
            httpsBearer: present(records.verification("https")?.bearer),
            homeAssistantWebhook: present(records.verification("home-assistant")?.webhook),
            mqttPassword: present(mqtt?.password),
            mqttPKCS12Password: present(mqtt?.pkcs12Password)
        )
    }

    // MARK: Archive folder

    /// A newly chosen folder has not been tested, so the old test report is dropped and
    /// the archive stays off until the next test passes.
    public func chooseLocalExportFolder(_ url: URL) throws -> String {
        try folder.saveFolder(url)
        records.remove(.localFileTestReport)
        return url.lastPathComponent
    }

    public func localExportFolderName() -> String? {
        folder.accessibleFolderName()
    }
}
