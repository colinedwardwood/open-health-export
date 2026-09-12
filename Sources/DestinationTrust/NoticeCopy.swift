// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import EnginePorts
import Foundation

/// User-facing copy for R-40. Kind is the registry key; interpolation happens here, never at
/// the call site that emitted the event (DP-6).
public struct LocalizedNotice: Sendable, Equatable {
    public var title: String
    public var body: String
}

public enum NoticeCopy {
    /// SEC-27: a notification body is Lock Screen content, so it may not read out a
    /// destination hostname. Labels are names a person chose ("Home Assistant",
    /// "Archive folder"); an identifier that is really an address is replaced rather
    /// than shown. Erring towards the generic term is the safe direction — the worst
    /// case is a vaguer notification, not an address on a locked screen.
    static func safeLabel(_ destination: String) -> String {
        let addressLike = destination.contains("://")
            || destination.contains(":")
            || destination.contains("/")
            || destination.contains(".")
        return addressLike ? "A destination" : destination
    }

    public static func render(_ notice: UserNotice) -> LocalizedNotice {
        let label = safeLabel(notice.destination)
        switch notice.kind {
        case .destinationVerified:
            return LocalizedNotice(
                title: "Destination verified",
                body: "\(label) accepted the test payload. It is not enabled yet."
            )
        case .destinationPinned:
            if let fingerprint = notice.fingerprint {
                return LocalizedNotice(
                    title: "Destination pinned",
                    body: "\(label) is pinned to \(fingerprint). A later change will halt export."
                )
            }
            return LocalizedNotice(
                title: "Destination pinned",
                body: "\(label) is pinned without TLS. Use this only on a network you control."
            )
        case .destinationRepointed:
            let previous = notice.previousFingerprint ?? "the previous pin"
            let observed = notice.fingerprint ?? "a different identity"
            return LocalizedNotice(
                title: "Destination halted",
                body: "\(label) presented \(observed) instead of \(previous). Export is halted until you re-verify."
            )
        case .destinationEnabled:
            return LocalizedNotice(
                title: "Destination enabled",
                body: "\(label) can receive exports."
            )
        case .destinationTrustLost:
            return LocalizedNotice(
                title: "Destination unpaired",
                body: "\(label) is no longer trusted. Export is halted."
            )
        case .anchorInvalidated:
            return LocalizedNotice(
                title: "Export paused for some data",
                body: "The export lost its place in some of your Health data. Nothing more is being sent to \(label) for it until you choose whether to send that history again."
            )
        case .queueEvicted:
            return LocalizedNotice(
                title: "Queued export data removed",
                body: "\(label) reached its storage limit. Open Data gaps to re-export the affected date range."
            )
        case .queueExpired:
            return LocalizedNotice(
                title: "Queued exports expired",
                body: "\(label) had queued data older than seven days. It was deleted instead of being sent late."
            )
        case .queueApproachingLoss:
            return LocalizedNotice(
                title: "Queued export storage is filling",
                body: "\(label) has been unreachable long enough that data loss is approaching."
            )
        case .exportFailed:
            return LocalizedNotice(
                title: "Export needs attention",
                body: "\(label) could not complete an export. Open the app for the cause and next step."
            )
        case .exportOverdue:
            return LocalizedNotice(
                title: "Export overdue",
                body: "\(label) has not completed a successful export within the freshness window."
            )
        case .healthAccessRevoked:
            return LocalizedNotice(
                title: "Health access changed",
                body: "\(label) was disabled and its queued payloads were deleted after the app observed that Health access was revoked."
            )
        }
    }
}
