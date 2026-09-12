// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CoreTemporal
import DestinationTrust
import EnginePorts
import FileWriteKit
import Foundation
import RunJournal
import Watchdog
import WireFormat

public enum ReconcileSweepError: Error, Equatable {
    case fullHistoryRangeUnavailable
    case gapRangeUnavailable
    case gapMetricMismatch
}

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
    public var scope: DestinationExportScope?

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
        ledgerSealURL: URL? = nil,
        scope: DestinationExportScope? = nil
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
        self.scope = scope
    }

    public func run(throughDay: String) async throws -> RunOutcome {
        try await run(
            days: ReconcilePlanner.trailingDays(throughDay: throughDay),
            throughDay: throughDay,
            reason: "reconcile"
        )
    }

    public func runFullHistory(throughDay: String) async throws -> RunOutcome {
        guard let bounded = observations as? any BoundedDayObservationSource else {
            throw ReconcileSweepError.fullHistoryRangeUnavailable
        }
        guard let available = try await bounded.availableDayRange(metric: metric) else {
            return try await run(days: [], throughDay: throughDay, reason: "full_reconcile")
        }
        let endDay = min(available.upperBound, throughDay)
        let days = available.lowerBound <= endDay
            ? try ReconcilePlanner.days(from: available.lowerBound, through: endDay)
            : []
        return try await run(
            days: days,
            throughDay: endDay,
            reason: "full_reconcile"
        )
    }

    /// O-9: sweep every day this metric still has a census row, so an undatable
    /// deletion can be rebuilt from live observations instead of waiting for a
    /// global full reconcile.
    public func runCensusDays(reason: String = DeletionUndatable.token) async throws -> RunOutcome {
        let days = try await store.transact { try $0.loadCensusDays(metric: metric) }
        let throughDay = days.max() ?? String(clock.now().ISO8601Format().prefix(10))
        return try await run(days: days, throughDay: throughDay, reason: reason)
    }

    public func run(gap: GapRecord) async throws -> RunOutcome {
        guard gap.metric == metric else {
            throw ReconcileSweepError.gapMetricMismatch
        }
        guard let startDay = gap.rangeStartDay,
              let endDay = gap.rangeEndDay
        else {
            throw ReconcileSweepError.gapRangeUnavailable
        }
        return try await run(
            days: ReconcilePlanner.days(from: startDay, through: endDay),
            throughDay: endDay,
            reason: "gap_reexport"
        )
    }

    public func runBackfill(
        days: [String],
        mode: BackfillMode
    ) async throws -> RunOutcome {
        try await run(
            days: days,
            throughDay: days.max() ?? String(clock.now().ISO8601Format().prefix(10)),
            reason: "backfill",
            includeRaw: mode == .raw
        )
    }

    private func run(
        days: [String],
        throughDay: String,
        reason: String,
        includeRaw: Bool = true
    ) async throws -> RunOutcome {
        var permittedDays = days
        if let scope {
            try ExportScopeGate.require(metric: metric, scope: scope)
            permittedDays = []
            for day in days {
                do {
                    try ExportScopeGate.require(
                        metric: metric,
                        rangeStartDay: day,
                        rangeEndDay: day,
                        scope: scope
                    )
                    permittedDays.append(day)
                } catch let violation as ExportScopeViolation {
                    switch violation {
                    case .rangeBeforeStart, .rangeAtOrAfterEnd:
                        continue
                    default:
                        throw violation
                    }
                }
            }
        }
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

        var samples: [SampleRecord] = []
        var observedSamples: [SampleRecord] = []
        var tombstones: [TombstoneRecord] = []
        for day in permittedDays {
            let observed = try await observations.samples(metric: metric, day: day)
            observedSamples.append(contentsOf: observed)
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
                    if includeRaw {
                        samples.append(contentsOf: observed)
                    }
                case .emitAbsenceTombstones(let tombs):
                    tombstones.append(contentsOf: tombs)
                }
            }
        }

        let page = SamplePage(
            samples: samples,
            tombstones: tombstones,
            metric: metric,
            anchorBlob: Data(
                "\(reason):\(days.first ?? throughDay):\(throughDay)".utf8
            ),
            observedThrough: clock.now()
        )
        let censusPage = SamplePage(
            samples: observedSamples,
            tombstones: tombstones,
            metric: metric,
            anchorBlob: page.anchorBlob,
            observedThrough: page.observedThrough
        )
        let aggregatePage = includeRaw ? page : censusPage
        let aggregates = try await drainPlans(
            for: aggregatePage,
            forcedDays: includeRaw ? [] : Set(days)
        )
        if !page.hasRecords, aggregates.isEmpty {
            let tally = RunTally(nothingDue: true)
            let outcome = RunOutcome.derive(from: tally)
            try await record(outcome: outcome, tally: tally, receipt: nil)
            return outcome
        }

        var wire = envelope
        wire.reason = reason
        let horizonBound = try await store.transact { tx -> String? in
            let stored = try tx.loadVerifiedThroughDay(metric: metric)
            let horizon = try tx.loadIndexHorizonDay()
            return [stored, horizon].compactMap { $0 }.min()
        }
        if let horizonBound {
            wire.verifiedThrough = EmittedIndexPolicy.verifiedThrough(
                completeThrough: wire.completeThrough,
                horizonDay: horizonBound
            )
        }
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
            createdAtEpoch: clock.now().timeIntervalSince1970,
            rangeStartDay: days.first,
            rangeEndDay: days.last
        )
        let queued = try await store.transact { try $0.queuedBytes() }
        if !CatchUpAdmission.allows(queuedBytes: queued, incomingBytes: pending.byteCount) {
            try? FileManager.default.removeItem(at: payloadURL)
            let tally = RunTally(
                read: recordCount,
                acked: 0,
                partialCause: CatchUpAdmission.parkedJournalDetail
            )
            let outcome = RunOutcome.derive(from: tally)
            try await record(outcome: outcome, tally: tally, receipt: nil)
            return outcome
        }
        let victims = try await store.transact { tx in
            let evicted = try QueueAdmission.makeRoom(for: pending.byteCount, on: tx)
            try tx.enqueuePending(pending)
            try Census.replaceObserved(page: censusPage, days: permittedDays, to: tx)
            try EmittedIndex.record(
                page: page,
                batchID: pending.id,
                on: tx,
                atEpoch: pending.createdAtEpoch ?? 0
            )
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
            clock: clock,
            scope: scope
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

    private func drainPlans(
        for page: SamplePage,
        forcedDays: Set<String> = []
    ) async throws -> [AggregateDayPlan] {
        var days = forcedDays
        days.formUnion(page.samples.map { String($0.start.prefix(10)) })
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
        let nowEpoch = clock.now().timeIntervalSince1970
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
                    outcomeKind: "run:\(outcome.kind.rawValue)",
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
        let thresholds = FreshnessTarget.snapshotThresholds(
            estimates: prior?.freshnessEstimates ?? [:]
        )
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
                staleThresholdSeconds: thresholds.stale,
                overdueThresholdSeconds: thresholds.overdue,
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
