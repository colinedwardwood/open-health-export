// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Q12 / S13: the Mac receiver notices when the phone has gone silent.
public struct CompanionReceiveWatch: Codable, Equatable, Sendable {
    public var lastReceivedEpoch: TimeInterval?
    public var lastQuietNoticeEpoch: TimeInterval?

    public init(
        lastReceivedEpoch: TimeInterval? = nil,
        lastQuietNoticeEpoch: TimeInterval? = nil
    ) {
        self.lastReceivedEpoch = lastReceivedEpoch
        self.lastQuietNoticeEpoch = lastQuietNoticeEpoch
    }
}

public enum CompanionQuietKind: Equatable, Sendable {
    case waitingForFirstTransfer
    case receiving(lastReceivedEpoch: TimeInterval)
    case quiet(lastReceivedEpoch: TimeInterval)
}

public enum CompanionQuietWatch {
    public static let quietAfterSeconds: TimeInterval = 3 * 24 * 60 * 60
    public static let noticeRepeatSeconds: TimeInterval = 24 * 60 * 60

    public static let waitingCopy =
        "Paired. Nothing received yet. Exports arrive when both devices are on the same network and the iPhone is unlocked."
    public static let quietTitle = "Nothing received for 3 days"
    public static let notificationIdentifier = "companion-quiet-watch"
    public static let menuBarTitle = "Companion"
    public static let openWindow = "Open receiver"

    public static func evaluate(
        lastReceivedEpoch: TimeInterval?,
        nowEpoch: TimeInterval
    ) -> CompanionQuietKind {
        guard let lastReceivedEpoch else {
            return .waitingForFirstTransfer
        }
        if nowEpoch - lastReceivedEpoch >= quietAfterSeconds {
            return .quiet(lastReceivedEpoch: lastReceivedEpoch)
        }
        return .receiving(lastReceivedEpoch: lastReceivedEpoch)
    }

    public static func statusCopy(
        _ kind: CompanionQuietKind
    ) -> String {
        switch kind {
        case .waitingForFirstTransfer:
            waitingCopy
        case .receiving(let epoch):
            "Last received \(formatUTC(epoch))."
        case .quiet(let epoch):
            quietTitle
                + ". The last transfer was \(formatUTC(epoch)). "
                + "Either your iPhone has not been on this network, or exports have stopped. "
                + "Check the exporter on your iPhone."
        }
    }

    /// Posts at most once per quiet spell, then daily while silence continues.
    public static func claimQuietNotice(
        kind: CompanionQuietKind,
        nowEpoch: TimeInterval,
        watch: inout CompanionReceiveWatch
    ) -> Bool {
        guard case .quiet(let lastReceived) = kind else { return false }
        if let posted = watch.lastQuietNoticeEpoch {
            if posted >= lastReceived,
               nowEpoch - posted < noticeRepeatSeconds
            {
                return false
            }
        }
        watch.lastQuietNoticeEpoch = nowEpoch
        return true
    }

    public static func formatUTC(_ epoch: TimeInterval) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date(timeIntervalSince1970: epoch))
    }
}
