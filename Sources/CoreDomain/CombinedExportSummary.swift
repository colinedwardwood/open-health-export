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
        // ADR-R8: nothing ran, so this explains the absence of every other result.
        if outcomes.contains(.migrationPending) { return .migrationPending }
        if outcomes.contains(.localNetworkDenied) { return .localNetworkDenied }
        if outcomes.contains(.blockedDeviceLocked) { return .blockedDeviceLocked }
        if outcomes.contains(.abandonedNoBudget) { return .abandonedNoBudget }
        if outcomes.contains(.cancelledBySystem) { return .cancelledBySystem }
        if outcomes.contains(.blockedLowPower) { return .blockedLowPower }
        if outcomes.contains(.blockedUnmetered) { return .blockedUnmetered }
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

    /// UX-38: Shortcut and Control Centre branches. Distinct from snapshot `kind`
    /// so a sent-unconfirmed ack does not collapse into Partial.
    public static func shortcutKind(_ outcomes: [RunOutcome.Kind]) -> String {
        if outcomes.contains(.failed) { return "failed" }
        if outcomes.contains(.localNetworkDenied) { return "blocked" }
        if outcomes.contains(.blockedDeviceLocked)
            || outcomes.contains(.abandonedNoBudget)
            || outcomes.contains(.cancelledBySystem)
            || outcomes.contains(.blockedLowPower)
            || outcomes.contains(.blockedUnmetered)
            || outcomes.contains(.migrationPending)
        {
            return "deferred"
        }
        if outcomes.contains(.unknownAck) { return "sentUnconfirmed" }
        switch kind(outcomes) {
        case .success: return "success"
        case .partial: return "partial"
        case .successNothingDue: return "nothingDue"
        case .failed: return "failed"
        case .localNetworkDenied: return "blocked"
        case .unknownAck: return "sentUnconfirmed"
        case .blockedDeviceLocked, .abandonedNoBudget, .cancelledBySystem, .blockedLowPower,
             .blockedUnmetered, .migrationPending:
            return "deferred"
        }
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
        case .blockedDeviceLocked, .abandonedNoBudget, .cancelledBySystem, .blockedLowPower,
             .blockedUnmetered:
            return "Export deferred."
        case .localNetworkDenied:
            return "Export is waiting for Local Network access."
        case .migrationPending:
            // Says what to do about it: the migration runs on a foreground launch, so
            // waiting for another background wake would wait forever.
            return "Export deferred. Open the app to finish a database update."
        case .unknownAck:
            return "Sent, unconfirmed."
        }
    }

    public static func progress(current: Int, total: Int) -> String {
        "Reading \(current) of \(total) types"
    }
}
