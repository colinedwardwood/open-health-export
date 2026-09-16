// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CoreTemporal
import DestinationTrust
import EnginePorts
import MetricCatalog
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
    public var freshnessCadenceSeconds: TimeInterval
    public var deferForLowPower: Bool
    /// AR-02 for the repair path. A day read once repairs every sink that was owed
    /// it; sweeping per sink would read the same history N times and let the sinks
    /// disagree about which observation they were repaired from.
    public var destinations: [RunDestination]
    /// Set to read what each sink did with the repair, so a caller can report a
    /// destination's status as its own rather than as the combined result.
    public var rowCollector: DestinationRowCollector?

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
        scope: DestinationExportScope? = nil,
        freshnessCadenceSeconds: TimeInterval = FreshnessTarget.defaultCadenceSeconds,
        deferForLowPower: Bool = false,
        destinations: [RunDestination] = []
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
        self.freshnessCadenceSeconds = freshnessCadenceSeconds
        self.deferForLowPower = deferForLowPower
        self.destinations = destinations.isEmpty
            ? [
                RunDestination(
                    id: destinationName,
                    destination: destination,
                    scope: scope,
                    snapshotURL: snapshotURL
                ),
            ]
            : destinations
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
        if deferForLowPower {
            let tally = RunTally(
                failed: 1,
                terminalError: .lowPowerMode,
                partialCause: ErrorClass.lowPowerMode.rawValue
            )
            let outcome = RunOutcome.derive(from: tally)
            try await record(outcome: outcome, tally: tally, receipt: nil)
            return outcome
        }
        if MetricCatalog.isCharacteristic(metric) {
            let tally = RunTally(nothingDue: true)
            let outcome = RunOutcome.derive(from: tally)
            try await record(outcome: outcome, tally: tally, receipt: nil)
            return outcome
        }
        let owed = try owedDestinations()
        if owed.isEmpty {
            let tally = RunTally(nothingDue: true)
            let outcome = RunOutcome.derive(from: tally)
            try await record(outcome: outcome, tally: tally, receipt: nil)
            return outcome
        }
        // The union of what the sinks asked for: one read covers all of them, and
        // each sink's own window is applied again when its payload is projected.
        var permittedDays: [String] = []
        for day in days where owed.contains(where: { permits(day: day, scope: $0.scope) }) {
            permittedDays.append(day)
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
        wire.seq = try await store.transact {
            try $0.reserveBatchSequence(exporterID: envelope.exporterId)
        }
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
        let batchID = NativeWire.mintBatchID(at: clock.now())
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
        let (queued, pinnedBytes) = try await store.transact { tx -> (Int, Int) in
            let batches = try tx.pendingBatches()
            return (
                try tx.queuedBytes(),
                batches.filter { $0.evictionClass == .pinned }
                    .reduce(0) { $0 + $1.byteCount }
            )
        }
        let pending = PendingBatch(
            id: batchID,
            payloadURL: payloadURL.path,
            expectedRecords: recordCount,
            byteCount: payload.count,
            metric: metric,
            createdAtEpoch: clock.now().timeIntervalSince1970,
            rangeStartDay: days.first,
            rangeEndDay: days.last,
            evictionClass: QueueAdmission.evictionClass(
                reason: reason,
                pinnedBytes: pinnedBytes,
                incomingBytes: payload.count
            )
        )
        // A parked sink keeps its obligation and is retried by the drain, so it no
        // longer cancels the repair the other sinks are owed.
        var attempting: [RunDestination] = []
        for dest in owed where dest.attemptNow {
            let breaker = try await store.transact { tx in
                RetryPolicy.age(
                    snapshot: try DestinationBreaker.load(from: tx, destinationID: dest.id),
                    now: clock.now()
                )
            }
            if CatchUpAdmission.allows(breaker: breaker) {
                attempting.append(dest)
            }
        }
        if attempting.isEmpty, owed.allSatisfy(\.attemptNow) {
            try? FileManager.default.removeItem(at: payloadURL)
            let tally = RunTally(
                read: recordCount,
                acked: 0,
                partialCause: CatchUpAdmission.destinationParkedJournalDetail
            )
            let outcome = RunOutcome.derive(from: tally)
            try await record(outcome: outcome, tally: tally, receipt: nil)
            return outcome
        }
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
        let extraStarts = aggregates.map(\.record.bucketStart)
        let expectedByDestination = Dictionary(
            uniqueKeysWithValues: owed.map {
                (
                    $0.id,
                    FanoutPayload.expectedRecordCount(
                        page: page,
                        extraStarts: extraStarts,
                        metric: metric,
                        scope: $0.scope
                    )
                )
            }
        )
        let victims = try await store.transact { tx in
            let evicted = try QueueAdmission.makeRoom(for: pending.byteCount, on: tx)
            try tx.enqueueFanout(
                pending,
                destinations: try owed.map {
                    try FanoutObligation.destination(
                        id: $0.id,
                        metric: metric,
                        expectedRecords: expectedByDestination[$0.id] ?? pending.expectedRecords,
                        scope: $0.scope
                    )
                }
            )
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
        var accepted = 0
        var unconfirmed = 0
        var statusOnly = false
        var failed = 0
        var terminalError = ErrorClass.none
        var partialCause: String?
        var receipts: [(RunDestination, DeliveryReceipt)] = []
        var expectedOfAttempts = 0
        var firstError: DestinationSendError?
        var failures: [String: DestinationSendError] = [:]
        for dest in attempting {
            let expected = expectedByDestination[dest.id] ?? recordCount
            expectedOfAttempts += expected
            do {
                let receipt = try await deliver(
                    pending: pending,
                    dest: dest,
                    expectedRecords: expected
                )
                receipts.append((dest, receipt))
                accepted += receipt.accepted
                unconfirmed += receipt.unconfirmed
                statusOnly = statusOnly || receipt.statusOnly
            } catch let error as DestinationSendError {
                failed += 1
                terminalError = error.errorClass
                partialCause = error.errorClass.rawValue
                firstError = firstError ?? error
                failures[dest.id] = error
            }
        }
        // A repair nobody could attempt in this context is not a repair that
        // happened: the obligations stay, and the run says so.
        let attemptedExpected = attempting.isEmpty ? recordCount : expectedOfAttempts
        var tally = RunTally(
            read: attemptedExpected,
            committed: recordCount,
            acked: attempting.isEmpty ? recordCount : accepted,
            unconfirmed: unconfirmed,
            failed: failed,
            terminalError: terminalError,
            ackEvidenceStatusOnly: statusOnly
        )
        tally.partialCause = partialCause
        if failed == 0, accepted < attemptedExpected, unconfirmed == 0, !attempting.isEmpty {
            tally.partialCause = "receipt_short"
        }
        let outcome = RunOutcome.derive(from: tally)
        try await record(
            outcome: outcome,
            tally: tally,
            receipts: receipts,
            owed: owed,
            failures: failures,
            expectedByDestination: expectedByDestination
        )
        if let firstError, receipts.isEmpty, attempting.count == 1 {
            // A single-sink sweep still surfaces its transport failure to the caller
            // exactly as it always has.
            throw firstError
        }
        return outcome
    }

    /// Which sinks this sweep repairs. A lone sink keeps the old behaviour of
    /// refusing loudly when the metric is outside its scope; among several, a sink
    /// that never asked for this metric is simply not owed the repair.
    private func owedDestinations() throws -> [RunDestination] {
        let allowed = destinations.filter { $0.role.allows(trigger) }
        var matching: [RunDestination] = []
        var lastScopeError: Error?
        for dest in allowed {
            guard let scope = dest.scope else {
                matching.append(dest)
                continue
            }
            do {
                try ExportScopeGate.require(metric: metric, scope: scope)
                matching.append(dest)
            } catch {
                lastScopeError = error
            }
        }
        if matching.isEmpty, destinations.count == 1, let error = lastScopeError {
            throw error
        }
        return matching
    }

    /// What each sink did with this repair. A sink that was attempted and failed is
    /// reported as failed against itself; only a sink this context could not attempt
    /// is still owed the repair.
    private func destinationRows(
        owed: [RunDestination],
        receipts: [(RunDestination, DeliveryReceipt)],
        failures: [String: DestinationSendError],
        expectedByDestination: [String: Int],
        fallbackExpected: Int
    ) -> [DestinationRunRow] {
        let accepted = Dictionary(
            receipts.map { ($0.0.id, $0.1) },
            uniquingKeysWith: { _, latest in latest }
        )
        return owed.map { dest in
            let expected = expectedByDestination[dest.id] ?? fallbackExpected
            if let error = failures[dest.id] {
                return DestinationRunRow(
                    destinationID: dest.id,
                    outcomeKind: RunOutcome.Kind.failed.rawValue,
                    detail: error.errorClass.rawValue,
                    expectedRecords: expected,
                    acceptedRecords: 0,
                    errorClass: error.errorClass.rawValue
                )
            }
            guard let receipt = accepted[dest.id] else {
                return DestinationRunRow(
                    destinationID: dest.id,
                    outcomeKind: RunEvent.queuedOutcomeKind,
                    detail: "",
                    expectedRecords: expected,
                    acceptedRecords: 0,
                    errorClass: nil
                )
            }
            let own = RunOutcome.derive(
                from: RunTally(
                    read: expected,
                    committed: expected,
                    acked: receipt.accepted,
                    unconfirmed: receipt.unconfirmed,
                    ackEvidenceStatusOnly: receipt.statusOnly
                )
            )
            return DestinationRunRow(
                destinationID: dest.id,
                outcomeKind: own.kind.rawValue,
                detail: own.partialCause ?? "",
                expectedRecords: expected,
                acceptedRecords: receipt.accepted,
                errorClass: nil
            )
        }
    }

    private func permits(day: String, scope: DestinationExportScope?) -> Bool {
        guard let scope else { return true }
        do {
            try ExportScopeGate.require(
                metric: metric,
                rangeStartDay: day,
                rangeEndDay: day,
                scope: scope
            )
            return true
        } catch {
            return false
        }
    }

    private func deliver(
        pending: PendingBatch,
        dest: RunDestination,
        expectedRecords: Int
    ) async throws -> DeliveryReceipt {
        if expectedRecords == 0 {
            return DeliveryReceipt(
                batchID: pending.id,
                accepted: 0,
                statusOnly: false
            )
        }
        var attempt = pending
        let url = try FanoutPayload.attemptURL(
            canonical: pending,
            destinationID: dest.id,
            expectedRecords: expectedRecords,
            scope: dest.scope,
            scratchDirectory: scratchDirectory
        )
        attempt.payloadURL = url.path
        attempt.expectedRecords = expectedRecords
        defer {
            if url.path != pending.payloadURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        return try await DeliveryExecutor.send(
            batch: attempt,
            destination: dest.destination,
            destinationName: dest.id,
            store: store,
            clock: clock,
            scope: dest.scope,
            skipRangeGate: url.path != pending.payloadURL
        )
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

    private func record(
        outcome: RunOutcome,
        tally: RunTally,
        receipt: DeliveryReceipt?
    ) async throws {
        try await record(
            outcome: outcome,
            tally: tally,
            receipts: receipt.map { [(destinations[0], $0)] } ?? []
        )
    }

    private func record(
        outcome: RunOutcome,
        tally: RunTally,
        receipts: [(RunDestination, DeliveryReceipt)],
        owed: [RunDestination] = [],
        failures: [String: DestinationSendError] = [:],
        expectedByDestination: [String: Int] = [:]
    ) async throws {
        let nowEpoch = clock.now().timeIntervalSince1970
        let parentRunID = RunID(rawValue: "reconcile-\(metric.rawValue)")
        let rows = destinationRows(
            owed: owed.isEmpty ? destinations : owed,
            receipts: receipts,
            failures: failures,
            expectedByDestination: expectedByDestination,
            fallbackExpected: tally.committed
        )
        await rowCollector?.record(rows)
        var settlements: [DeliverySettlement] = []
        try await store.transact { tx in
            for (dest, receipt) in receipts {
                settlements.append(
                    try FanoutObligation.settle(
                        receipt: receipt,
                        destinationID: dest.id,
                        on: tx
                    )
                )
            }
            try tx.appendJournal(
                RunEvent(
                    runID: parentRunID,
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
            // A repair that fanned out says what each sink did with it, under one
            // parent row. A lone sink keeps the flat single row it always had.
            if rows.count > 1 {
                for row in rows {
                    try tx.appendJournal(
                        RunEvent(
                            runID: RunID(rawValue: "\(parentRunID.rawValue)-\(row.destinationID)"),
                            outcomeKind: row.outcomeKind,
                            detail: row.detail,
                            trigger: trigger,
                            samplesRead: row.expectedRecords,
                            samplesCommitted: row.expectedRecords,
                            samplesAcked: row.acceptedRecords,
                            wallTimeEpoch: nowEpoch,
                            errorClass: row.errorClass,
                            facts: RunHistoryFacts(
                                destinationID: row.destinationID,
                                metric: metric.rawValue,
                                parentRunID: parentRunID.rawValue
                            )
                        )
                    )
                }
            }
            for dest in destinations {
                try tx.appendLedger(
                    EgressEntry(
                        destination: dest.id,
                        sampleCount: tally.committed,
                        outcomeKind: "run:\(outcome.kind.rawValue)",
                        wallTimeEpoch: nowEpoch
                    )
                )
            }
        }
        for settlement in settlements {
            FanoutObligation.unlink(settlement)
        }
        let queued = try await store.transact { try $0.queuedBytes() }
        try writeSnapshot(
            outcome: outcome,
            tally: tally,
            queueOccupancy: QueueRed.occupancy(queuedBytes: queued).snapshotToken
        )
        try writeExternalStatus(outcome: outcome, tally: tally)
        try await writeLedgerHeadSeal()
    }

    private func writeSnapshot(
        outcome: RunOutcome,
        tally: RunTally,
        queueOccupancy: String
    ) throws {
        guard let snapshotURL else { return }
        let now = clock.now().timeIntervalSince1970
        let prior = try? DestinationSnapshotFile.read(from: snapshotURL)
        let succeeded = outcome.kind == .success || outcome.kind == .successNothingDue
        let thresholds = FreshnessTarget.snapshotThresholds(
            estimates: prior?.freshnessEstimates ?? [:],
            cadenceSeconds: freshnessCadenceSeconds
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
                freshnessEstimates: prior?.freshnessEstimates ?? [:],
                queueOccupancy: queueOccupancy,
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
