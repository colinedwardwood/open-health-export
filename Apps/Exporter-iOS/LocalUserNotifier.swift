// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import DestinationTrust
import EnginePorts
import Foundation
import UserNotifications
import Watchdog

private actor NotificationCooldowns {
    static let shared = NotificationCooldowns()
    private let defaultsKey = SettingKey.notificationCooldownV1.rawValue

    func claim(_ notice: UserNotice, nowEpoch: TimeInterval) -> Bool {
        var state = UserDefaults.standard.data(forKey: defaultsKey)
            .flatMap { try? JSONDecoder().decode(NotificationRateLimitState.self, from: $0) }
            ?? NotificationRateLimitState()
        let allowed = NotificationRateLimit.claim(
            kind: notice.kind,
            destinationID: notice.destinationID,
            nowEpoch: nowEpoch,
            state: &state
        )
        if allowed,
           NotificationRateLimit.isFailureKind(notice.kind),
           let encoded = try? JSONEncoder().encode(state)
        {
            UserDefaults.standard.set(encoded, forKey: defaultsKey)
        }
        return allowed
    }
}

/// Platform R-40 notifier. Copy is resolved from `NoticeCopy`, never composed here.
final class LocalUserNotifier: UserNotifier, Sendable {
    /// Notices arrive quietly, and the person hasn't been asked for alerts yet.
    func canOfferAlerts() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .provisional || status == .notDetermined
    }

    /// The one place full alert permission is requested: from a failure the person is
    /// looking at, so they can judge what they're agreeing to (UX-35).
    func requestAlerts() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        )) ?? false
    }

    func authorizationDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus == .denied
    }

    func notify(_ notice: UserNotice) async throws -> NoticeDelivery {
        let copy = NoticeCopy.render(notice)
        let center = UNUserNotificationCenter.current()
        // UX-35: quiet (provisional) delivery until the person asks for alerts. Asking
        // here, mid-run, would put Apple's prompt over whatever they are doing, and a
        // refusal would take provisional delivery away too. The full request is
        // `requestAlerts()`, offered on the error a failure opens.
        let granted = try await center.requestAuthorization(
            options: [.alert, .sound, .badge, .provisional]
        )
        guard granted else { return .skippedAuthorizationDenied }
        guard await NotificationCooldowns.shared.claim(
            notice,
            nowEpoch: Date().timeIntervalSince1970
        ) else {
            return .skippedRateLimited
        }
        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.threadIdentifier = "dest.\(notice.destinationID)"
        content.userInfo = FailureNotificationPayload.userInfo(for: notice)
        let identifier = NotificationRateLimit.isFailureKind(notice.kind)
            ? "failure.\(notice.destinationID)"
            : "\(notice.kind.rawValue).\(notice.destinationID)"
        let request = UNNotificationRequest(
            identifier: identifier,
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
                destinationID: snapshot.destinationID,
                destination: snapshot.destinationLabel
            )
        )
        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.threadIdentifier = "dest.\(snapshot.destinationID)"
        content.userInfo = FailureNotificationPayload.userInfo(
            for: UserNotice(
                kind: .exportOverdue,
                destinationID: snapshot.destinationID,
                destination: snapshot.destinationLabel
            )
        )
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
