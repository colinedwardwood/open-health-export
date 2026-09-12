// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import EnginePorts
import Foundation

/// UX-32: a failure notification lands on the five-part error with no further tap.
public struct UserFacingErrorRoute: Sendable, Equatable {
    public static let scheme = WidgetStatusRoute.scheme
    public static let host = "error"

    public var destinationID: String
    public var archetype: UserFacingErrorArchetype?

    public init(destinationID: String, archetype: UserFacingErrorArchetype? = nil) {
        self.destinationID = destinationID
        self.archetype = archetype
    }

    public init?(url: URL) {
        guard url.scheme == Self.scheme, url.host == Self.host else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        guard let destinationID = items.first(where: { $0.name == "destination" })?.value,
              !destinationID.isEmpty
        else {
            return nil
        }
        self.destinationID = destinationID
        if let raw = items.first(where: { $0.name == "archetype" })?.value {
            archetype = UserFacingErrorArchetype(rawValue: raw)
        } else {
            archetype = nil
        }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        var items = [URLQueryItem(name: "destination", value: destinationID)]
        if let archetype {
            items.append(URLQueryItem(name: "archetype", value: archetype.rawValue))
        }
        components.queryItems = items
        return components.url!
    }
}

/// Maps a durable destination snapshot onto the five-part error object.
public enum UserFacingErrorPresentation {
    public static func archetype(
        for snapshot: DestinationStatusSnapshot,
        nowEpoch: TimeInterval
    ) -> UserFacingErrorArchetype? {
        let state = snapshot.state(at: nowEpoch)
        switch state {
        case .overdue, .stale, .quiet:
            return .backgroundNeverRan
        case .failing, .blocked:
            if let mapped = mappedErrorClass(snapshot.errorClass) {
                return mapped
            }
            return .timeout
        case .deferred:
            return mappedErrorClass(snapshot.errorClass) ?? .healthLocked
        default:
            return mappedErrorClass(snapshot.errorClass)
        }
    }

    public static func object(
        for snapshot: DestinationStatusSnapshot,
        nowEpoch: TimeInterval
    ) -> UserFacingErrorObject? {
        guard let archetype = archetype(for: snapshot, nowEpoch: nowEpoch) else {
            return nil
        }
        return UserFacingErrorObject.make(
            archetype: archetype,
            destinationLabel: snapshot.destinationLabel
        )
    }

    public static func route(
        for snapshot: DestinationStatusSnapshot,
        nowEpoch: TimeInterval
    ) -> UserFacingErrorRoute? {
        guard let archetype = archetype(for: snapshot, nowEpoch: nowEpoch) else {
            return nil
        }
        return UserFacingErrorRoute(
            destinationID: snapshot.destinationID,
            archetype: archetype
        )
    }

    public static func object(
        route: UserFacingErrorRoute,
        snapshot: DestinationStatusSnapshot?,
        nowEpoch: TimeInterval
    ) -> UserFacingErrorObject? {
        let label = snapshot?.destinationLabel ?? route.destinationID
        if let archetype = route.archetype {
            return UserFacingErrorObject.make(archetype: archetype, destinationLabel: label)
        }
        guard let snapshot else { return nil }
        return object(for: snapshot, nowEpoch: nowEpoch)
    }

    private static func mappedErrorClass(_ raw: String?) -> UserFacingErrorArchetype? {
        guard let raw, let classified = ErrorClass(rawValue: raw) else { return nil }
        return UserFacingErrorArchetype.fromErrorClass(classified)
    }
}

public extension Notification.Name {
    static let oheOpenDeepLink = Notification.Name("ohe.openDeepLink")
}

/// Payload the notifier stamps so a tap reconstructs `UserFacingErrorRoute`.
public enum FailureNotificationPayload {
    public static let destinationIDKey = "destination_id"
    public static let openURLKey = "ohe_open_url"
    public static let notificationPolicyVersionKey = "notification_policy_version"

    public static func userInfo(for notice: UserNotice) -> [AnyHashable: Any] {
        var info: [AnyHashable: Any] = [
            notificationPolicyVersionKey: 1,
            destinationIDKey: notice.destinationID,
        ]
        if let url = url(for: notice) {
            info[openURLKey] = url.absoluteString
        }
        return info
    }

    public static func url(for notice: UserNotice) -> URL? {
        switch notice.kind {
        case .exportFailed:
            let archetype = notice.errorClass
                .flatMap(ErrorClass.init(rawValue:))
                .flatMap(UserFacingErrorArchetype.fromErrorClass)
                ?? .timeout
            return UserFacingErrorRoute(
                destinationID: notice.destinationID,
                archetype: archetype
            ).url
        case .exportOverdue:
            return UserFacingErrorRoute(
                destinationID: notice.destinationID,
                archetype: .backgroundNeverRan
            ).url
        default:
            return nil
        }
    }

    public static func url(from userInfo: [AnyHashable: Any]) -> URL? {
        guard let raw = userInfo[openURLKey] as? String,
              let url = URL(string: raw)
        else {
            return nil
        }
        if UserFacingErrorRoute(url: url) != nil { return url }
        if WidgetStatusRoute(url: url) != nil { return url }
        return nil
    }
}
