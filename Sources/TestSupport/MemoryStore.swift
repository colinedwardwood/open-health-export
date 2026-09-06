import CoreDomain
import EnginePorts
import Foundation

public final class MemoryTransaction: StateTransaction {
    public var journal: [RunEvent] = []
    public var ledger: [EgressEntry] = []
    public var cursors: [MetricID: CursorSnapshot] = [:]
    public var gaps: [GapRecord] = []
    public var census: [String: CensusRow] = [:]
    public var dirty: [MetricID: Set<String>] = [:]
    public var deliveries: [BatchID: DeliveryReceipt] = [:]
    public var pending: [BatchID: PendingBatch] = [:]
    private var pendingOrder: [BatchID] = []

    public init() {}

    public func loadCursor(metric: MetricID) throws -> CursorSnapshot? {
        cursors[metric]
    }

    public func commitBatch(_ batch: PendingBatch, advancing: CursorAdvance) throws {
        if pending[batch.id] == nil {
            pendingOrder.append(batch.id)
        }
        pending[batch.id] = batch
        cursors[advancing.metric] = advancing.snapshot
    }

    public func pendingBatches() throws -> [PendingBatch] {
        pendingOrder.compactMap { pending[$0] }
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

    public func appendLedger(_ entry: EgressEntry) throws {
        ledger.append(entry)
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
}

public final class MemoryStateStore: StateStore, @unchecked Sendable {
    public let transaction = MemoryTransaction()

    public init() {}

    public func transact<T: Sendable>(
        _ body: (any StateTransaction) throws -> T
    ) async throws -> T {
        try body(transaction)
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
        guard let page = pages.first(where: { $0.metric == metric }) else { return empty }
        if let afterAnchor, afterAnchor == page.anchorBlob {
            return empty
        }
        return page
    }
}
