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
                    rangeDescription: "queue_eviction:\(victim.byteCount)"
                )
            )
        }
        return victims
    }
}
