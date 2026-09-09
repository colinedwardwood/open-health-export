import CoreDomain
import CoreTemporal
import DestinationTrust
import EnginePorts
import FileWriteKit
import Foundation
import RunJournal
import Watchdog
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
    public var observations: (any DayObservationSource)?
    public var trigger: RunTrigger
    public var snapshotURL: URL?
    public var externalStatusURL: URL?
    public var ledgerHeadSeal: (any LedgerHeadSeal)?
    public var ledgerSealURL: URL?
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
        observations: (any DayObservationSource)? = nil,
        trigger: RunTrigger = .manual,
        snapshotURL: URL? = nil,
        externalStatusURL: URL? = nil,
        ledgerHeadSeal: (any LedgerHeadSeal)? = nil,
        ledgerSealURL: URL? = nil
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
        self.observations = observations
        self.trigger = trigger
        self.snapshotURL = snapshotURL
        self.externalStatusURL = externalStatusURL
        self.ledgerHeadSeal = ledgerHeadSeal
        self.ledgerSealURL = ledgerSealURL
    }

    public func run() async throws -> RunOutcome {
        let typeStatus = try await store.transact {
            try $0.loadTypeStatus(metric: metric)
        }
        if let typeStatus, typeStatus.disabled {
            let tally = RunTally(
                failed: 1,
                terminalError: .internalFault,
                partialCause: "types_purged"
            )
            let outcome = RunOutcome.derive(from: tally)
            try await record(outcome: outcome, tally: tally, receipt: nil)
            return outcome
        }
        let effectiveEpoch = max(epoch, typeStatus?.generation ?? epoch)
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
        let page: SamplePage
        do {
            page = try await source.page(metric: metric, afterAnchor: prior?.anchorBlob)
        } catch {
            let errorClass = (error as? DestinationSendError)?.errorClass ?? .internalFault
            let tally = RunTally(
                failed: 1,
                terminalError: errorClass,
                partialCause: errorClass.rawValue
            )
            let outcome = RunOutcome.derive(from: tally)
            try await record(outcome: outcome, tally: tally, receipt: nil)
            if errorClass == .deviceLocked {
                return outcome
            }
            throw error
        }
        #if DEBUG
        try faults.hit(.afterRead)
        #endif
        let aggregates = try await drainPlans(for: page)
        if !page.hasRecords, aggregates.isEmpty {
            let outcome = RunOutcome.derive(from: RunTally(nothingDue: true))
            try await record(outcome: outcome, tally: RunTally(nothingDue: true), receipt: nil)
            return outcome
        }

        let batchID = NativeWire.batchID(
            metric: metric,
            anchorBlob: page.anchorBlob,
            aggregateVersions: aggregates.map {
                "\($0.record.bucketKey)#\($0.record.emitSeq)"
            }
        )
        var wireEnvelope = envelope
        wireEnvelope.completeThrough = page.observedThrough.ISO8601Format()
        if wireEnvelope.tzDatabaseVersion == nil,
           temporal.tzDatabaseVersion != "unknown",
           !temporal.tzDatabaseVersion.isEmpty
        {
            wireEnvelope.tzDatabaseVersion = temporal.tzDatabaseVersion
        }
        let payload = try NativeWire.encode(
            samples: page.samples,
            categories: page.categories,
            correlations: page.correlations,
            workouts: page.workouts,
            minds: page.minds,
            electrocardiograms: page.electrocardiograms,
            audiograms: page.audiograms,
            medicationDoses: page.medicationDoses,
            series: page.series,
            tombstones: page.tombstones,
            aggregates: aggregates.map(\.record),
            metric: metric,
            batchID: batchID,
            envelope: wireEnvelope
        )
        #if DEBUG
        try faults.hit(.afterTransform)
        #endif
        let payloadURL = scratchDirectory.appendingPathComponent(
            NativeWire.outputFileName(batchID: batchID, demo: envelope.demo)
        )
        try FileWriteKit.writeAtomically(payload, to: payloadURL)

        let recordCount = page.censusKeys.count + page.tombstones.count + aggregates.count
        var rangeDays = page.censusKeys.map(\.day)
        rangeDays.append(
            contentsOf: aggregates.map { String($0.record.bucketStart.prefix(10)) }
        )
        let tombstoneDays = try await store.transact { tx in
            try page.tombstones.compactMap {
                try tx.loadEmittedIndex(uuid: $0.key.uuid)?.day
            }
        }
        rangeDays.append(contentsOf: tombstoneDays)
        let fallbackDay = String(page.observedThrough.ISO8601Format().prefix(10))
        let pending = PendingBatch(
            id: batchID,
            payloadURL: payloadURL.path,
            expectedRecords: recordCount,
            byteCount: payload.count,
            metric: metric,
            createdAtEpoch: clock.now().timeIntervalSince1970,
            rangeStartDay: rangeDays.min() ?? fallbackDay,
            rangeEndDay: rangeDays.max() ?? fallbackDay
        )
        let victims = try await store.transact { tx in
            let evicted = try QueueAdmission.makeRoom(for: pending.byteCount, on: tx)
            try tx.commitBatch(
                pending,
                advancing: CursorAdvance(
                    page: page,
                    epoch: effectiveEpoch,
                    tzDatabaseVersion: temporal.tzDatabaseVersion
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
        let receipt: DeliveryReceipt
        do {
            #if DEBUG
            receipt = try await DeliveryExecutor.send(
                batch: pending,
                destination: destination,
                destinationName: destinationName,
                store: store,
                faults: faults,
                clock: clock
            )
            #else
            receipt = try await DeliveryExecutor.send(
                batch: pending,
                destination: destination,
                destinationName: destinationName,
                store: store,
                clock: clock
            )
            #endif
        } catch let error as DestinationSendError {
            let tally = RunTally(
                read: recordCount,
                committed: recordCount,
                failed: 1,
                terminalError: error.errorClass,
                partialCause: error.errorClass.rawValue
            )
            let outcome = RunOutcome.derive(from: tally)
            try await record(outcome: outcome, tally: tally, receipt: nil)
            return outcome
        }
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
        days.formUnion(page.categories.map { String($0.start.prefix(10)) })
        days.formUnion(page.censusKeys.map(\.day))
        let persistedDays = try await store.transact { tx -> Set<String> in
            var found: Set<String> = []
            found.formUnion(try tx.dirtyDays(metric: metric))
            for tomb in page.tombstones {
                if let row = try tx.loadEmittedIndex(uuid: tomb.key.uuid) {
                    found.insert(row.day)
                }
            }
            return found
        }
        days.formUnion(persistedDays)
        var aggregateSamples = page.samples
        if let observations {
            var byUUID = Dictionary(uniqueKeysWithValues: page.samples.map { ($0.key.uuid, $0) })
            for day in days {
                for sample in try await observations.samples(metric: metric, day: day) {
                    byUUID[sample.key.uuid] = sample
                }
            }
            aggregateSamples = Array(byUUID.values)
        }
        return try await AggregateResolver.plans(
            metric: metric,
            days: days,
            samples: aggregateSamples,
            statistics: statistics,
            store: store,
            context: temporal,
            computedAt: envelope.emittedAt,
            observedAt: envelope.observedAt,
            now: clock.now()
        )
    }

    private func record(outcome: RunOutcome, tally: RunTally, receipt: DeliveryReceipt?) async throws {
        let nowEpoch = clock.now().timeIntervalSince1970
        try await store.transact { tx in
            if let receipt {
                try tx.recordDelivery(receipt)
            }
            try tx.appendJournal(
                RunEvent(
                    runID: RunID(rawValue: "run-\(metric.rawValue)"),
                    outcomeKind: outcome.kind.rawValue,
                    detail: envelope.demo
                        ? "demo"
                        : (outcome.partialCause ?? ""),
                    trigger: trigger,
                    samplesRead: tally.read,
                    samplesCommitted: tally.committed,
                    samplesAcked: tally.acked,
                    wallTimeEpoch: nowEpoch,
                    errorClass: tally.terminalError == .none
                        ? nil
                        : tally.terminalError.rawValue
                )
            )
            try tx.appendLedger(
                EgressEntry(
                    destination: destinationName,
                    sampleCount: tally.committed,
                    outcomeKind: envelope.demo
                        ? "run:\(outcome.kind.rawValue):demo"
                        : "run:\(outcome.kind.rawValue)",
                    wallTimeEpoch: nowEpoch
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
                destinationLabel: prior?.destinationLabel ?? destinationName,
                enabled: true,
                lastOutcome: outcome.kind.rawValue,
                lastSuccessEpoch: succeeded ? now : prior?.lastSuccessEpoch,
                lastConfirmedAckEpoch:
                    outcome.ackEvidence == .receiptFull ? now : prior?.lastConfirmedAckEpoch,
                attribution: ExternalStatusRecord.attribution(for: trigger),
                attributionConfidence: "evidenced",
                errorClass: tally.terminalError.rawValue,
                staleThresholdSeconds: prior?.staleThresholdSeconds,
                overdueThresholdSeconds: prior?.overdueThresholdSeconds,
                nextAttemptEarliestEpoch: prior?.nextAttemptEarliestEpoch,
                nextAttemptLatestEpoch: prior?.nextAttemptLatestEpoch,
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
