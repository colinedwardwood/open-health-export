// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public enum RetryClass: String, Sendable, Codable {
    case transientNetwork
    case transientServer
    case awaitingUnmetered
    case clientConfig
    case auth
    case pinChangeHalt
    case localStorageFull
    case storeLocked
    case unknownAck
    case `protocol`
}

public enum BreakerState: String, Sendable, Codable, Equatable {
    case closed
    case open
    case halfOpen
    case blockedNeedsUser
    case halted
    case failingPersistently
}

public struct BreakerSnapshot: Sendable, Codable, Equatable {
    public var state: BreakerState
    public var consecutiveFailures: Int
    public var consecutiveUnknownAcks: Int
    public var openedAt: Date?
    public var nextEarliestAttempt: Date?

    public init(
        state: BreakerState = .closed,
        consecutiveFailures: Int = 0,
        consecutiveUnknownAcks: Int = 0,
        openedAt: Date? = nil,
        nextEarliestAttempt: Date? = nil
    ) {
        self.state = state
        self.consecutiveFailures = consecutiveFailures
        self.consecutiveUnknownAcks = consecutiveUnknownAcks
        self.openedAt = openedAt
        self.nextEarliestAttempt = nextEarliestAttempt
    }
}

public enum DeliveryAttemptResult: Sendable, Equatable {
    case acknowledged
    case failed(RetryClass, retryAfter: TimeInterval? = nil)
    case unknownAck
}

/// Pure retry/breaker state machine. One invocation records one transport result; it never sleeps
/// or retries. `jitter` is injected so tests and ledgers can reproduce every scheduling decision.
public enum RetryPolicy {
    public static let baseDelay: TimeInterval = 15
    public static let maximumDelay: TimeInterval = 6 * 60 * 60
    public static let maximumRetryAfter: TimeInterval = 24 * 60 * 60
    public static let persistentAfter: TimeInterval = 7 * 24 * 60 * 60

    public static func record(
        _ result: DeliveryAttemptResult,
        snapshot: BreakerSnapshot,
        now: Date,
        jitter: Double
    ) -> BreakerSnapshot {
        precondition((0...1).contains(jitter))
        switch result {
        case .acknowledged:
            return BreakerSnapshot()
        case .unknownAck:
            var next = snapshot
            next.consecutiveFailures += 1
            next.consecutiveUnknownAcks += 1
            schedule(&next, now: now, jitter: jitter, retryAfter: nil)
            if next.consecutiveUnknownAcks >= 3 {
                open(&next, now: now)
            }
            return next
        case .failed(let retryClass, let retryAfter):
            return recordFailure(
                retryClass,
                retryAfter: retryAfter,
                snapshot: snapshot,
                now: now,
                jitter: jitter
            )
        }
    }

    /// Foregrounding grants one free real-batch probe. Background work obeys the back-off window.
    public static func mayAttempt(
        snapshot: BreakerSnapshot,
        now: Date,
        foreground: Bool
    ) -> Bool {
        switch snapshot.state {
        case .closed, .halfOpen:
            return snapshot.nextEarliestAttempt.map { now >= $0 } ?? true
        case .open, .failingPersistently:
            return foreground || snapshot.nextEarliestAttempt.map { now >= $0 } ?? false
        case .blockedNeedsUser, .halted:
            return false
        }
    }

    public static func beginProbe(
        snapshot: BreakerSnapshot,
        now: Date,
        foreground: Bool
    ) -> BreakerSnapshot {
        guard mayAttempt(snapshot: snapshot, now: now, foreground: foreground) else {
            return snapshot
        }
        guard snapshot.state == .open || snapshot.state == .failingPersistently else {
            return snapshot
        }
        var next = snapshot
        next.state = .halfOpen
        return next
    }

    public static func age(snapshot: BreakerSnapshot, now: Date) -> BreakerSnapshot {
        guard snapshot.state == .open,
              let openedAt = snapshot.openedAt,
              now.timeIntervalSince(openedAt) >= persistentAfter
        else {
            return snapshot
        }
        var next = snapshot
        next.state = .failingPersistently
        next.nextEarliestAttempt = max(
            next.nextEarliestAttempt ?? now,
            now.addingTimeInterval(maximumDelay)
        )
        return next
    }

    private static func recordFailure(
        _ retryClass: RetryClass,
        retryAfter: TimeInterval?,
        snapshot: BreakerSnapshot,
        now: Date,
        jitter: Double
    ) -> BreakerSnapshot {
        var next = snapshot
        next.consecutiveUnknownAcks = 0
        switch retryClass {
        case .pinChangeHalt:
            next.state = .halted
            next.nextEarliestAttempt = nil
        case .clientConfig, .auth, .protocol:
            next.consecutiveFailures += 1
            next.state = .blockedNeedsUser
            next.openedAt = next.openedAt ?? now
            next.nextEarliestAttempt = nil
        case .transientNetwork, .transientServer:
            next.consecutiveFailures += 1
            schedule(&next, now: now, jitter: jitter, retryAfter: retryAfter)
            if next.state == .halfOpen || next.consecutiveFailures >= 5 {
                open(&next, now: now)
            }
        case .unknownAck:
            return record(.unknownAck, snapshot: snapshot, now: now, jitter: jitter)
        case .awaitingUnmetered, .localStorageFull, .storeLocked:
            break
        }
        return next
    }

    private static func open(_ snapshot: inout BreakerSnapshot, now: Date) {
        snapshot.state = .open
        snapshot.openedAt = snapshot.openedAt ?? now
    }

    private static func schedule(
        _ snapshot: inout BreakerSnapshot,
        now: Date,
        jitter: Double,
        retryAfter: TimeInterval?
    ) {
        let delay: TimeInterval
        if let retryAfter {
            delay = min(max(0, retryAfter), maximumRetryAfter)
        } else {
            let exponent = min(snapshot.consecutiveFailures, 31)
            let ceiling = min(maximumDelay, baseDelay * pow(2, Double(exponent)))
            delay = ceiling * jitter
        }
        snapshot.nextEarliestAttempt = now.addingTimeInterval(delay)
    }
}
