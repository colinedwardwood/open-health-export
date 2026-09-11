// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import DestinationTrust
import EnginePorts
import UserNotifications
import Watchdog

/// Platform R-40 notifier. Copy is resolved from `NoticeCopy`, never composed here.
final class LocalUserNotifier: UserNotifier, Sendable {
    func authorizationDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus == .denied
    }

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

    func rescheduleExportOverdue(
        snapshot: DestinationStatusSnapshot,
        now: Date = Date()
    ) async throws -> NoticeDelivery {
        let center = UNUserNotificationCenter.current()
        let identifier = "exportOverdue.\(snapshot.destinationID)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard let fireEpoch = OverdueNotificationSchedule.fireEpoch(snapshot: snapshot) else {
            return .notRequired
        }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral
        else {
            return .skippedAuthorizationDenied
        }
        let copy = NoticeCopy.render(
            UserNotice(
                kind: .exportOverdue,
                destination: snapshot.destinationLabel
            )
        )
        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.threadIdentifier = UserNotice.Kind.exportOverdue.rawValue
        let delay = max(1, fireEpoch - now.timeIntervalSince1970)
        try await center.add(
            UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: delay,
                    repeats: false
                )
            )
        )
        return .posted
    }
}
