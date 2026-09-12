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
}

/// I6: catch-up work never evicts live delta batches. Amber occupancy parks
/// reconcile/backfill instead of calling `makeRoom`.
public enum CatchUpAdmission {
    public static let parkedJournalDetail = "catch_up_parked"

    public static func allows(
        queuedBytes: Int,
        incomingBytes: Int = 0,
        policy: QueuePolicy = .production
    ) -> Bool {
        queuedBytes + incomingBytes < policy.catchUpLimit
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
                    batchID: victim.id,
                    rangeDescription: [
                        "queue_eviction",
                        victim.rangeStartDay ?? "unknown",
                        victim.rangeEndDay ?? "unknown",
                    ].joined(separator: ":"),
                    metric: victim.metric,
                    rangeStartDay: victim.rangeStartDay,
                    rangeEndDay: victim.rangeEndDay
                )
            )
        }
        return victims
    }
}
