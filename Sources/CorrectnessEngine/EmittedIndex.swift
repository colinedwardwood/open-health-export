import CoreDomain
import EnginePorts

enum EmittedIndex {
    static func record(page: SamplePage, batchID: BatchID, on tx: any StateTransaction) throws {
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
    }
}
