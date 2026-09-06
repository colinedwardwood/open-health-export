import CoreDomain
import DestinationTrust
import EnginePorts
import FileWriteKit
import Foundation
import WireFormat

public struct ExportRun: Sendable {
    public var source: any SampleSource
    public var destination: VerifiedDestination
    public var store: any StateStore
    public var metric: MetricID
    public var epoch: UInt32
    public var scratchDirectory: URL
    public var destinationName: String
    public var envelope: WireEnvelope

    public init(
        source: any SampleSource,
        destination: VerifiedDestination,
        store: any StateStore,
        metric: MetricID,
        epoch: UInt32 = 1,
        scratchDirectory: URL,
        destinationName: String = "local-file",
        envelope: WireEnvelope
    ) {
        self.source = source
        self.destination = destination
        self.store = store
        self.metric = metric
        self.epoch = epoch
        self.scratchDirectory = scratchDirectory
        self.destinationName = destinationName
        self.envelope = envelope
    }

    public func run() async throws -> RunOutcome {
        let prior = try await store.transact { tx in
            try tx.loadCursor(metric: metric)
        }
        let page = try await source.page(metric: metric, afterAnchor: prior?.anchorBlob)
        if page.samples.isEmpty, page.tombstones.isEmpty {
            let outcome = RunOutcome.derive(from: RunTally(nothingDue: true))
            try await record(outcome: outcome, tally: RunTally(nothingDue: true), receipt: nil)
            return outcome
        }

        let batchID = NativeWire.batchID(metric: metric, anchorBlob: page.anchorBlob)
        let payload = try NativeWire.encode(
            samples: page.samples,
            tombstones: page.tombstones,
            metric: metric,
            batchID: batchID,
            envelope: envelope
        )
        let payloadURL = scratchDirectory.appendingPathComponent("\(batchID.rawValue).ndjson")
        try FileWriteKit.writeAtomically(payload, to: payloadURL)

        try await store.transact { tx in
            try tx.commitBatch(
                PendingBatch(
                    id: batchID,
                    payloadURL: payloadURL.path,
                    expectedRecords: page.samples.count + page.tombstones.count
                ),
                advancing: CursorAdvance(page: page, epoch: epoch)
            )
            try Census.apply(page: page, to: tx)
        }

        let receipt = try await destination.sink.send(fileHandle: payloadURL.path, idempotencyKey: batchID)
        let recordCount = page.samples.count + page.tombstones.count
        var tally = RunTally(
            read: recordCount,
            committed: recordCount,
            acked: receipt.accepted,
            unconfirmed: receipt.unconfirmed,
            ackEvidenceStatusOnly: receipt.statusOnly
        )
        if receipt.accepted < recordCount, receipt.unconfirmed == 0 {
            tally.partialCause = "receipt_short"
        }
        let outcome = RunOutcome.derive(from: tally)
        try await record(outcome: outcome, tally: tally, receipt: receipt)
        return outcome
    }

    private func record(outcome: RunOutcome, tally: RunTally, receipt: DeliveryReceipt?) async throws {
        try await store.transact { tx in
            if let receipt {
                try tx.recordDelivery(receipt)
            }
            try tx.appendJournal(
                RunEvent(
                    runID: RunID(rawValue: "run-\(metric.rawValue)"),
                    outcomeKind: outcome.kind.rawValue,
                    detail: outcome.partialCause ?? ""
                )
            )
            try tx.appendLedger(
                EgressEntry(
                    destination: destinationName,
                    sampleCount: tally.acked,
                    outcomeKind: outcome.kind.rawValue
                )
            )
        }
    }
}

enum Census {
    static func apply(page: SamplePage, to tx: any StateTransaction) throws {
        var grouped: [String: [String]] = [:]
        for sample in page.samples {
            let day = String(sample.start.prefix(10))
            grouped[day, default: []].append(sample.key.uuid)
        }
        for (day, uuids) in grouped {
            let digest = digestUUIDs(uuids)
            try tx.upsertCensus(
                CensusRow(
                    metric: page.metric,
                    day: day,
                    sampleCount: uuids.count,
                    digest: digest
                )
            )
            try tx.markDirty(metric: page.metric, day: day)
        }
    }

    static func digestUUIDs(_ uuids: [String]) -> String {
        var hash: UInt64 = 5381
        for byte in uuids.sorted().joined(separator: ",").utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }
}
