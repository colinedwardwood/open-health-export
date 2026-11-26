// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import CompanionReceive
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
    /// #68: the last unlock state StoreKit reported, for background wakes and offline.
    case unlockLastKnown = "ohe.unlock.lastKnown"
    case backgroundSubmitFailure = "ohe.backgroundSubmitFailure"
    case browserDemoMode = "ohe.browserDemoMode"
    case browserOnlyWithData = "ohe.browserOnlyWithData"
    case clockDisplay = "ohe.clockDisplay"
    case companionPropagateTraceparent = "ohe.companion.propagateTraceparent"
    case diagnosticMinimumRuns = "ohe.diagnosticMinimumRuns"
    case diagnosticWindowHours = "ohe.diagnosticWindowHours"
    case disclosureAcknowledged = "ohe.disclosureAcknowledged"
    case displayUnitPreference = "ohe.displayUnitPreference"
    /// #59: the one iCloud Drive folder the person has accepted; cleared by Delete everything.
    case iCloudFolderAcknowledged = "ohe.iCloudFolderAcknowledged"
    case exportWindowHours = "ohe.exportWindowHours"
    case freshnessIntervalMinutes = "ohe.freshnessIntervalMinutes"
    /// #62: launch and background steps that failed and have not worked since.
    case launchIssuesV1 = "ohe.launchIssues.v1"
    case lastScheduledFullReconcileEpoch = "ohe.lastScheduledFullReconcileEpoch"
    case notificationCooldownV1 = "ohe.notificationCooldown.v1"
    case notificationsPreviouslyDenied = "ohe.notificationsPreviouslyDenied"
    case observerRegistrationFailures = "ohe.observerRegistrationFailures"
    case presetCoreDailyAppliedVersion = "ohe.preset.coreDaily.appliedVersion"
    case shareProtectionAcknowledged = "ohe.shareProtectionAcknowledged"
}

extension ICloudFolderAcknowledgement {
    static var app: Self {
        let key = SettingKey.iCloudFolderAcknowledged.rawValue
        return Self(storage: Storage(
            read: { UserDefaults.standard.string(forKey: key) },
            write: { UserDefaults.standard.set($0, forKey: key) }
        ))
    }
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
