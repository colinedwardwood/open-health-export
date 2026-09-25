// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Every UserDefaults key the app reads or writes, in one place (#42). The raw values
/// are the keys already on disk and in UI-test launch arguments, so they never change
/// once shipped. policycheck rejects an `"ohe.` string literal anywhere else in Apps.
enum SettingKey: String, CaseIterable {
    case advisoryEnabled = "ohe.advisoryEnabled"
    case advisoryLastAttemptEpoch = "ohe.advisoryLastAttemptEpoch"
    case advisoryLastSeenSeq = "ohe.advisoryLastSeenSeq"
    case advisoryLastVerifiedEpoch = "ohe.advisoryLastVerifiedEpoch"
    case appPrivacyGateEnabled = "ohe.appPrivacyGateEnabled"
    case backfillMode = "ohe.backfillMode"
    case backgroundSubmitFailure = "ohe.backgroundSubmitFailure"
    case browserDemoMode = "ohe.browserDemoMode"
    case browserOnlyWithData = "ohe.browserOnlyWithData"
    case clockDisplay = "ohe.clockDisplay"
    case companionPropagateTraceparent = "ohe.companion.propagateTraceparent"
    case diagnosticMinimumRuns = "ohe.diagnosticMinimumRuns"
    case diagnosticWindowHours = "ohe.diagnosticWindowHours"
    case disclosureAcknowledged = "ohe.disclosureAcknowledged"
    case displayUnitPreference = "ohe.displayUnitPreference"
    case exportWindowHours = "ohe.exportWindowHours"
    case freshnessIntervalMinutes = "ohe.freshnessIntervalMinutes"
    case lastScheduledFullReconcileEpoch = "ohe.lastScheduledFullReconcileEpoch"
    case notificationCooldownV1 = "ohe.notificationCooldown.v1"
    case notificationsPreviouslyDenied = "ohe.notificationsPreviouslyDenied"
    case observerRegistrationFailures = "ohe.observerRegistrationFailures"
    case presetCoreDailyAppliedVersion = "ohe.preset.coreDaily.appliedVersion"
    case shareProtectionAcknowledged = "ohe.shareProtectionAcknowledged"
}

enum SettingsStore {
    /// Whether this installation exports automatically to a destination or leaves it
    /// manual-only (AR-15).
    static func exportRoleKey(_ destinationID: String) -> String {
        "ohe.\(destinationID).exportRole"
    }

    /// Whether a destination may send over cellular and other metered networks.
    static func allowsMeteredNetworkKey(_ destinationID: String) -> String {
        "ohe.\(destinationID).allowsMeteredNetwork"
    }

    /// The name of the background-task assertion an export holds while it uploads.
    static let exportBackgroundTaskName = "ohe.https.export"
}
