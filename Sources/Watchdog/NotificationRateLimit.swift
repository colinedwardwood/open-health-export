// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import EnginePorts
import Foundation

public struct NotificationRateLimitState: Codable, Sendable, Equatable {
    public var failureLastPostedEpochByDestinationID: [String: TimeInterval]

    public init(
        failureLastPostedEpochByDestinationID: [String: TimeInterval] = [:]
    ) {
        self.failureLastPostedEpochByDestinationID =
            failureLastPostedEpochByDestinationID
    }
}

public enum NotificationRateLimit {
    public static let failureWindowSeconds: TimeInterval = 24 * 60 * 60

    public static func isFailureKind(_ kind: UserNotice.Kind) -> Bool {
        kind == .exportFailed || kind == .exportOverdue || kind == .queueApproachingLoss
    }

    /// Atomically model "check then reserve" at the caller's clock. Export failures
    /// and overdue reminders share one destination bucket (UX-36).
    public static func claim(
        kind: UserNotice.Kind,
        destinationID: String,
        nowEpoch: TimeInterval,
        state: inout NotificationRateLimitState
    ) -> Bool {
        guard isFailureKind(kind) else { return true }
        if let previous = state.failureLastPostedEpochByDestinationID[destinationID],
           nowEpoch - previous < failureWindowSeconds
        {
            return false
        }
        state.failureLastPostedEpochByDestinationID[destinationID] = nowEpoch
        return true
    }
}
