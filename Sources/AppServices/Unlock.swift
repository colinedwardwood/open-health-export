// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import EnginePorts
import Foundation

/// Whether this install has the one-time unlock (D-08a, D-08b, #68).
public enum UnlockState: String, Sendable, Equatable, Codable {
    /// Built from source: everything is unlocked, always (D-08a).
    case sourceBuild
    /// App Store build without the purchase: manual export to every destination.
    case locked
    /// Purchased, or shared through Family Sharing.
    case unlocked
    /// Refunded or revoked. Behaves as locked; nothing configured is deleted.
    case revoked

    public var isUnlocked: Bool {
        self == .sourceBuild || self == .unlocked
    }
}

/// D-08b: the free tier is everything the person starts themselves; the unlock adds
/// everything that runs on its own. Security notices and updates are never gated,
/// and neither is any destination, data type or setting.
public enum AutomationGate {
    /// Runs the person starts by hand. Shortcuts are not among them: a Shortcut can
    /// be scheduled as an automation, which is the automatic export the unlock adds.
    public static func isManual(_ trigger: RunTrigger) -> Bool {
        switch trigger {
        case .manual, .widgetControl:
            true
        case .observerQuery, .bgAppRefresh, .bgProcessing, .shortcut, .appForeground, .launch:
            false
        }
    }

    public static func allows(_ trigger: RunTrigger, state: UnlockState) -> Bool {
        isManual(trigger) || state.isUnlocked
    }
}

/// The current state, decided from what StoreKit last reported. The last known
/// answer is remembered so background wakes, which can't wait on the App Store,
/// still decide correctly offline.
public enum UnlockDecision {
    public static func state(
        isStoreBuild: Bool,
        hasEntitlement: Bool?,
        wasRevoked: Bool,
        lastKnown: UnlockState?
    ) -> UnlockState {
        guard isStoreBuild else { return .sourceBuild }
        if wasRevoked { return .revoked }
        if let hasEntitlement { return hasEntitlement ? .unlocked : .locked }
        // StoreKit had nothing to say yet (first launch offline): keep the last answer,
        // or start locked. Manual export works either way.
        return lastKnown ?? .locked
    }

    /// What Status and Settings say about it.
    public static func summary(_ state: UnlockState) -> String {
        switch state {
        case .sourceBuild:
            "Built from source: automatic exports are included."
        case .unlocked:
            "Unlocked. Exports run on their own as iOS allows."
        case .locked:
            "Export now works with every destination. The one-time unlock adds automatic exports."
        case .revoked:
            "The unlock was refunded or revoked, so exports run only when you tap Export now. Your destinations and settings are unchanged."
        }
    }
}
