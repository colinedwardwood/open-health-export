import EnginePorts
import Foundation

/// R-23 escalation is a pure function of snapshot, clock, and notification permission.
public struct EscalationPlan: Sendable, Equatable {
    public var overdue: Bool
    public var inAppCopy: String
    public var notification: UserNotice?
    public var widgetEntries: [DestinationTimelineEntry]
    public var claimsNotificationBadge: Bool

    public init(
        overdue: Bool,
        inAppCopy: String,
        notification: UserNotice?,
        widgetEntries: [DestinationTimelineEntry],
        claimsNotificationBadge: Bool
    ) {
        self.overdue = overdue
        self.inAppCopy = inAppCopy
        self.notification = notification
        self.widgetEntries = widgetEntries
        self.claimsNotificationBadge = claimsNotificationBadge
    }
}

public enum EscalationCopy {
    public static let overdue = "Export is overdue."
    public static let overdueNotificationsOff =
        "Export is overdue. Notifications are off — use the widget."
}

public enum OverdueNotificationSchedule {
    public static func fireEpoch(
        snapshot: DestinationStatusSnapshot
    ) -> TimeInterval? {
        guard snapshot.enabled,
              let lastSuccess = snapshot.lastSuccessEpoch,
              let threshold = snapshot.overdueThresholdSeconds
        else {
            return nil
        }
        return lastSuccess + threshold
    }
}

public enum Escalation {
    public static func plan(
        snapshot: DestinationStatusSnapshot,
        now: Date,
        notificationsAuthorized: Bool
    ) -> EscalationPlan {
        let nowEpoch = now.timeIntervalSince1970
        let overdue = snapshot.state(at: nowEpoch) == .overdue
        let entries = DestinationTimelinePlanner.entries(
            snapshots: [snapshot],
            nowEpoch: nowEpoch
        )
        guard overdue else {
            return EscalationPlan(
                overdue: false,
                inAppCopy: "",
                notification: nil,
                widgetEntries: entries,
                claimsNotificationBadge: false
            )
        }
        if notificationsAuthorized {
            return EscalationPlan(
                overdue: true,
                inAppCopy: EscalationCopy.overdue,
                notification: UserNotice(
                    kind: .exportOverdue,
                    destination: snapshot.destinationLabel
                ),
                widgetEntries: entries,
                claimsNotificationBadge: false
            )
        }
        return EscalationPlan(
            overdue: true,
            inAppCopy: EscalationCopy.overdueNotificationsOff,
            notification: nil,
            widgetEntries: entries,
            claimsNotificationBadge: false
        )
    }

    public static func deliver(
        _ plan: EscalationPlan,
        notifier: UserNotifier
    ) async throws -> NoticeDelivery {
        guard let notice = plan.notification else {
            return plan.overdue ? .skippedAuthorizationDenied : .notRequired
        }
        return try await notifier.notify(notice)
    }
}
