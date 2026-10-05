// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import CoreDomain
import EnginePorts
import Foundation
import MetricCatalog
import Watchdog

/// One run on the History screen (#51): what happened, where, and why, in words.
public struct HistoryRow: Sendable, Equatable, Identifiable {
    public var id: String
    public var epoch: TimeInterval
    public var destinationID: String?
    public var destination: String
    public var typeName: String?
    public var trigger: String
    public var result: String
    public var isProblem: Bool
    public var state: DestinationDisplayState
    public var event: RunEvent
}

/// #51: the run journal as people read it. Problems or everything, one destination
/// or all; triggers and outcomes in words; an empty view that says what is true.
public enum HistoryPresentation {
    public enum Filter: String, Sendable, CaseIterable {
        case problems
        case all
    }

    public static func rows(
        _ events: [RunEvent],
        filter: Filter,
        destinationID: String? = nil
    ) -> [HistoryRow] {
        events
            .map(row)
            .filter { filter == .all || $0.isProblem }
            .filter { destinationID == nil || $0.destinationID == destinationID }
            .sorted { $0.epoch > $1.epoch }
    }

    /// What the filtered list says when it has nothing to show.
    public static func emptyCopy(_ events: [RunEvent], filter: Filter) -> String {
        guard !events.isEmpty else { return RunHistoryDetail.emptyStateCopy }
        let delivered = events.map(row).filter { !$0.isProblem }.count
        let runs = delivered == 1 ? "1 run" : "\(delivered.formatted()) runs"
        return filter == .problems
            ? "No problems in the last 90 days. \(runs) delivered."
            : RunHistoryDetail.emptyStateCopy
    }

    public static func trigger(_ trigger: RunTrigger) -> String {
        switch trigger {
        case .manual: "You tapped Export now"
        case .widgetControl: "Control Centre"
        case .shortcut: "Shortcut"
        case .observerQuery: "New Health data"
        case .bgAppRefresh, .bgProcessing: "Background"
        case .appForeground: "Opening the app"
        case .launch: "App launch"
        }
    }

    public static func row(_ event: RunEvent) -> HistoryRow {
        let kind = RunOutcome.Kind(rawValue: event.outcomeKind)
        let destinationID = event.facts.destinationID.flatMap { $0.isEmpty ? nil : $0 }
        let typeName = event.facts.metric
            .flatMap { MetricCatalog.declaration(for: MetricID(rawValue: $0)) }
            .map(\.displayName)
        return HistoryRow(
            id: "\(event.runID.rawValue)-\(event.facts.destinationID ?? "")-\(event.facts.metric ?? "")",
            epoch: event.wallTimeEpoch,
            destinationID: destinationID,
            destination: destinationID.map(DestinationRepository.label) ?? "All destinations",
            typeName: typeName,
            trigger: trigger(event.trigger),
            result: result(kind, records: event.samplesCommitted, errorClass: event.errorClass),
            isProblem: isProblem(kind),
            state: state(kind),
            event: event
        )
    }

    static func isProblem(_ kind: RunOutcome.Kind?) -> Bool {
        switch kind {
        case .success, .successNothingDue: false
        default: true
        }
    }

    static func state(_ kind: RunOutcome.Kind?) -> DestinationDisplayState {
        switch kind {
        case .success, .successNothingDue: .healthy
        case .partial: .partial
        case .unknownAck: .sentUnconfirmed
        case .failed, .localNetworkDenied: .failing
        case .blockedLowPower, .blockedUnmetered, .blockedDeviceLocked, .abandonedNoBudget,
             .cancelledBySystem, .migrationPending: .deferred
        case nil: .failing
        }
    }

    static func result(_ kind: RunOutcome.Kind?, records: Int, errorClass: String?) -> String {
        let count = records == 1 ? "1 record" : "\(records.formatted()) records"
        let reason = StatusDashboard.humanReason(errorClass)
        switch kind {
        case .success: return "Delivered \(count)."
        case .successNothingDue: return "Nothing new to send."
        case .partial: return "Delivered \(count); some weren't." + (reason.map { " \($0)" } ?? "")
        case .unknownAck: return "Sent \(count); the destination didn't confirm."
        case .failed, .localNetworkDenied, nil: return reason ?? "Not delivered."
        default: return reason ?? "Waiting for iOS to allow it."
        }
    }
}
