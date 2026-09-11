import CoreDomain
import EnginePorts
import MetricCatalog

/// Per-(metric, day) census: accumulate across pages; XOR digests so merges are order-independent.
enum Census {
    static func apply(page: SamplePage, to tx: any StateTransaction) throws {
        var delta: [String: (count: Int, xor: UInt64)] = [:]

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
                try tx.appendJournal(
                    RunEvent(
                        runID: RunID(rawValue: "census-\(page.metric.rawValue)"),
                        outcomeKind: "partial",
                        detail: "deletion_undatable"
                    )
                )
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
