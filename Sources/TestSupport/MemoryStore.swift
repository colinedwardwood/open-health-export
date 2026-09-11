// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import EnginePorts
import Foundation
import RunJournal

public final class MemoryTransaction: StateTransaction {
    public var journal: [RunEvent] = []
    public var ledger: [EgressEntry] = []
    public var cursors: [MetricID: CursorSnapshot] = [:]
    public var backfillCheckpoints: [String: Data] = [:]
    public var gaps: [GapRecord] = []
    public var census: [String: CensusRow] = [:]
    public var dirty: [MetricID: Set<String>] = [:]
    public var deliveries: [BatchID: DeliveryReceipt] = [:]
    public var pending: [BatchID: PendingBatch] = [:]
    public var emittedIndex: [String: EmittedIndexRow] = [:]
    public var aggregateEmitSeq: [String: Int] = [:]
    public var typeStatus: [MetricID: TypeStatus] = [:]
    public var anchorHolds: [MetricID: AnchorHold] = [:]
    private var pendingOrder: [BatchID] = []

    public init() {}

    public func loadCursor(metric: MetricID) throws -> CursorSnapshot? {
        guard let stored = cursors[metric] else { return nil }
        let checkpoint = try CheckpointEnvelope.decoded(stored.anchorBlob)
        return CursorSnapshot(
            metric: stored.metric,
            epoch: checkpoint.epoch,
            anchorBlob: checkpoint.adapterAnchor
        )
    }

    public func loadBackfillCheckpoint(jobID: String) throws -> Data? {
        backfillCheckpoints[jobID]
    }

    public func upsertBackfillCheckpoint(jobID: String, bytes: Data) throws {
        backfillCheckpoints[jobID] = bytes
    }

    public func enqueuePending(_ batch: PendingBatch) throws {
        if pending[batch.id] == nil {
            pendingOrder.append(batch.id)
        }
        pending[batch.id] = batch
    }

    public func commitBatch(_ batch: PendingBatch, advancing: CursorAdvance) throws {
        try enqueuePending(batch)
        let envelope = CheckpointEnvelope(
            tzDatabaseVersion: advancing.tzDatabaseVersion,
            epoch: advancing.epoch,
            adapterAnchor: advancing.snapshot.anchorBlob
        )
        cursors[advancing.metric] = CursorSnapshot(
            metric: advancing.metric,
            epoch: advancing.epoch,
            anchorBlob: envelope.encoded()
        )
    }

    public func pendingBatches() throws -> [PendingBatch] {
        pendingOrder.compactMap { pending[$0] }
    }

    public func queuedBytes() throws -> Int {
        pending.values.reduce(0) { $0 + $1.byteCount }
    }

    public func loadGaps() throws -> [GapRecord] {
        gaps
    }

    public func evict(_ batchID: BatchID, recording: GapRecord) throws {
        pending.removeValue(forKey: batchID)
        pendingOrder.removeAll { $0 == batchID }
        gaps.append(recording)
    }

    public func recordDelivery(_ receipt: DeliveryReceipt) throws {
        deliveries[receipt.batchID] = receipt
        if let batch = pending[receipt.batchID],
           receipt.unconfirmed == 0,
           receipt.accepted >= batch.expectedRecords {
            pending.removeValue(forKey: receipt.batchID)
            pendingOrder.removeAll { $0 == receipt.batchID }
        }
    }

    public func appendJournal(_ event: RunEvent) throws {
        journal.append(event)
    }

    public func unprojectedJournal(limit: Int) throws -> [RunEvent] {
        Array(journal.filter { $0.projectedAtEpoch == nil }.prefix(max(0, limit)))
    }

    public func markJournalProjected(runIDs: [RunID], atEpoch: TimeInterval) throws {
        let ids = Set(runIDs)
        for index in journal.indices where ids.contains(journal[index].runID) {
            if journal[index].projectedAtEpoch == nil {
                journal[index].projectedAtEpoch = atEpoch
            }
        }
    }

    public func appendLedger(_ entry: EgressEntry) throws {
        ledger.append(
            LedgerChain.seal(
                entry,
                sequence: ledger.count + 1,
                previousHash: ledger.last?.entryHash ?? LedgerChain.genesisHash
            )
        )
    }

    public func loadLedger() throws -> [EgressEntry] {
        ledger
    }

    public func upsertCensus(_ row: CensusRow) throws {
        census["\(row.metric.rawValue)|\(row.day)"] = row
    }

    public func loadCensus(metric: MetricID, day: String) throws -> CensusRow? {
        census["\(metric.rawValue)|\(day)"]
    }

    public func markDirty(metric: MetricID, day: String) throws {
        dirty[metric, default: []].insert(day)
    }

    public func dirtyDays(metric: MetricID) throws -> [String] {
        Array(dirty[metric] ?? []).sorted()
    }

    public func clearDirty(metric: MetricID, day: String) throws {
        dirty[metric]?.remove(day)
        if dirty[metric]?.isEmpty == true {
            dirty.removeValue(forKey: metric)
        }
    }

    public func upsertEmittedIndex(_ row: EmittedIndexRow) throws {
        emittedIndex[row.uuid] = row
    }

    public func loadEmittedIndex(uuid: String) throws -> EmittedIndexRow? {
        emittedIndex[uuid]
    }

    public func removeEmittedIndex(uuid: String) throws {
        emittedIndex.removeValue(forKey: uuid)
    }

    public func loadEmittedIndex(metric: MetricID, day: String) throws -> [EmittedIndexRow] {
        emittedIndex.values
            .filter { $0.metric == metric && $0.day == day }
            .sorted { $0.uuid < $1.uuid }
    }

    public func latestEmittedDay(metric: MetricID) throws -> String? {
        emittedIndex.values
            .filter { $0.metric == metric }
            .map(\.day)
            .max()
    }

    public func loadAggregateEmitSeq(bucketKey: String) throws -> Int? {
        aggregateEmitSeq[bucketKey]
    }

    public func upsertAggregateEmitSeq(bucketKey: String, emitSeq: Int) throws {
        aggregateEmitSeq[bucketKey] = emitSeq
    }

    public func loadJournal() throws -> [RunEvent] {
        journal
    }

    public func loadTypeStatus(metric: MetricID) throws -> TypeStatus? {
        typeStatus[metric]
    }

    public func upsertTypeStatus(_ status: TypeStatus) throws {
        typeStatus[status.metric] = status
    }

    public func loadAnchorHold(metric: MetricID) throws -> AnchorHold? {
        anchorHolds[metric]
    }

    public func loadAnchorHolds() throws -> [AnchorHold] {
        anchorHolds.values.sorted { $0.metric.rawValue < $1.metric.rawValue }
    }

    public func upsertAnchorHold(_ hold: AnchorHold) throws {
        anchorHolds[hold.metric] = hold
    }

    public func clearAnchorHold(metric: MetricID) throws {
        anchorHolds.removeValue(forKey: metric)
    }

    public func purgeMetricState(metric: MetricID) throws {
        cursors.removeValue(forKey: metric)
        census = census.filter { $0.value.metric != metric }
        dirty.removeValue(forKey: metric)
        emittedIndex = emittedIndex.filter { $0.value.metric != metric }
        anchorHolds.removeValue(forKey: metric)
    }

    public func wipe(atEpoch: TimeInterval) throws -> [String] {
        let urls = pending.values.map(\.payloadURL)
        let destroyedCount = ledger.count
        let previousHead = ledger.last?.entryHash ?? LedgerChain.genesisHash
        journal = []
        ledger = []
        cursors = [:]
        backfillCheckpoints = [:]
        gaps = []
        census = [:]
        dirty = [:]
        deliveries = [:]
        pending = [:]
        pendingOrder = []
        emittedIndex = [:]
        aggregateEmitSeq = [:]
        typeStatus = [:]
        anchorHolds = [:]
        try appendLedger(
            EgressEntry(
                destination: "local-device",
                sampleCount: 0,
                outcomeKind: "genesis_after_wipe",
                detail: "destroyed_count=\(destroyedCount) previous_head=\(previousHead)",
                wallTimeEpoch: atEpoch
            )
        )
        return urls
    }
}

public final class MemoryStateStore: StateStore, @unchecked Sendable {
    public let transaction = MemoryTransaction()

    public init() {}

    public func transact<T: Sendable>(
        _ body: (any StateTransaction) throws -> T
    ) async throws -> T {
        try body(transaction)
    }

    public func wipe(atEpoch: TimeInterval) async throws {
        let urls = try await transact { try $0.wipe(atEpoch: atEpoch) }
        for path in urls {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}

public struct FixtureSource: SampleSource {
    public var pages: [SamplePage]
    public init(pages: [SamplePage]) { self.pages = pages }

    public func page(metric: MetricID, afterAnchor: Data?) async throws -> SamplePage {
        let empty = SamplePage(
            samples: [],
            tombstones: [],
            metric: metric,
            anchorBlob: afterAnchor ?? Data(),
            observedThrough: Date(timeIntervalSince1970: 0)
        )
        let matching = pages.filter { $0.metric == metric }
        guard !matching.isEmpty else { return empty }
        if let afterAnchor, let idx = matching.firstIndex(where: { $0.anchorBlob == afterAnchor }) {
            let next = matching.index(after: idx)
            return next < matching.endIndex ? matching[next] : empty
        }
        return matching[0]
    }
}

public struct FixtureDays: BoundedDayObservationSource, Sendable {
    public var byDay: [String: [SampleRecord]]
    public init(byDay: [String: [SampleRecord]]) { self.byDay = byDay }

    public func samples(metric: MetricID, day: String) async throws -> [SampleRecord] {
        (byDay[day] ?? []).filter { $0.metric == metric }
    }

    public func availableDayRange(metric: MetricID) async throws -> ClosedRange<String>? {
        let days = byDay.compactMap { day, samples in
            samples.contains { $0.metric == metric } ? day : nil
        }.sorted()
        guard let first = days.first, let last = days.last else { return nil }
        return first ... last
    }
}

public struct FixtureStatistics: StatisticsSource, Sendable {
    public var byDay: [String: AggregateRecord]
    public init(byDay: [String: AggregateRecord]) { self.byDay = byDay }

    public func dailyBucket(metric: MetricID, day: String) async throws -> AggregateRecord? {
        guard let record = byDay[day], record.metric == metric else { return nil }
        return record
    }
}
