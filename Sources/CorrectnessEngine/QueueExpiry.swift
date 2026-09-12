// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import EnginePorts
import Foundation

public struct QueueExpiryResult: Sendable, Equatable {
    public var expiredBatches: Int
    public var expiredRecords: Int
    public var expiredBytes: Int

    public init(expiredBatches: Int, expiredRecords: Int, expiredBytes: Int) {
        self.expiredBatches = expiredBatches
        self.expiredRecords = expiredRecords
        self.expiredBytes = expiredBytes
    }

    public static let none = QueueExpiryResult(
        expiredBatches: 0,
        expiredRecords: 0,
        expiredBytes: 0
    )
}

/// R-44's hard exposure bound when HealthKit revocation remains unobservable.
public enum QueueExpiry {
    public static let timeToLive: TimeInterval = 7 * 24 * 60 * 60

    static func apply(
        nowEpoch: TimeInterval,
        destination: String,
        on tx: any StateTransaction
    ) throws -> (QueueExpiryResult, [String]) {
        let expired = try tx.pendingBatches().filter { batch in
            guard let created = batch.createdAtEpoch else { return false }
            return nowEpoch >= created + timeToLive
        }
        guard !expired.isEmpty else { return (.none, []) }

        for batch in expired {
            try tx.evict(
                batch.id,
                recording: GapRecord(
                    evicting: batch,
                    rangeDescription: "queue_ttl_expired"
                )
            )
            try tx.appendLedger(
                EgressEntry(
                    destination: destination,
                    sampleCount: batch.expectedRecords,
                    outcomeKind: "queue_ttl_expired",
                    byteCount: batch.byteCount,
                    wallTimeEpoch: nowEpoch
                )
            )
        }
        let result = QueueExpiryResult(
            expiredBatches: expired.count,
            expiredRecords: expired.reduce(0) { $0 + $1.expectedRecords },
            expiredBytes: expired.reduce(0) { $0 + $1.byteCount }
        )
        try tx.appendJournal(
            RunEvent(
                runID: RunID(rawValue: "queue-expiry"),
                outcomeKind: "queue_ttl_expired",
                detail: "",
                trigger: .launch,
                samplesRead: 0,
                samplesCommitted: result.expiredRecords,
                samplesAcked: 0,
                wallTimeEpoch: nowEpoch
            )
        )
        return (result, expired.map(\.payloadURL))
    }
}

extension StateStore {
    public func expirePending(
        nowEpoch: TimeInterval,
        destination: String
    ) async throws -> QueueExpiryResult {
        let (result, payloadURLs) = try await transact { tx in
            try QueueExpiry.apply(
                nowEpoch: nowEpoch,
                destination: destination,
                on: tx
            )
        }
        for path in payloadURLs {
            try? FileManager.default.removeItem(atPath: path)
        }
        return result
    }
}
