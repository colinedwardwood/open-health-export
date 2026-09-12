// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import EnginePorts
import Foundation

public enum QueueAdmissionError: Error, Equatable {
    case blocked
}

/// R-09: oldest-first eviction inside the enqueue transaction, before the new cursor commits.
public struct QueuePolicy: Sendable, Equatable {
    public var cap: Int
    public var lowWatermark: Int

    public init(cap: Int, lowWatermark: Int) {
        self.cap = cap
        self.lowWatermark = lowWatermark
    }

    public static let production = QueuePolicy(
        cap: 256 * 1024 * 1024,
        lowWatermark: 230 * 1024 * 1024
    )

    /// I6 Amber: catch-up (reconcile, backfill, re-export) stops at 60% of cap.
    public var catchUpLimit: Int { cap * 3 / 5 }
    /// I6 Red: derived caches purge and the WAL truncates at 80% of cap. Still no eviction.
    public var redLimit: Int { cap * 4 / 5 }
    /// Re-export may pin up to 25% of cap (64 MB at the production 256 MB cap).
    public var pinnedBudget: Int { cap / 4 }
}

/// I6: catch-up work never evicts live delta batches. Amber occupancy parks
/// reconcile/backfill instead of calling `makeRoom`.
public enum CatchUpAdmission {
    public static let parkedJournalDetail = "catch_up_parked"
    /// I6: destination still broken; catch-up waits instead of occupying the live queue.
    public static let destinationParkedJournalDetail = "breaker_open"

    public static func allows(
        queuedBytes: Int,
        incomingBytes: Int = 0,
        policy: QueuePolicy = .production
    ) -> Bool {
        queuedBytes + incomingBytes < policy.catchUpLimit
    }

    public static func allows(breaker: BreakerSnapshot) -> Bool {
        switch breaker.state {
        case .closed, .halfOpen:
            return true
        case .open, .blockedNeedsUser, .halted, .failingPersistently:
            return false
        }
    }
}

public enum QueueOccupancy: Int, Sendable, Comparable {
    case green
    case amber
    case red
    case overCap

    public static func < (lhs: QueueOccupancy, rhs: QueueOccupancy) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var snapshotToken: String {
        switch self {
        case .green: "green"
        case .amber: "amber"
        case .red: "red"
        case .overCap: "over_cap"
        }
    }
}

/// I6 Red: Amber still holds, plus derived attempt-body caches are dropped and
/// SQLite's WAL is truncated so occupancy can fall without evicting live batches.
public enum QueueRed {
    public static let attemptsDirectoryName = "attempts"
    public static let journalDetail = "queue_red"

    public static func occupancy(
        queuedBytes: Int,
        policy: QueuePolicy = .production
    ) -> QueueOccupancy {
        if queuedBytes >= policy.cap { return .overCap }
        if queuedBytes >= policy.redLimit { return .red }
        if queuedBytes >= policy.catchUpLimit { return .amber }
        return .green
    }

    public static func purgeAttemptCaches(root: URL) throws -> Int {
        let directory = root.appendingPathComponent(attemptsDirectoryName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        let items = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for item in items {
            try FileManager.default.removeItem(at: item)
        }
        return items.count
    }
}

public enum ScheduledReconcile {
    public static let defaultInterval: TimeInterval = 86_400

    public static func due(
        lastEpoch: TimeInterval?,
        nowEpoch: TimeInterval,
        interval: TimeInterval = defaultInterval
    ) -> Bool {
        guard interval > 0 else { return false }
        guard let lastEpoch else { return true }
        return nowEpoch - lastEpoch >= interval
    }
}

public enum QueueAdmission {
    public static func evictionClass(
        reason: String,
        pinnedBytes: Int,
        incomingBytes: Int,
        policy: QueuePolicy = .production
    ) -> QueueEvictionClass {
        guard reason == "gap_reexport" else { return .normal }
        if pinnedBytes + incomingBytes <= policy.pinnedBudget {
            return .pinned
        }
        return .normal
    }

    @discardableResult
    public static func makeRoom(
        for incomingBytes: Int,
        on tx: any StateTransaction,
        policy: QueuePolicy = .production
    ) throws -> [PendingBatch] {
        let queued = try tx.queuedBytes()
        if queued + incomingBytes <= policy.cap {
            return []
        }
        var remaining = queued
        var victims: [PendingBatch] = []
        for batch in try tx.pendingBatches() {
            if remaining + incomingBytes <= policy.lowWatermark { break }
            if batch.evictionClass == .pinned { continue }
            victims.append(batch)
            remaining -= batch.byteCount
        }
        if remaining + incomingBytes > policy.cap {
            throw QueueAdmissionError.blocked
        }
        for victim in victims {
            try tx.evict(
                victim.id,
                recording: GapRecord(
                    evicting: victim,
                    rangeDescription: [
                        "queue_eviction",
                        victim.rangeStartDay ?? "unknown",
                        victim.rangeEndDay ?? "unknown",
                    ].joined(separator: ":")
                )
            )
        }
        return victims
    }
}
