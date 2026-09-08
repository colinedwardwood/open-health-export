import DestinationTrust
import EnginePorts
import UserNotifications

/// Platform R-40 notifier. Copy is resolved from `NoticeCopy`, never composed here.
final class LocalUserNotifier: UserNotifier, Sendable {
    func notify(_ notice: UserNotice) async throws -> NoticeDelivery {
        let copy = NoticeCopy.render(notice)
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        guard granted else { return .skippedAuthorizationDenied }
        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.threadIdentifier = notice.kind.rawValue
        let request = UNNotificationRequest(
            identifier: "\(notice.kind.rawValue).\(notice.destination)",
            content: content,
            trigger: nil
        )
        try await center.add(request)
        return .posted
    }
}
