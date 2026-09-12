// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import EnginePorts
import Foundation
import MetricCatalog

/// O-9: a deletion whose UUID has left the date-bounded emitted index. The token is
/// closed; `type` and `uuid` are identifiers, not health values.
public enum DeletionUndatable {
    public static let token = "deletion_undatable"

    public static func detail(metric: MetricID, uuid: String) -> String {
        "\(token) type=\(metric.rawValue) uuid=\(uuid)"
    }

    public static func parse(_ detail: String) -> (metric: MetricID, uuid: String)? {
        guard detail.hasPrefix(token + " ") else { return nil }
        var metric: MetricID?
        var uuid: String?
        for part in detail.split(separator: " ").dropFirst() {
            if part.hasPrefix("type="), metric == nil {
                metric = MetricID(rawValue: String(part.dropFirst("type=".count)))
            } else if part.hasPrefix("uuid="), uuid == nil {
                uuid = String(part.dropFirst("uuid=".count))
            }
        }
        guard let metric, let uuid, !uuid.isEmpty else { return nil }
        return (metric, uuid)
    }
}

struct CensusApplyResult: Sendable, Equatable {
    var undatableUUIDs: [String]
}

/// Per-(metric, day) census: accumulate across pages; XOR digests so merges are order-independent.
enum Census {
    @discardableResult
    static func apply(
        page: SamplePage,
        to tx: any StateTransaction,
        atEpoch: TimeInterval = 0
    ) throws -> CensusApplyResult {
        var delta: [String: (count: Int, xor: UInt64)] = [:]
        var undatableUUIDs: [String] = []

        for entry in page.censusKeys {
            if try tx.loadEmittedIndex(uuid: entry.uuid) != nil {
                // Already counted on a prior page; re-send must not inflate the census.
                continue
            }
            let fold = delta[entry.day] ?? (0, 0)
            delta[entry.day] = (fold.count + 1, fold.xor ^ sampleDigest(entry.uuid))
        }

        for tombstone in page.tombstones {
            if let indexed = try tx.loadEmittedIndex(uuid: tombstone.key.uuid) {
                let fold = delta[indexed.day] ?? (0, 0)
                delta[indexed.day] = (fold.count - 1, fold.xor ^ sampleDigest(tombstone.key.uuid))
                try tx.removeEmittedIndex(uuid: tombstone.key.uuid)
            } else {
                undatableUUIDs.append(tombstone.key.uuid)
                try tx.appendJournal(
                    RunEvent(
                        runID: RunID(rawValue: "census-\(page.metric.rawValue)"),
                        outcomeKind: "partial",
                        detail: DeletionUndatable.detail(
                            metric: page.metric,
                            uuid: tombstone.key.uuid
                        ),
                        wallTimeEpoch: atEpoch
                    )
                )
                if let horizon = try tx.loadIndexHorizonDay()
                    ?? tx.emittedIndexHorizonDay(
                        excluding: EmittedIndexPolicy.unboundedRetentionMetrics
                    )
                {
                    try tx.clampVerifiedThroughDay(metric: page.metric, horizonDay: horizon)
                }
            }
        }

        for (day, change) in delta {
            let prior = try tx.loadCensus(metric: page.metric, day: day)
            let priorXor = prior.flatMap { UInt64($0.digest, radix: 16) } ?? 0
            let sampleCount = (prior?.sampleCount ?? 0) + change.count
            let digestXor = priorXor ^ change.xor
            try tx.upsertCensus(
                CensusRow(
                    metric: page.metric,
                    day: day,
                    sampleCount: max(0, sampleCount),
                    digest: String(digestXor, radix: 16)
                )
            )
            if MetricCatalog.declaration(for: page.metric)?.kind == "sample.quantity" {
                try tx.markDirty(metric: page.metric, day: day)
            }
        }
        return CensusApplyResult(undatableUUIDs: undatableUUIDs)
    }

    /// R-08 reconcile rebuilds each swept day's census from the live observation set.
    /// Incremental apply cannot decrement a day it cannot date.
    static func replaceObserved(
        page: SamplePage,
        days: [String],
        to tx: any StateTransaction
    ) throws {
        var uuidsByDay: [String: [String]] = [:]
        for entry in page.censusKeys {
            uuidsByDay[entry.day, default: []].append(entry.uuid)
        }
        for day in days {
            let folded = fold(uuids: uuidsByDay[day] ?? [])
            try tx.upsertCensus(
                CensusRow(
                    metric: page.metric,
                    day: day,
                    sampleCount: folded.count,
                    digest: folded.digest
                )
            )
            if MetricCatalog.declaration(for: page.metric)?.kind == "sample.quantity" {
                try tx.markDirty(metric: page.metric, day: day)
            }
        }
        for tombstone in page.tombstones {
            if try tx.loadEmittedIndex(uuid: tombstone.key.uuid) != nil {
                try tx.removeEmittedIndex(uuid: tombstone.key.uuid)
            }
        }
    }

    /// Order-independent fold of UUID digests (XOR).
    static func fold(uuids: [String]) -> (count: Int, digest: String) {
        var xor: UInt64 = 0
        for uuid in uuids {
            xor ^= sampleDigest(uuid)
        }
        return (uuids.count, String(xor, radix: 16))
    }

    static func digestUUIDs(_ uuids: [String]) -> String {
        fold(uuids: uuids).digest
    }

    static func sampleDigest(_ uuid: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in uuid.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
        }
        return hash
    }
}
