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
        case .queueExpired:
            return LocalizedNotice(
                title: "Queued exports expired",
                body: "\(notice.destination) had queued data older than seven days. It was deleted instead of being sent late."
            )
        }
    }
}
