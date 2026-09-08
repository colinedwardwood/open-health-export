import CoreDomain
import CoreTemporal
import DestinationTrust
import EnginePorts
import FileWriteKit
import Foundation
import RunJournal
import Watchdog
import WireFormat

/// R-08 trailing-window apply. Plans from stored census vs date-ranged observations, then
/// enqueues a repair batch without advancing the HealthKit cursor.
public struct ReconcileSweep: Sendable {
    public var observations: any DayObservationSource
    public var destination: VerifiedDestination
    public var store: any StateStore
    public var metric: MetricID
    public var scratchDirectory: URL
    public var destinationName: String
    public var envelope: WireEnvelope
    public var clock: any Clock
    public var temporal: TemporalContext
    public var statistics: (any StatisticsSource)?
    public var trigger: RunTrigger
    public var snapshotURL: URL?
    public var externalStatusURL: URL?
    public var ledgerHeadSeal: (any LedgerHeadSeal)?
    public var ledgerSealURL: URL?

    public init(
        observations: any DayObservationSource,
        destination: VerifiedDestination,
        store: any StateStore,
        metric: MetricID,
        scratchDirectory: URL,
        destinationName: String = "local-file",
        envelope: WireEnvelope,
        clock: any Clock = SystemClock(),
        temporal: TemporalContext = .utc,
        statistics: (any StatisticsSource)? = nil,
        trigger: RunTrigger = .manual,
        snapshotURL: URL? = nil,
        externalStatusURL: URL? = nil,
        ledgerHeadSeal: (any LedgerHeadSeal)? = nil,
        ledgerSealURL: URL? = nil
    ) {
        self.observations = observations
        self.destination = destination
        self.store = store
        self.metric = metric
        self.scratchDirectory = scratchDirectory
        self.destinationName = destinationName
        self.envelope = envelope
        self.clock = clock
        self.temporal = temporal
        self.statistics = statistics
        self.trigger = trigger
        self.snapshotURL = snapshotURL
        self.externalStatusURL = externalStatusURL
        self.ledgerHeadSeal = ledgerHeadSeal
        self.ledgerSealURL = ledgerSealURL
    }

    public func run(throughDay: String) async throws -> RunOutcome {
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

        let days = ReconcilePlanner.trailingDays(throughDay: throughDay)
        var samples: [SampleRecord] = []
        var tombstones: [TombstoneRecord] = []
        for day in days {
            let observed = try await observations.samples(metric: metric, day: day)
            let plan = try await store.transact { tx in
                ReconcilePlanner.planDay(
                    metric: metric,
                    day: day,
                    stored: try tx.loadCensus(metric: metric, day: day),
                    indexed: try tx.loadEmittedIndex(metric: metric, day: day),
                    observed: observed
                )
            }
            for repair in plan.repairs {
                switch repair {
                case .reemitDay:
                    samples.append(contentsOf: observed)
                case .emitAbsenceTombstones(let tombs):
                    tombstones.append(contentsOf: tombs)
                }
            }
        }

        if samples.isEmpty, tombstones.isEmpty {
            let tally = RunTally(nothingDue: true)
            let outcome = RunOutcome.derive(from: tally)
            try await record(outcome: outcome, tally: tally, receipt: nil)
            return outcome
        }

        let page = SamplePage(
            samples: samples,
            tombstones: tombstones,
            metric: metric,
            anchorBlob: Data("reconcile:\(throughDay)".utf8),
            observedThrough: clock.now()
        )
        var wire = envelope
        wire.reason = "reconcile"
        let aggregates = try await drainPlans(for: page)
        let batchID = NativeWire.batchID(metric: metric, anchorBlob: page.anchorBlob)
        let payload = try NativeWire.encode(
            samples: page.samples,
            tombstones: page.tombstones,
            aggregates: aggregates.map(\.record),
            metric: metric,
            batchID: batchID,
            envelope: wire
        )
        let payloadURL = scratchDirectory.appendingPathComponent("\(batchID.rawValue).ndjson")
        try FileWriteKit.writeAtomically(payload, to: payloadURL)
        let recordCount = page.samples.count + page.tombstones.count + aggregates.count
        let pending = PendingBatch(
            id: batchID,
            payloadURL: payloadURL.path,
            expectedRecords: recordCount,
            byteCount: payload.count,
            metric: metric,
            createdAtEpoch: clock.now().timeIntervalSince1970
        )
        let victims = try await store.transact { tx in
            let evicted = try QueueAdmission.makeRoom(for: pending.byteCount, on: tx)
            try tx.enqueuePending(pending)
            try Census.apply(page: page, to: tx)
            try EmittedIndex.record(page: page, batchID: pending.id, on: tx)
            for plan in aggregates {
                try tx.upsertAggregateEmitSeq(
                    bucketKey: plan.record.bucketKey,
                    emitSeq: plan.record.emitSeq
                )
                try tx.clearDirty(metric: metric, day: plan.day)
            }
            return evicted
        }
        for victim in victims {
            try? FileManager.default.removeItem(atPath: victim.payloadURL)
        }
        let receipt = try await DeliveryExecutor.send(
            batch: pending,
            destination: destination,
            destinationName: destinationName,
            store: store,
            clock: clock
        )
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
                    runID: RunID(rawValue: "reconcile-\(metric.rawValue)"),
                    outcomeKind: outcome.kind.rawValue,
                    detail: outcome.partialCause ?? "",
                    trigger: trigger,
                    samplesRead: tally.read,
                    samplesCommitted: tally.committed,
                    samplesAcked: tally.acked
                )
            )
            try tx.appendLedger(
                EgressEntry(
                    destination: destinationName,
                    sampleCount: tally.committed,
                    outcomeKind: "run:\(outcome.kind.rawValue)",
                    wallTimeEpoch: clock.now().timeIntervalSince1970
                )
            )
        }
        try writeSnapshot(outcome: outcome, tally: tally)
        try writeExternalStatus(outcome: outcome, tally: tally)
        try await writeLedgerHeadSeal()
    }

    private func writeSnapshot(outcome: RunOutcome, tally: RunTally) throws {
        guard let snapshotURL else { return }
        let now = clock.now().timeIntervalSince1970
        let prior = try? DestinationSnapshotFile.read(from: snapshotURL)
        let succeeded = outcome.kind == .success || outcome.kind == .successNothingDue
        try DestinationSnapshotFile.write(
            DestinationStatusSnapshot(
                destinationID: destinationName,
                enabled: true,
                lastOutcome: outcome.kind.rawValue,
                lastSuccessEpoch: succeeded ? now : prior?.lastSuccessEpoch,
                lastConfirmedAckEpoch:
                    outcome.ackEvidence == .receiptFull ? now : prior?.lastConfirmedAckEpoch,
                attribution: ExternalStatusRecord.attribution(for: trigger),
                attributionConfidence: "evidenced",
                errorClass: tally.terminalError.rawValue,
                unacknowledgedSecurityEventCount:
                    prior?.unacknowledgedSecurityEventCount ?? 0,
                writtenAtEpoch: now
            ),
            to: snapshotURL
        )
    }

    private func writeLedgerHeadSeal() async throws {
        guard let ledgerHeadSeal, let ledgerSealURL else { return }
        let entries = try await store.transact { tx in
            try tx.loadLedger()
        }
        try await LedgerHeadSealRecordFile.update(
            entries: entries,
            seal: ledgerHeadSeal,
            sealedAtEpoch: clock.now().timeIntervalSince1970,
            url: ledgerSealURL
        )
    }

    private func writeExternalStatus(outcome: RunOutcome, tally: RunTally) throws {
        guard let externalStatusURL else { return }
        let prior = try? ExternalStatusRecordFile.read(from: externalStatusURL)
        let snapshot = snapshotURL.flatMap { try? DestinationSnapshotFile.read(from: $0) }
        let record = ExternalStatusRecord.next(
            prior: prior,
            exporterInstanceID: envelope.exporterId,
            destinationID: destinationName,
            runAt: envelope.emittedAt,
            runAtEpoch: clock.now().timeIntervalSince1970,
            outcome: outcome,
            tally: tally,
            trigger: trigger,
            staleThresholdSeconds: snapshot?.staleThresholdSeconds,
            overdueThresholdSeconds: snapshot?.overdueThresholdSeconds
        )
        try ExternalStatusRecordFile.write(record, to: externalStatusURL)
    }
}
