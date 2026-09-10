import EnginePorts
import Foundation

/// User-facing copy for R-40. Kind is the registry key; interpolation happens here, never at
/// the call site that emitted the event (DP-6).
public struct LocalizedNotice: Sendable, Equatable {
    public var title: String
    public var body: String
}

public enum NoticeCopy {
    public static func render(_ notice: UserNotice) -> LocalizedNotice {
        switch notice.kind {
        case .destinationVerified:
            return LocalizedNotice(
                title: "Destination verified",
                body: "\(notice.destination) accepted the test payload. It is not enabled yet."
            )
        case .destinationPinned:
            if let fingerprint = notice.fingerprint {
                return LocalizedNotice(
                    title: "Destination pinned",
                    body: "\(notice.destination) is pinned to \(fingerprint). A later change will halt export."
                )
            }
            return LocalizedNotice(
                title: "Destination pinned",
                body: "\(notice.destination) is pinned without TLS. Use this only on a network you control."
            )
        case .destinationRepointed:
            let previous = notice.previousFingerprint ?? "the previous pin"
            let observed = notice.fingerprint ?? "a different identity"
            return LocalizedNotice(
                title: "Destination halted",
                body: "\(notice.destination) presented \(observed) instead of \(previous). Export is halted until you re-verify."
            )
        case .destinationEnabled:
            return LocalizedNotice(
                title: "Destination enabled",
                body: "\(notice.destination) can receive exports."
            )
        case .destinationTrustLost:
            return LocalizedNotice(
                title: "Destination unpaired",
                body: "\(notice.destination) is no longer trusted. Export is halted."
            )
        case .anchorInvalidated:
            return LocalizedNotice(
                title: "Export paused for some data",
                body: "The export lost its place in some of your Health data. Nothing more is being sent to \(notice.destination) for it until you choose whether to send that history again."
            )
        case .queueEvicted:
            return LocalizedNotice(
                title: "Queued export data removed",
                body: "\(notice.destination) reached its storage limit. Open Data gaps to re-export the affected date range."
            )
        case .queueExpired:
            return LocalizedNotice(
                title: "Queued exports expired",
                body: "\(notice.destination) had queued data older than seven days. It was deleted instead of being sent late."
            )
        case .exportOverdue:
            return LocalizedNotice(
                title: "Export overdue",
                body: "\(notice.destination) has not completed a successful export within the freshness window."
            )
        case .healthAccessRevoked:
            return LocalizedNotice(
                title: "Health access changed",
                body: "\(notice.destination) was disabled and its queued payloads were deleted after the app observed that Health access was revoked."
            )
        }
    }
}
