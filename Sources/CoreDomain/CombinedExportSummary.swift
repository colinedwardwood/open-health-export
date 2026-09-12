// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

/// UX-24: a user-facing export of several selected types is Partial when any
/// type returned no data. Per-type journals may still record `successNothingDue`.
public enum CombinedExportSummary {
    public static func typesWithData(_ outcomes: [RunOutcome.Kind]) -> Int {
        outcomes.filter { $0 == .success }.count
    }

    public static func kind(_ outcomes: [RunOutcome.Kind]) -> RunOutcome.Kind {
        guard !outcomes.isEmpty else { return .successNothingDue }
        if outcomes.contains(.failed) { return .failed }
        if outcomes.contains(.localNetworkDenied) { return .localNetworkDenied }
        if outcomes.contains(.blockedDeviceLocked) { return .blockedDeviceLocked }
        if outcomes.contains(.abandonedNoBudget) { return .abandonedNoBudget }
        if outcomes.contains(.cancelledBySystem) { return .cancelledBySystem }
        if outcomes.contains(.partial) || outcomes.contains(.unknownAck) {
            return .partial
        }
        let withData = typesWithData(outcomes)
        if withData > 0, withData < outcomes.count {
            return .partial
        }
        if withData == outcomes.count {
            return .success
        }
        return .successNothingDue
    }

    public static func copy(_ outcomes: [RunOutcome.Kind]) -> String {
        let selected = outcomes.count
        let withData = typesWithData(outcomes)
        switch kind(outcomes) {
        case .partial:
            return "Partial · \(withData) of \(selected) types returned data. Review coverage."
        case .success:
            return "Exported from \(selected) types."
        case .successNothingDue:
            return "Nothing new to export."
        case .failed:
            return "Export failed."
        case .blockedDeviceLocked, .abandonedNoBudget, .cancelledBySystem:
            return "Export deferred."
        case .localNetworkDenied:
            return "Export is waiting for Local Network access."
        case .unknownAck:
            return "Sent, unconfirmed."
        }
    }

    public static func progress(current: Int, total: Int) -> String {
        "Reading \(current) of \(total) types"
    }
}
