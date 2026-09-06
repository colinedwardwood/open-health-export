import CoreDomain
import CoreTemporal
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
    public var clock: any Clock
    public var temporal: TemporalContext
    public var statistics: (any StatisticsSource)?
    public var trigger: RunTrigger
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
        envelope: WireEnvelope,
        clock: any Clock = SystemClock(),
        temporal: TemporalContext = .utc,
        statistics: (any StatisticsSource)? = nil,
        trigger: RunTrigger = .manual
    ) {
        self.source = source
        self.destination = destination
        self.store = store
        self.metric = metric
        self.epoch = epoch
        self.scratchDirectory = scratchDirectory
        self.destinationName = destinationName
        self.envelope = envelope
        self.clock = clock
        self.temporal = temporal
        self.statistics = statistics
        self.trigger = trigger
    }

    public func run() async throws -> RunOutcome {
        if let status = try await store.transact({ try $0.loadTypeStatus(metric: metric) }),
           status.disabled {
            let tally = RunTally(
                failed: 1,
                terminalError: .internalFault,
                partialCause: "types_purged"
            )
            let outcome = RunOutcome.derive(from: tally)
            try await record(outcome: outcome, tally: tally, receipt: nil)
            return outcome
        }
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

        let aggregates = try await drainPlans(for: page)
        let batchID = NativeWire.batchID(metric: metric, anchorBlob: page.anchorBlob)
        let payload = try NativeWire.encode(
            samples: page.samples,
            tombstones: page.tombstones,
            aggregates: aggregates.map(\.record),
            metric: metric,
            batchID: batchID,
            envelope: envelope
        )
        #if DEBUG
        try faults.hit(.afterTransform)
        #endif
        let payloadURL = scratchDirectory.appendingPathComponent("\(batchID.rawValue).ndjson")
        try FileWriteKit.writeAtomically(payload, to: payloadURL)

        let recordCount = page.samples.count + page.tombstones.count + aggregates.count
        let pending = PendingBatch(
            id: batchID,
            payloadURL: payloadURL.path,
            expectedRecords: recordCount,
            byteCount: payload.count,
            metric: metric
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
            try EmittedIndex.record(page: page, batchID: pending.id, on: tx)
            for plan in aggregates {
                try tx.upsertAggregateEmitSeq(
                    bucketKey: plan.record.bucketKey,
                    emitSeq: plan.record.emitSeq
                )
                try tx.clearDirty(metric: metric, day: plan.day)
            }
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

    private func drainPlans(for page: SamplePage) async throws -> [AggregateDayPlan] {
        var days = Set(page.samples.map { String($0.start.prefix(10)) })
        let tombDays = try await store.transact { tx -> Set<String> in
            var found: Set<String> = []
            for tomb in page.tombstones {
                if let row = try tx.loadEmittedIndex(uuid: tomb.key.uuid) {
                    found.insert(row.day)
                }
            }
            return found
        }
        days.formUnion(tombDays)
        return try await AggregateResolver.plans(
            metric: metric,
            days: days,
            samples: page.samples,
            statistics: statistics,
            store: store,
            context: temporal,
            computedAt: envelope.emittedAt,
            observedAt: envelope.observedAt,
            now: clock.now()
        )
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
                    detail: outcome.partialCause ?? "",
                    trigger: trigger,
                    samplesRead: tally.read,
                    samplesCommitted: tally.committed,
                    samplesAcked: tally.acked
                )
            )
        }
    }
}
