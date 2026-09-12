// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppIntents
import CoreDomain
import EnginePorts
import Foundation
import Watchdog

struct DestinationStatusEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Export destination"
    )
    static let defaultQuery = DestinationStatusEntityQuery()

    var id: String

    @Property(title: "Destination")
    var label: String

    @Property(title: "Last successful export")
    var lastSuccessAt: String?

    @Property(title: "Last confirmed acknowledgement")
    var lastConfirmedAckAt: String?

    @Property(title: "Age in seconds")
    var ageSeconds: Int?

    @Property(title: "State")
    var state: String

    @Property(title: "Last outcome")
    var lastOutcome: String?

    @Property(title: "Attribution")
    var attribution: String?

    @Property(title: "Attribution confidence")
    var attributionConfidence: String?

    @Property(title: "Error class")
    var errorClass: String?

    @Property(title: "Failure reason")
    var failureReason: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(label)", subtitle: "\(state)")
    }

    init(status: DestinationMonitoringStatus) {
        id = status.destinationID
        label = status.label
        lastSuccessAt = status.lastSuccessAt
        lastConfirmedAckAt = status.lastConfirmedAckAt
        ageSeconds = status.ageSeconds
        state = status.state
        lastOutcome = status.lastOutcome
        attribution = status.attribution
        attributionConfidence = status.attributionConfidence
        errorClass = status.errorClass
        failureReason = status.failureReason
    }
}

struct DestinationStatusEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [DestinationStatusEntity] {
        Self.current().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [DestinationStatusEntity] {
        Self.current()
    }

    private static func current() -> [DestinationStatusEntity] {
        let now = Date().timeIntervalSince1970
        return StatusSnapshotLocation.readAll().map {
            DestinationStatusEntity(
                status: DestinationMonitoringStatus(snapshot: $0, nowEpoch: now)
            )
        }
    }
}

enum ShortcutExportKind: String, AppEnum {
    case success
    case partial
    case failed
    case deferred
    case blocked
    case nothingDue
    case sentUnconfirmed

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Export outcome")

    static let caseDisplayRepresentations: [ShortcutExportKind: DisplayRepresentation] = [
        .success: "Success",
        .partial: "Partial",
        .failed: "Failed",
        .deferred: "Deferred",
        .blocked: "Blocked",
        .nothingDue: "Nothing due",
        .sentUnconfirmed: "Sent, unconfirmed",
    ]

    static func summarizing(_ outcomes: [RunOutcome.Kind]) -> ShortcutExportKind {
        switch CombinedExportSummary.kind(outcomes) {
        case .success: .success
        case .successNothingDue: .nothingDue
        case .partial: .partial
        case .failed: .failed
        case .unknownAck: .sentUnconfirmed
        case .localNetworkDenied: .blocked
        case .blockedDeviceLocked, .abandonedNoBudget, .cancelledBySystem, .blockedLowPower:
            .deferred
        }
    }

    static func kinds(fromExportLines lines: [String]) -> [RunOutcome.Kind] {
        lines.compactMap { line in
            guard let separator = line.lastIndex(of: ":") else { return nil }
            let raw = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            return RunOutcome.Kind(rawValue: raw)
        }
    }
}

struct LastSuccessfulExportIntent: AppIntent {
    static let title: LocalizedStringResource = "Last successful export"
    static let description = IntentDescription(
        "Returns value-free freshness and delivery status for every export destination."
    )
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<[DestinationStatusEntity]> {
        .result(value: try await DestinationStatusEntityQuery().suggestedEntities())
    }
}

enum ShortcutExportError: Error, LocalizedError {
    case disclosureRequired
    case destinationDisabled

    var errorDescription: String? {
        switch self {
        case .disclosureRequired:
            ShortcutExportAuthorization.denyReason(
                disclosureAcknowledged: false,
                localFileEnabled: true
            )
        case .destinationDisabled:
            ShortcutExportAuthorization.denyReason(
                disclosureAcknowledged: true,
                localFileEnabled: false
            )
        }
    }
}

struct ExportOnePageIntent: AppIntent {
    static let title: LocalizedStringResource = "Export one page"
    static let description = IntentDescription(
        "Runs one anchored page per selected type to the enabled local archive. Outcomes are kinds, not health values."
    )
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<ShortcutExportKind> {
        if let reason = ShortcutExportAuthorization.denyReason(
            disclosureAcknowledged: UserDefaults.standard.bool(forKey: "ohe.disclosureAcknowledged"),
            localFileEnabled: HarnessExport.isLocalFileEnabled()
        ) {
            if reason.contains("disclosure") {
                throw ShortcutExportError.disclosureRequired
            }
            throw ShortcutExportError.destinationDisabled
        }
        let lines = try await HarnessExport.runOnePageEachMetric(trigger: .shortcut)
        return .result(
            value: ShortcutExportKind.summarizing(ShortcutExportKind.kinds(fromExportLines: lines))
        )
    }
}

struct ExportTypeWindowIntent: AppIntent {
    static let title: LocalizedStringResource = "Export type for window"
    static let description = IntentDescription(
        "Runs one anchored page of one type using the owned export window. Outcomes are kinds, not health values."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Type identifier")
    var metricIdentifier: String

    @Parameter(title: "Window hours")
    var windowHours: Int

    func perform() async throws -> some IntentResult & ReturnsValue<ShortcutExportKind> {
        if let reason = ShortcutExportAuthorization.denyReason(
            disclosureAcknowledged: UserDefaults.standard.bool(forKey: "ohe.disclosureAcknowledged"),
            localFileEnabled: HarnessExport.isLocalFileEnabled()
        ) {
            if reason.contains("disclosure") {
                throw ShortcutExportError.disclosureRequired
            }
            throw ShortcutExportError.destinationDisabled
        }
        UserDefaults.standard.set(max(1, windowHours), forKey: "ohe.exportWindowHours")
        let lines = try await HarnessExport.runOnePageEachMetric(
            metrics: [MetricID(rawValue: metricIdentifier)],
            trigger: .shortcut
        )
        return .result(
            value: ShortcutExportKind.summarizing(ShortcutExportKind.kinds(fromExportLines: lines))
        )
    }
}

struct ExporterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LastSuccessfulExportIntent(),
            phrases: [
                "Get last successful export with \(.applicationName)",
                "Check export status with \(.applicationName)",
            ],
            shortTitle: "Last export status",
            systemImageName: "heart.text.clipboard"
        )
        AppShortcut(
            intent: ExportOnePageIntent(),
            phrases: [
                "Export one page with \(.applicationName)",
                "Export now with \(.applicationName)",
                "Run a local export with \(.applicationName)",
            ],
            shortTitle: "Export now",
            systemImageName: "square.and.arrow.up"
        )
        AppShortcut(
            intent: ExportTypeWindowIntent(),
            phrases: [
                "Export a type for a window with \(.applicationName)",
            ],
            shortTitle: "Export type for window",
            systemImageName: "calendar"
        )
    }
}
