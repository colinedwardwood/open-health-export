// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import EnginePorts
import Foundation

/// ADR-HK-7: the deletion-dating index is date-bounded, not a trailing day count.
/// Low-cardinality types keep unbounded rows; everything else evicts oldest-day-first
/// at 48 MB (~40 bytes/row including B-tree overhead).
public enum EmittedIndexPolicy {
    public static let capBytes = 48 * 1024 * 1024
    public static let bytesPerRow = 40
    public static let horizonJournalToken = "index_horizon"

    public static let unboundedRetentionMetrics: Set<MetricID> = [
        MetricID(rawValue: "workout"),
        MetricID(rawValue: "sleep_analysis"),
        MetricID(rawValue: "bodyMass"),
        MetricID(rawValue: "bloodPressureSystolic"),
        MetricID(rawValue: "bloodPressureDiastolic"),
        MetricID(rawValue: "bloodGlucose"),
        MetricID(rawValue: "electrocardiogram"),
    ]

    public static func overCap(
        rowCount: Int,
        capBytes: Int = capBytes,
        bytesPerRow: Int = bytesPerRow
    ) -> Bool {
        rowCount > 0 && rowCount * bytesPerRow > capBytes
    }

    /// Aggregate verification stops at the earlier of the page's complete day and the
    /// published index horizon. Returns a calendar day, not a timestamp.
    public static func verifiedThrough(completeThrough: String?, horizonDay: String?) -> String? {
        let completeDay = completeThrough.map { String($0.prefix(10)) }
        switch (completeDay, horizonDay) {
        case let (complete?, horizon?):
            return complete < horizon ? complete : horizon
        case let (complete?, nil):
            return complete
        case let (nil, horizon?):
            return horizon
        case (nil, nil):
            return nil
        }
    }
}

enum EmittedIndex {
    static func record(
        page: SamplePage,
        batchID: BatchID,
        on tx: any StateTransaction,
        atEpoch: TimeInterval = 0,
        capBytes: Int = EmittedIndexPolicy.capBytes,
        bytesPerRow: Int = EmittedIndexPolicy.bytesPerRow
    ) throws {
        for entry in page.censusKeys {
            try tx.upsertEmittedIndex(
                EmittedIndexRow(
                    uuid: entry.uuid,
                    metric: page.metric,
                    day: entry.day,
                    digest: Census.digestUUIDs([entry.uuid]),
                    batchID: batchID
                )
            )
        }
        try enforceCap(
            on: tx,
            atEpoch: atEpoch,
            capBytes: capBytes,
            bytesPerRow: bytesPerRow
        )
    }

    @discardableResult
    static func enforceCap(
        on tx: any StateTransaction,
        atEpoch: TimeInterval = 0,
        capBytes: Int = EmittedIndexPolicy.capBytes,
        bytesPerRow: Int = EmittedIndexPolicy.bytesPerRow
    ) throws -> String? {
        let pinned = EmittedIndexPolicy.unboundedRetentionMetrics
        var evicted: [String] = []
        var affected: Set<MetricID> = []
        while EmittedIndexPolicy.overCap(
            rowCount: try tx.emittedIndexRowCount(),
            capBytes: capBytes,
            bytesPerRow: bytesPerRow
        ) {
            guard let day = try tx.oldestEvictableEmittedDay(excluding: pinned) else {
                break
            }
            for metric in try tx.emittedIndexMetrics(day: day, excluding: pinned) {
                affected.insert(metric)
            }
            try tx.removeEmittedIndex(day: day, excluding: pinned)
            evicted.append(day)
        }
        let horizon = try tx.emittedIndexHorizonDay(excluding: pinned) ?? evicted.max()
        if let horizon {
            try tx.upsertIndexHorizonDay(horizon)
            for metric in affected {
                try tx.clampVerifiedThroughDay(metric: metric, horizonDay: horizon)
            }
            if !evicted.isEmpty {
                try tx.appendJournal(
                    RunEvent(
                        runID: RunID(rawValue: "emitted-index"),
                        outcomeKind: "partial",
                        detail: "\(EmittedIndexPolicy.horizonJournalToken) day=\(horizon) "
                            + "evicted=\(evicted.sorted().joined(separator: ","))",
                        wallTimeEpoch: atEpoch
                    )
                )
            }
        }
        return horizon
    }
}
