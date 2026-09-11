// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import EnginePorts

/// Pure R-08 cell comparison. No HealthKit; callers supply observed folds.
public struct CellCensus: Sendable, Equatable {
    public var count: Int
    public var digestXor: UInt64
    public var digestSum: UInt64

    public init(count: Int, digestXor: UInt64, digestSum: UInt64) {
        self.count = count
        self.digestXor = digestXor
        self.digestSum = digestSum
    }
}

public enum ReconcileCellOutcome: Sendable, Equatable {
    case identical
    case countGreater
    case countSmaller
    case digestMismatch
}

public enum ReconcileCompare {
    public static func fold(uuids: [String]) -> CellCensus {
        var xor: UInt64 = 0
        var sum: UInt64 = 0
        for uuid in uuids {
            let d = Census.sampleDigest(uuid)
            xor ^= d
            sum &+= d
        }
        return CellCensus(count: uuids.count, digestXor: xor, digestSum: sum)
    }

    public static func compare(stored: CensusRow, observed: CellCensus) -> ReconcileCellOutcome {
        let storedXor = UInt64(stored.digest, radix: 16) ?? 0
        if observed.count > stored.sampleCount {
            return .countGreater
        }
        if observed.count < stored.sampleCount {
            return .countSmaller
        }
        if storedXor != observed.digestXor {
            return .digestMismatch
        }
        return .identical
    }

    /// UUIDs we emitted for the day that are absent from the fresh HealthKit set.
    public static func absentUUIDs(
        indexed: [EmittedIndexRow],
        observedUUIDs: Set<String>
    ) -> [String] {
        indexed.map(\.uuid).filter { !observedUUIDs.contains($0) }.sorted()
    }

    public static func tombstonesForAbsence(
        indexed: [EmittedIndexRow],
        observedUUIDs: Set<String>,
        metric: MetricID
    ) -> [TombstoneRecord] {
        absentUUIDs(indexed: indexed, observedUUIDs: observedUUIDs).map {
            TombstoneRecord(key: RecordKey(uuid: $0), metric: metric)
        }
    }
}
