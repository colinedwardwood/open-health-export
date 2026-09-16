// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CoreTemporal
import DestinationTrust
import EnginePorts
import FileWriteKit
import Foundation
import MetricCatalog
import RunJournal
import Watchdog
import WireFormat

public struct RunDestination: Sendable {
    public var id: String
    public var destination: VerifiedDestination
    public var scope: DestinationExportScope?
    public var role: DestinationExportRole
    public var snapshotURL: URL?
    /// False keeps the durable obligation without a transport attempt in this
    /// execution context (background companion delivery).
    public var attemptNow: Bool

    public init(
        id: String,
        destination: VerifiedDestination,
        scope: DestinationExportScope? = nil,
        role: DestinationExportRole = .designated,
        snapshotURL: URL? = nil,
        attemptNow: Bool = true
    ) {
        self.id = id
        self.destination = destination
        self.scope = scope
        self.role = role
        self.snapshotURL = snapshotURL
        self.attemptNow = attemptNow
    }
}

/// What one destination did with a read, for the history row that hangs under it.
public struct DestinationRunRow: Sendable {
    public var destinationID: String
    public var outcomeKind: String
    public var detail: String
    public var expectedRecords: Int
    public var acceptedRecords: Int
    public var errorClass: String?

    /// What one sink did, if this run has anything to say about it. A sink this
    /// trigger could only queue for is absent: nothing was attempted, so its last
    /// result still stands.
    public static func kind(
        for destinationID: String,
        in rows: [DestinationRunRow]
    ) -> RunOutcome.Kind? {
        guard let row = rows.first(where: { $0.destinationID == destinationID })
        else { return nil }
        return RunOutcome.Kind(rawValue: row.outcomeKind)
    }
}

/// One read's result: what the run as a whole did, and what each sink did with it.
///
/// The run's own outcome is the combination across sinks, which is what a caller
/// reports to the person who asked for the export. A destination's *status* is its
/// own row: attributing the combined outcome to every sink told someone their
/// working archive folder had failed because an unrelated server was unreachable.
/// Sinks this trigger could only queue for have no row, because nothing was
/// attempted for them and their last result still stands.
public struct FanoutRunResult: Sendable {
    public let outcome: RunOutcome
    public let destinations: [DestinationRunRow]

    public func kind(for destinationID: String) -> RunOutcome.Kind? {
        DestinationRunRow.kind(for: destinationID, in: destinations)
    }
}

/// Carries the per-destination rows out of a run without changing what the run
/// returns, so every existing caller and every early return stays as it was.
public actor DestinationRowCollector {
    private var stored: [DestinationRunRow] = []

    public init() {}

    func record(_ rows: [DestinationRunRow]) {
        stored = rows
    }

    public func rows() -> [DestinationRunRow] {
        stored
    }
}

public struct ExportRun: Sendable {
    public var source: any SampleSource
    public var destination: VerifiedDestination
    public var destinations: [RunDestination]
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
    public var characteristics: (any CharacteristicSource)?
    public var trigger: RunTrigger
    public var snapshotURL: URL?
    public var externalStatusURL: URL?
    public var ledgerHeadSeal: (any LedgerHeadSeal)?
    public var ledgerSealURL: URL?
    public var scope: DestinationExportScope?
    /// QA-17: the page size above which a delta is treated as a replayed store.
    public var replaySampleLimit: Int
    /// UX-22: C, the owned freshness cadence that drives stale and overdue windows.
    public var freshnessCadenceSeconds: TimeInterval
    public var deferForLowPower: Bool
    /// UX-40 history archive copy. Volume pages skip this so SHA-256 is not re-run
    /// on every bounded ExportRun after the first page of a metric.
    public var persistHistoryPayload: Bool
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
        characteristics: (any CharacteristicSource)? = nil,
        trigger: RunTrigger = .manual,
        snapshotURL: URL? = nil,
        externalStatusURL: URL? = nil,
        ledgerHeadSeal: (any LedgerHeadSeal)? = nil,
        ledgerSealURL: URL? = nil,
        scope: DestinationExportScope? = nil,
        replaySampleLimit: Int = AnchorGuard.implausibleDeltaSamples,
        freshnessCadenceSeconds: TimeInterval = FreshnessTarget.defaultCadenceSeconds,
        deferForLowPower: Bool = false,
        persistHistoryPayload: Bool = true,
        destinations: [RunDestination] = []
    ) {
        self.source = source
        self.destination = destination
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
        self.characteristics = characteristics
        self.trigger = trigger
        self.snapshotURL = snapshotURL
        self.externalStatusURL = externalStatusURL
        self.ledgerHeadSeal = ledgerHeadSeal
        self.ledgerSealURL = ledgerSealURL
        self.scope = scope
        self.replaySampleLimit = replaySampleLimit
        self.freshnessCadenceSeconds = freshnessCadenceSeconds
        self.deferForLowPower = deferForLowPower
        self.persistHistoryPayload = persistHistoryPayload
    }

    var rowCollector: DestinationRowCollector?

    /// The same run, with each sink's own result alongside the combined outcome.
    public func runFanout() async throws -> FanoutRunResult {
        let collector = DestinationRowCollector()
        var run = self
        run.rowCollector = collector
        let outcome = try await run.run()
        return FanoutRunResult(outcome: outcome, destinations: await collector.rows())
    }

    public func run() async throws -> RunOutcome {
        let startedAt = clock.now()
        var lastMark = startedAt
        var timings: [RunStepTiming] = []
        func mark(_ name: String) {
            let now = clock.now()
            timings.append(
                RunStepTiming(
                    name: name,
                    durationMillis: max(0, Int((now.timeIntervalSince(lastMark) * 1000).rounded()))
                )
            )
            lastMark = now
        }
        if deferForLowPower {
            let tally = RunTally(
                failed: 1,
                terminalError: .lowPowerMode,
                partialCause: ErrorClass.lowPowerMode.rawValue
            )
            let outcome = RunOutcome.derive(from: tally)
            try await record(outcome: outcome, tally: tally, receipt: nil, startedAt: startedAt)
            return outcome
        }
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
            try await record(outcome: outcome, tally: tally, receipt: nil, startedAt: startedAt)
            return outcome
        }
        if MetricCatalog.isCharacteristic(metric) {
            return try await runCharacteristic(startedAt: startedAt, mark: mark)
        }
        let owed = try owedDestinations()
        if owed.isEmpty {
            let outcome = RunOutcome.derive(from: RunTally(nothingDue: true))
            try await record(
                outcome: outcome,
                tally: RunTally(nothingDue: true),
                receipt: nil,
                startedAt: startedAt,
                timings: timings
            )
            return outcome
        }
        let effectiveEpoch = max(epoch, typeStatus?.generation ?? epoch)
        let openHold = try await store.transact { try $0.loadAnchorHold(metric: metric) }
        var authorizedReexport = false
        if let openHold {
            guard openHold.decision == .reexportAuthorized else {
                // Someone has to decide whether this metric re-exports its history.
                // Until they do, running would make that decision for them.
                return try await refuse(
                    cause: AnchorGuard.heldJournalDetail,
                    startedAt: startedAt,
                    timings: timings
                )
            }
            // Decided, and the decision was to send it all again. The guards below stay
            // quiet for this run so they do not re-hold what was just authorised.
            authorizedReexport = true
            try await store.transact { try $0.clearAnchorHold(metric: metric) }
        }
        let prior: CursorSnapshot?
        do {
            prior = try await store.transact { tx in
                try tx.loadCursor(metric: metric)
            }
        } catch let error as CheckpointError {
            let tally = RunTally(failed: 1, terminalError: .internalFault, partialCause: "anchor_undecodable")
            let outcome = RunOutcome.derive(from: tally)
            try await record(outcome: outcome, tally: tally, receipt: nil, startedAt: startedAt)
            throw error
        }
        let lastEmittedDay = try await store.transact { tx in
            try tx.latestEmittedDay(metric: metric)
        }
        if !authorizedReexport,
           AnchorGuard.cursorIsLost(hasCursor: prior != nil, lastEmittedDay: lastEmittedDay)
        {
            // Reading now would pass a nil anchor and pull the whole store back, which
            // is exactly the silent full re-export QA-17 forbids. Do not read at all.
            try await hold(reason: .cursorLost, observedSamples: 0, lastEmittedDay: lastEmittedDay)
            return try await refuse(
                cause: AnchorGuard.journalDetail,
                startedAt: startedAt,
                timings: timings
            )
        }
        try await persistOpenRun(
            phase: "reading",
            startedAt: startedAt
        )
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
            try await record(outcome: outcome, tally: tally, receipt: nil, startedAt: startedAt)
            if errorClass == .deviceLocked
                || errorClass == .healthDataRestricted
                || errorClass == .lowPowerMode
                || errorClass == .awaitingUnmetered
            {
                return outcome
            }
            throw error
        }
        mark("read")
        try await persistOpenRun(
            phase: "reading",
            startedAt: startedAt,
            samplesRead: page.censusKeys.count + page.tombstones.count
        )
        #if DEBUG
        try faults.hit(.afterRead)
        #endif
        let freshnessTiming = freshnessTiming(for: page)
        let returned = page.censusKeys.count + page.tombstones.count
        if !authorizedReexport,
           AnchorGuard.replayIsSuspected(
               resumedFromAnchor: prior != nil,
               sampleCount: returned,
               limit: replaySampleLimit
           )
        {
            // The anchor was accepted and the source still replayed the store, so the
            // anchor no longer means what it says. Drop the page rather than enqueue it.
            try await hold(
                reason: .replaySuspected,
                observedSamples: returned,
                lastEmittedDay: lastEmittedDay
            )
            return try await refuse(
                cause: AnchorGuard.journalDetail,
                startedAt: startedAt,
                timings: timings
            )
        }
        let aggregates = try await drainPlans(for: page)
        if !page.hasRecords, aggregates.isEmpty {
            let outcome = RunOutcome.derive(from: RunTally(nothingDue: true))
            try await record(
                outcome: outcome,
                tally: RunTally(nothingDue: true),
                receipt: nil,
                startedAt: startedAt,
                timings: timings
            )
            return outcome
        }

        let batchID = NativeWire.mintBatchID(at: clock.now())
        var wireEnvelope = envelope
        wireEnvelope.seq = try await store.transact {
            try $0.reserveBatchSequence(exporterID: envelope.exporterId)
        }
        wireEnvelope.completeThrough = page.observedThrough.ISO8601Format()
        let horizonBound = try await store.transact { tx -> String? in
            let stored = try tx.loadVerifiedThroughDay(metric: metric)
            let horizon = try tx.loadIndexHorizonDay()
            return [stored, horizon].compactMap { $0 }.min()
        }
        if let horizonBound {
            wireEnvelope.verifiedThrough = EmittedIndexPolicy.verifiedThrough(
                completeThrough: wireEnvelope.completeThrough,
                horizonDay: horizonBound
            )
        }
        if wireEnvelope.tzDatabaseVersion == nil,
           temporal.tzDatabaseVersion != "unknown",
           !temporal.tzDatabaseVersion.isEmpty
        {
            wireEnvelope.tzDatabaseVersion = temporal.tzDatabaseVersion
        }
        let payloadURL = scratchDirectory.appendingPathComponent(
            NativeWire.outputFileName(batchID: batchID, demo: envelope.demo)
        )
        // Encoded straight to the file. Holding the page's payload as `Data` cost three
        // simultaneous copies of a full T1 page and broke R-74's 100 MiB ceiling.
        var payloadBytes = 0
        try FileWriteKit.writeAtomically(to: payloadURL) { handle in
            payloadBytes = try NativeWire.encode(
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
                envelope: wireEnvelope,
                to: handle
            )
        }
        #if DEBUG
        try faults.hit(.afterTransform)
        #endif
        mark("transform")

        let recordCount = page.encodedRecordCount + aggregates.count
        var rangeDays = page.censusKeys.map(\.day)
        rangeDays.append(
            contentsOf: page.correlations.map { String($0.start.prefix(10)) }
        )
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
        let applyEpoch = clock.now().timeIntervalSince1970
        let pending = PendingBatch(
            id: batchID,
            payloadURL: payloadURL.path,
            expectedRecords: recordCount,
            byteCount: payloadBytes,
            metric: metric,
            createdAtEpoch: applyEpoch,
            rangeStartDay: rangeDays.min() ?? fallbackDay,
            rangeEndDay: rangeDays.max() ?? fallbackDay
        )
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
        let enqueue = try await store.transact { tx -> (victims: [PendingBatch], undatable: [String]) in
            let evicted = try QueueAdmission.makeRoom(for: pending.byteCount, on: tx)
            try tx.commitFanout(
                pending,
                destinations: try owed.map {
                    try FanoutObligation.destination(
                        id: $0.id,
                        metric: metric,
                        expectedRecords: expectedByDestination[$0.id] ?? pending.expectedRecords,
                        scope: $0.scope
                    )
                },
                advancing: CursorAdvance(
                    page: page,
                    epoch: effectiveEpoch,
                    tzDatabaseVersion: temporal.tzDatabaseVersion
                )
            )
            let census = try Census.apply(
                page: page,
                to: tx,
                atEpoch: applyEpoch
            )
            try EmittedIndex.record(
                page: page,
                batchID: pending.id,
                on: tx,
                atEpoch: applyEpoch
            )
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
            return (evicted, census.undatableUUIDs)
        }
        mark("enqueue")
        try await persistOpenRun(
            phase: "delivering",
            startedAt: startedAt,
            samplesRead: recordCount,
            samplesCommitted: recordCount
        )
        for victim in enqueue.victims {
            try? FileManager.default.removeItem(atPath: victim.payloadURL)
        }
        #if DEBUG
        try faults.hit(.afterEnqueueBeforeDestinationWrite)
        #endif
        var accepted = 0
        var unconfirmed = 0
        var statusOnly = false
        var failed = 0
        var terminalError = ErrorClass.none
        var partialCause: String?
        var lastReceipt: DeliveryReceipt?
        var receipts: [(RunDestination, DeliveryReceipt)] = []
        var failures: [String: DestinationSendError] = [:]
        var releasedPayloads: [DeliverySettlement] = []
        for dest in owed where dest.attemptNow {
            do {
                receipts.append(
                    (
                        dest,
                        try await deliver(
                            pending: pending,
                            dest: dest,
                            expectedRecords: expectedByDestination[dest.id] ?? pending.expectedRecords
                        )
                    )
                )
            } catch let error as DestinationSendError {
                failed += 1
                terminalError = error.errorClass
                partialCause = error.errorClass.rawValue
                failures[dest.id] = error
            }
        }
        mark("send")
        if !receipts.isEmpty {
            #if DEBUG
            try faults.hit(.afterAckBeforeRelease)
            #endif
            for (dest, receipt) in receipts {
                let settlement = try await store.transact { tx in
                    try FanoutObligation.settle(
                        receipt: receipt,
                        destinationID: dest.id,
                        on: tx
                    )
                }
                // Unlinked after the run records: the history copy and the digest are
                // still taken from the queued payload.
                releasedPayloads.append(settlement)
                accepted += receipt.accepted
                unconfirmed += receipt.unconfirmed
                statusOnly = statusOnly || receipt.statusOnly
                lastReceipt = receipt
            }
        }
        let attemptedCount = owed.filter(\.attemptNow).count
        let owedExpected = owed.filter(\.attemptNow).reduce(0) {
            $0 + (expectedByDestination[$1.id] ?? recordCount)
        }
        var tally = RunTally(
            read: attemptedCount == 0 ? recordCount : owedExpected,
            committed: recordCount,
            acked: attemptedCount == 0 ? recordCount : accepted,
            unconfirmed: unconfirmed,
            failed: failed,
            terminalError: terminalError,
            ackEvidenceStatusOnly: statusOnly,
            partialCause: partialCause
        )
        if attemptedCount == 1, accepted < recordCount, unconfirmed == 0, failed == 0 {
            tally.partialCause = "receipt_short"
        }
        let outcome = RunOutcome.derive(from: tally)
        let journalTally = RunTally(
            read: recordCount,
            committed: recordCount,
            acked: lastReceipt?.accepted ?? 0,
            unconfirmed: lastReceipt?.unconfirmed ?? 0,
            failed: failed,
            terminalError: terminalError,
            ackEvidenceStatusOnly: statusOnly,
            partialCause: tally.partialCause
        )
        let children = destinationRows(
            owed: owed,
            expectedByDestination: expectedByDestination,
            receipts: receipts,
            failures: failures,
            fallbackExpected: recordCount
        )
        // Each sink's own result, so a caller can report a destination's status as
        // its own rather than as the combination of every sink's.
        await rowCollector?.record(children)
        try await record(
            outcome: outcome,
            tally: journalTally,
            receipt: lastReceipt,
            freshnessTiming: freshnessTiming,
            startedAt: startedAt,
            timings: timings,
            pending: pending,
            children: children
        )
        for settlement in releasedPayloads {
            FanoutObligation.unlink(settlement)
        }
        try await sweepUndatable(enqueue.undatable)
        return outcome
    }

    /// A history row per destination that was owed this read. A single-destination run
    /// keeps the flat one-row history it has always had, so these appear only where the
    /// parent row would otherwise hide what happened per sink.
    private func destinationRows(
        owed: [RunDestination],
        expectedByDestination: [String: Int],
        receipts: [(RunDestination, DeliveryReceipt)],
        failures: [String: DestinationSendError],
        fallbackExpected: Int
    ) -> [DestinationRunRow] {
        guard owed.count > 1 else { return [] }
        let accepted = Dictionary(
            receipts.map { ($0.0.id, $0.1) },
            uniquingKeysWith: { _, latest in latest }
        )
        return owed.map { dest in
            let expected = expectedByDestination[dest.id] ?? fallbackExpected
            guard dest.attemptNow else {
                return DestinationRunRow(
                    destinationID: dest.id,
                    outcomeKind: RunEvent.queuedOutcomeKind,
                    detail: "",
                    expectedRecords: expected,
                    acceptedRecords: 0,
                    errorClass: nil
                )
            }
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
            let receipt = accepted[dest.id]
            let outcome = RunOutcome.derive(
                from: RunTally(
                    read: expected,
                    committed: expected,
                    acked: receipt?.accepted ?? 0,
                    unconfirmed: receipt?.unconfirmed ?? 0,
                    ackEvidenceStatusOnly: receipt?.statusOnly ?? false
                )
            )
            return DestinationRunRow(
                destinationID: dest.id,
                outcomeKind: outcome.kind.rawValue,
                detail: outcome.partialCause ?? "",
                expectedRecords: expected,
                acceptedRecords: receipt?.accepted ?? 0,
                errorClass: nil
            )
        }
    }

    private func sweepUndatable(_ uuids: [String]) async throws {
        guard !uuids.isEmpty, !envelope.demo, let observations else { return }
        _ = try await ReconcileSweep(
            observations: observations,
            destination: destination,
            store: store,
            metric: metric,
            scratchDirectory: scratchDirectory,
            destinationName: destinationName,
            envelope: envelope,
            clock: clock,
            temporal: temporal,
            statistics: statistics,
            trigger: trigger,
            snapshotURL: snapshotURL,
            externalStatusURL: externalStatusURL,
            ledgerHeadSeal: ledgerHeadSeal,
            ledgerSealURL: ledgerSealURL,
            scope: scope
        ).runCensusDays()
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

    private func hold(
        reason: AnchorHold.Reason,
        observedSamples: Int,
        lastEmittedDay: String?
    ) async throws {
        let detectedAt = clock.now().timeIntervalSince1970
        try await store.transact { tx in
            try tx.upsertAnchorHold(
                AnchorHold(
                    metric: metric,
                    reason: reason,
                    detectedAtEpoch: detectedAt,
                    observedSamples: observedSamples,
                    lastEmittedDay: lastEmittedDay
                )
            )
        }
    }

    private func refuse(
        cause: String,
        startedAt: Date,
        timings: [RunStepTiming]
    ) async throws -> RunOutcome {
        let tally = RunTally(failed: 1, terminalError: .internalFault, partialCause: cause)
        let outcome = RunOutcome.derive(from: tally)
        try await record(
            outcome: outcome,
            tally: tally,
            receipt: nil,
            startedAt: startedAt,
            timings: timings
        )
        return outcome
    }

    private func record(
        outcome: RunOutcome,
        tally: RunTally,
        receipt: DeliveryReceipt?,
        freshnessTiming: (
            freshnessClass: FreshnessClass,
            firstObservedAtEpoch: TimeInterval,
            observationLatencySeconds: TimeInterval
        )? = nil,
        startedAt: Date? = nil,
        timings: [RunStepTiming] = [],
        pending: PendingBatch? = nil,
        children: [DestinationRunRow] = []
    ) async throws {
        let nowEpoch = clock.now().timeIntervalSince1970
        let runID = RunID(rawValue: "run-\(metric.rawValue)")
        let durationMillis = startedAt.map {
            max(0, Int((clock.now().timeIntervalSince($0) * 1000).rounded()))
        } ?? 0
        var payloadPath: String?
        var payloadSHA: String?
        if persistHistoryPayload, let pending {
            let dir = scratchDirectory.appendingPathComponent("history-payloads", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("\(metric.rawValue)-\(Int(nowEpoch)).ndjson")
            let source = URL(fileURLWithPath: pending.payloadURL)
            try FileWriteKit.copyAtomically(from: source, to: url)
            payloadPath = url.path
            payloadSHA = try ContentSHA256.hex(file: source)
        }
        let facts = RunHistoryFacts(
            destinationID: destinationName,
            metric: metric.rawValue,
            windowStartDay: pending?.rangeStartDay,
            windowEndDay: pending?.rangeEndDay,
            byteCount: pending?.byteCount ?? 0,
            durationMillis: durationMillis,
            stepTimings: timings,
            payloadSHA256: payloadSHA,
            redactedPayload: RunHistoryDetail.redactedPayload(
                metric: metric.rawValue,
                records: tally.committed,
                byteCount: pending?.byteCount ?? 0,
                windowStartDay: pending?.rangeStartDay,
                windowEndDay: pending?.rangeEndDay
            ),
            payloadPath: payloadPath
        )
        let freshnessLatency: RunFreshnessLatency?
        if !envelope.demo,
           outcome.kind == .success,
           receipt != nil,
           let freshnessTiming {
            freshnessLatency = RunFreshnessLatency(
                runID: runID,
                destinationID: destinationName,
                freshnessClass: freshnessTiming.freshnessClass,
                firstObservedAtEpoch: freshnessTiming.firstObservedAtEpoch,
                observationLatencySeconds: freshnessTiming.observationLatencySeconds,
                deliveryLatencySeconds: nowEpoch - freshnessTiming.firstObservedAtEpoch,
                recordedAtEpoch: nowEpoch
            )
        } else {
            freshnessLatency = nil
        }
        var settlement = DeliverySettlement(batchReleased: false)
        try await store.transact { tx in
            if let receipt, destinations.count == 1 {
                settlement = try FanoutObligation.settle(
                    receipt: receipt,
                    destinationID: destinationName,
                    on: tx
                )
            }
            if let freshnessLatency {
                try tx.appendFreshnessLatency(freshnessLatency)
            }
            try tx.appendJournal(
                RunEvent(
                    runID: runID,
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
                        : tally.terminalError.rawValue,
                    facts: facts
                )
            )
            // One read, N sinks: the parent row above is the read, and each child row
            // below is what a single destination did with it.
            for child in children {
                try tx.appendJournal(
                    RunEvent(
                        runID: RunID(rawValue: "\(runID.rawValue)|\(child.destinationID)"),
                        outcomeKind: child.outcomeKind,
                        detail: child.detail,
                        trigger: trigger,
                        samplesRead: child.expectedRecords,
                        samplesCommitted: child.expectedRecords,
                        samplesAcked: child.acceptedRecords,
                        wallTimeEpoch: nowEpoch,
                        errorClass: child.errorClass,
                        facts: RunHistoryFacts(
                            destinationID: child.destinationID,
                            metric: metric.rawValue,
                            windowStartDay: pending?.rangeStartDay,
                            windowEndDay: pending?.rangeEndDay,
                            parentRunID: runID.rawValue
                        )
                    )
                )
            }
            try tx.closeOpenRun(destinationID: destinationName, metric: metric)
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
        FanoutObligation.unlink(settlement)
        var freshnessEstimates: [FreshnessClass: LocalFreshnessEstimate] = [:]
        var queueOccupancy = QueueOccupancy.green.snapshotToken
        let snapshotTargetsExist = snapshotURL != nil
            || destinations.contains { $0.snapshotURL != nil }
        if snapshotTargetsExist {
            let queued = try await store.transact { try $0.queuedBytes() }
            queueOccupancy = QueueRed.occupancy(queuedBytes: queued).snapshotToken
            for freshnessClass in FreshnessClass.allCases {
                let observations = try await store.transact {
                    try $0.loadFreshnessLatencies(
                        destinationID: destinationName,
                        freshnessClass: freshnessClass
                    )
                }
                if !observations.isEmpty {
                    freshnessEstimates[freshnessClass] =
                        FreshnessTarget.localEstimate(observations: observations)
                }
            }
        }
        try FanoutSnapshotWriter.write(
            destinations: destinations,
            destinationName: destinationName,
            fallbackURL: snapshotURL,
            children: children,
            outcome: outcome,
            combinedErrorClass: tally.terminalError.rawValue,
            now: clock.now().timeIntervalSince1970,
            trigger: trigger,
            freshnessCadenceSeconds: freshnessCadenceSeconds,
            freshnessEstimates: freshnessEstimates,
            queueOccupancy: queueOccupancy
        )
        try writeExternalStatus(outcome: outcome, tally: tally)
        try await writeLedgerHeadSeal()
    }

    private func freshnessTiming(
        for page: SamplePage
    ) -> (
        freshnessClass: FreshnessClass,
        firstObservedAtEpoch: TimeInterval,
        observationLatencySeconds: TimeInterval
    )? {
        guard let freshnessClass = FreshnessClass.knownClass(for: metric) else { return nil }
        var pairs: [(observedAt: String, end: String)] = []
        pairs += page.samples.map { ($0.observedAt, $0.end) }
        pairs += page.categories.map { ($0.observedAt, $0.end) }
        pairs += page.correlations.map { ($0.observedAt, $0.end) }
        pairs += page.workouts.map { ($0.observedAt, $0.end) }
        pairs += page.minds.map { ($0.observedAt, $0.end) }
        pairs += page.electrocardiograms.map { ($0.observedAt, $0.end) }
        pairs += page.audiograms.map { ($0.observedAt, $0.end) }
        pairs += page.medicationDoses.map { ($0.observedAt, $0.end) }

        let timings: [(firstObservedAtEpoch: TimeInterval, latency: TimeInterval)] =
            pairs.compactMap { pair in
                guard let observedAt = Self.parseISO8601(pair.observedAt),
                      let end = Self.parseISO8601(pair.end) else {
                    return nil
                }
                let latency = observedAt.timeIntervalSince(end)
                guard latency.isFinite, latency >= 0 else { return nil }
                return (observedAt.timeIntervalSince1970, latency)
            }
        return timings.max { $0.latency < $1.latency }
            .map { (freshnessClass, $0.0, $0.1) }
    }

    private func runCharacteristic(
        startedAt: Date,
        mark: (String) -> Void
    ) async throws -> RunOutcome {
        try await persistOpenRun(phase: "reading", startedAt: startedAt)
        let snapshot: CharacteristicRecord?
        do {
            snapshot = try await characteristics?.read(
                metric: metric,
                observedAt: envelope.observedAt
            )
        } catch {
            let errorClass = (error as? DestinationSendError)?.errorClass ?? .internalFault
            let tally = RunTally(
                failed: 1,
                terminalError: errorClass,
                partialCause: errorClass.rawValue
            )
            let outcome = RunOutcome.derive(from: tally)
            try await record(outcome: outcome, tally: tally, receipt: nil, startedAt: startedAt)
            if errorClass == .deviceLocked
                || errorClass == .healthDataRestricted
                || errorClass == .lowPowerMode
                || errorClass == .awaitingUnmetered
            {
                return outcome
            }
            throw error
        }
        mark("read")
        guard let snapshot else {
            let tally = RunTally(nothingDue: true)
            let outcome = RunOutcome.derive(from: tally)
            try await record(outcome: outcome, tally: tally, receipt: nil, startedAt: startedAt)
            return outcome
        }
        let identity = Data("ohe.characteristic.v1:\(snapshot.characteristicId):\(snapshot.value)".utf8)
        let batchID = NativeWire.mintBatchID(at: clock.now())
        var wireEnvelope = envelope
        wireEnvelope.seq = try await store.transact {
            try $0.reserveBatchSequence(exporterID: envelope.exporterId)
        }
        let payload = try NativeWire.encode(
            samples: [],
            tombstones: [],
            characteristics: [snapshot],
            metric: metric,
            batchID: batchID,
            envelope: wireEnvelope
        )
        let payloadURL = scratchDirectory.appendingPathComponent(
            NativeWire.outputFileName(batchID: batchID, demo: envelope.demo)
        )
        try FileWriteKit.writeAtomically(payload, to: payloadURL)
        mark("transform")
        let applyEpoch = clock.now().timeIntervalSince1970
        let day = String(envelope.observedAt.prefix(10))
        let pending = PendingBatch(
            id: batchID,
            payloadURL: payloadURL.path,
            expectedRecords: 1,
            byteCount: payload.count,
            metric: metric,
            createdAtEpoch: applyEpoch,
            rangeStartDay: day,
            rangeEndDay: day
        )
        let dummyPage = SamplePage(
            samples: [],
            tombstones: [],
            metric: metric,
            anchorBlob: identity,
            observedThrough: clock.now()
        )
        try await store.transact { tx in
            _ = try QueueAdmission.makeRoom(for: pending.byteCount, on: tx)
            try tx.commitFanout(
                pending,
                destinations: [
                    try FanoutObligation.destination(
                        id: destinationName,
                        metric: metric,
                        expectedRecords: pending.expectedRecords,
                        scope: scope
                    ),
                ],
                advancing: CursorAdvance(
                    page: dummyPage,
                    epoch: epoch,
                    tzDatabaseVersion: temporal.tzDatabaseVersion
                )
            )
        }
        mark("enqueue")
        let receipt: DeliveryReceipt
        do {
            #if DEBUG
            receipt = try await DeliveryExecutor.send(
                batch: pending,
                destination: destination,
                destinationName: destinationName,
                store: store,
                faults: faults,
                clock: clock,
                scope: scope
            )
            #else
            receipt = try await DeliveryExecutor.send(
                batch: pending,
                destination: destination,
                destinationName: destinationName,
                store: store,
                clock: clock,
                scope: scope
            )
            #endif
        } catch let error as DestinationSendError {
            mark("send")
            let tally = RunTally(
                read: 1,
                committed: 1,
                failed: 1,
                terminalError: error.errorClass,
                partialCause: error.errorClass.rawValue
            )
            let outcome = RunOutcome.derive(from: tally)
            try await record(
                outcome: outcome,
                tally: tally,
                receipt: nil,
                startedAt: startedAt,
                pending: pending
            )
            return outcome
        }
        mark("send")
        var tally = RunTally(
            read: 1,
            committed: 1,
            acked: receipt.accepted,
            unconfirmed: receipt.unconfirmed,
            ackEvidenceStatusOnly: receipt.statusOnly
        )
        if receipt.accepted < 1, receipt.unconfirmed == 0 {
            tally.partialCause = "receipt_short"
        }
        let outcome = RunOutcome.derive(from: tally)
        try await record(
            outcome: outcome,
            tally: tally,
            receipt: receipt,
            startedAt: startedAt,
            pending: pending
        )
        return outcome
    }

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
        if matching.isEmpty, destinations.count == 1, destinations[0].role.allows(trigger) {
            if let error = lastScopeError {
                throw error
            }
            if let scope = destinations[0].scope {
                try ExportScopeGate.require(metric: metric, scope: scope)
            }
        }
        return matching
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
        #if DEBUG
        return try await DeliveryExecutor.send(
            batch: attempt,
            destination: dest.destination,
            destinationName: dest.id,
            store: store,
            faults: faults,
            clock: clock,
            scope: dest.scope,
            skipRangeGate: url.path != pending.payloadURL
        )
        #else
        return try await DeliveryExecutor.send(
            batch: attempt,
            destination: dest.destination,
            destinationName: dest.id,
            store: store,
            clock: clock,
            scope: dest.scope,
            skipRangeGate: url.path != pending.payloadURL
        )
        #endif
    }

    private func persistOpenRun(
        phase: String,
        startedAt: Date,
        samplesRead: Int = 0,
        samplesCommitted: Int = 0,
        samplesAcked: Int = 0
    ) async throws {
        try await store.transact { tx in
            try tx.upsertOpenRun(
                OpenRun(
                    destinationID: destinationName,
                    metric: metric,
                    phase: phase,
                    trigger: trigger,
                    startedAtEpoch: startedAt.timeIntervalSince1970,
                    samplesRead: samplesRead,
                    samplesCommitted: samplesCommitted,
                    samplesAcked: samplesAcked
                )
            )
        }
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
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
