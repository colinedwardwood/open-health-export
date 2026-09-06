import CoreDomain
import EnginePorts

enum EmittedIndex {
    static func record(page: SamplePage, batchID: BatchID, on tx: any StateTransaction) throws {
        for sample in page.samples {
            let day = String(sample.start.prefix(10))
            try tx.upsertEmittedIndex(
                EmittedIndexRow(
                    uuid: sample.key.uuid,
                    metric: page.metric,
                    day: day,
                    digest: Census.digestUUIDs([sample.key.uuid]),
                    batchID: batchID
                )
            )
        }
    }
}
