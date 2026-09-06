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
    #if DEBUG
    public var faults: any ExportFaultInjector = NoExportFaults()
    #endif

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
        let prior: CursorSnapshot?
        do {
            prior = try await store.transact { tx in
                try tx.loadCursor(metric: metric)
            }
        } catch let error as CheckpointError {
            let tally = RunTally(failed: 1, terminalError: .internalFault, partialCause: "anchor_undecodable")
            let outcome = RunOutcome.derive(from: tally)
            try await record(outcome: outcome, tally: tally, receipt: nil)
            throw error
        }
        let page = try await source.page(metric: metric, afterAnchor: prior?.anchorBlob)
        #if DEBUG
        try faults.hit(.afterRead)
        #endif
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
        #if DEBUG
        try faults.hit(.afterTransform)
        #endif
        let payloadURL = scratchDirectory.appendingPathComponent("\(batchID.rawValue).ndjson")
        try FileWriteKit.writeAtomically(payload, to: payloadURL)

        let recordCount = page.samples.count + page.tombstones.count
        let pending = PendingBatch(
            id: batchID,
            payloadURL: payloadURL.path,
            expectedRecords: recordCount,
            byteCount: payload.count
        )
        let victims = try await store.transact { tx in
            let evicted = try QueueAdmission.makeRoom(for: pending.byteCount, on: tx)
            try tx.commitBatch(
                pending,
                advancing: CursorAdvance(
                    page: page,
                    epoch: epoch,
                    tzDatabaseVersion: envelope.producerVersion
                )
            )
            try Census.apply(page: page, to: tx)
            #if DEBUG
            try faults.hit(.duringAnchorPersist)
            #endif
            return evicted
        }
        for victim in victims {
            try? FileManager.default.removeItem(atPath: victim.payloadURL)
        }
        #if DEBUG
        try faults.hit(.afterEnqueueBeforeDestinationWrite)
        #endif
        #if DEBUG
        let receipt = try await DeliveryExecutor.send(
            batch: pending,
            destination: destination,
            destinationName: destinationName,
            store: store,
            faults: faults
        )
        #else
        let receipt = try await DeliveryExecutor.send(
            batch: pending,
            destination: destination,
            destinationName: destinationName,
            store: store
        )
        #endif
        #if DEBUG
        try faults.hit(.afterAckBeforeRelease)
        #endif
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
