import CoreDomain
import Foundation

public struct SamplePage: Sendable {
    public var samples: [SampleRecord]
    public var tombstones: [TombstoneRecord]
    public var metric: MetricID
    public var anchorBlob: Data
    public var observedThrough: Date

    public init(
        samples: [SampleRecord],
        tombstones: [TombstoneRecord],
        metric: MetricID,
        anchorBlob: Data,
        observedThrough: Date
    ) {
        self.samples = samples
        self.tombstones = tombstones
        self.metric = metric
        self.anchorBlob = anchorBlob
        self.observedThrough = observedThrough
    }
}

/// Constructible only alongside the page it describes.
public struct CursorAdvance: Sendable {
    public let metric: MetricID
    public let epoch: UInt32
    let anchorBlob: Data
    let observedThrough: Date

    public var snapshot: CursorSnapshot {
        CursorSnapshot(metric: metric, epoch: epoch, anchorBlob: anchorBlob)
    }

    public let tzDatabaseVersion: String

    public init(page: SamplePage, epoch: UInt32, tzDatabaseVersion: String = "unknown") {
        self.metric = page.metric
        self.epoch = epoch
        self.anchorBlob = page.anchorBlob
        self.observedThrough = page.observedThrough
        self.tzDatabaseVersion = tzDatabaseVersion
    }
}

public struct PendingBatch: Sendable, Equatable {
    public var id: BatchID
    public var payloadURL: String
    public var expectedRecords: Int
    public var byteCount: Int

    public init(id: BatchID, payloadURL: String, expectedRecords: Int = 0, byteCount: Int = 0) {
        self.id = id
        self.payloadURL = payloadURL
        self.expectedRecords = expectedRecords
        self.byteCount = byteCount
    }
}

public struct GapRecord: Sendable {
    public var batchID: BatchID
    public var rangeDescription: String
    public init(batchID: BatchID, rangeDescription: String) {
        self.batchID = batchID
        self.rangeDescription = rangeDescription
    }
}

public struct DeliveryReceipt: Sendable {
    public var batchID: BatchID
    public var accepted: Int
    public var statusOnly: Bool
    public var unconfirmed: Int
    public init(batchID: BatchID, accepted: Int, statusOnly: Bool, unconfirmed: Int = 0) {
        self.batchID = batchID
        self.accepted = accepted
        self.statusOnly = statusOnly
        self.unconfirmed = unconfirmed
    }
}

public struct RunEvent: Sendable {
    public var runID: RunID
    public var outcomeKind: String
    public var detail: String
    public init(runID: RunID, outcomeKind: String, detail: String) {
        self.runID = runID
        self.outcomeKind = outcomeKind
        self.detail = detail
    }
}

public struct EgressEntry: Sendable {
    public var destination: String
    public var sampleCount: Int
    public var outcomeKind: String
    public init(destination: String, sampleCount: Int, outcomeKind: String) {
        self.destination = destination
        self.sampleCount = sampleCount
        self.outcomeKind = outcomeKind
    }
}

public struct CursorSnapshot: Sendable, Equatable {
    public var metric: MetricID
    public var epoch: UInt32
    public var anchorBlob: Data

    public init(metric: MetricID, epoch: UInt32, anchorBlob: Data) {
        self.metric = metric
        self.epoch = epoch
        self.anchorBlob = anchorBlob
    }
}

public struct CensusRow: Sendable, Equatable {
    public var metric: MetricID
    public var day: String
    public var sampleCount: Int
    public var digest: String

    public init(metric: MetricID, day: String, sampleCount: Int, digest: String) {
        self.metric = metric
        self.day = day
        self.sampleCount = sampleCount
        self.digest = digest
    }
}

public struct EmittedIndexRow: Sendable, Equatable {
    public var uuid: String
    public var metric: MetricID
    public var day: String
    public var digest: String
    public var batchID: BatchID

    public init(uuid: String, metric: MetricID, day: String, digest: String, batchID: BatchID) {
        self.uuid = uuid
        self.metric = metric
        self.day = day
        self.digest = digest
        self.batchID = batchID
    }
}

public protocol StateTransaction: AnyObject {
    func loadCursor(metric: MetricID) throws -> CursorSnapshot?
    func commitBatch(_ batch: PendingBatch, advancing: CursorAdvance) throws
    /// Batches survive process death until a receipt confirms every expected record.
    func pendingBatches() throws -> [PendingBatch]
    func queuedBytes() throws -> Int
    func loadGaps() throws -> [GapRecord]
    func evict(_ batchID: BatchID, recording: GapRecord) throws
    func recordDelivery(_ receipt: DeliveryReceipt) throws
    func appendJournal(_ event: RunEvent) throws
    func appendLedger(_ entry: EgressEntry) throws
    func upsertCensus(_ row: CensusRow) throws
    func loadCensus(metric: MetricID, day: String) throws -> CensusRow?
    func markDirty(metric: MetricID, day: String) throws
    func dirtyDays(metric: MetricID) throws -> [String]
    func clearDirty(metric: MetricID, day: String) throws
    func upsertEmittedIndex(_ row: EmittedIndexRow) throws
    func loadEmittedIndex(uuid: String) throws -> EmittedIndexRow?
    func removeEmittedIndex(uuid: String) throws
    func loadEmittedIndex(metric: MetricID, day: String) throws -> [EmittedIndexRow]
}

public protocol StateStore: Sendable {
    /// Synchronous body: no suspension point inside the transaction.
    func transact<T: Sendable>(
        _ body: (any StateTransaction) throws -> T
    ) async throws -> T
}

public protocol SampleSource: Sendable {
    func page(metric: MetricID, afterAnchor: Data?) async throws -> SamplePage
}

public protocol DestinationSink: Sendable {
    func send(fileHandle: String, idempotencyKey: BatchID) async throws -> DeliveryReceipt
}

/// R-40 / DP-6: a classified notice, never prose. `kind` is the registry key the
/// renderer joins on; the stored strings are identifiers the copy interpolates.
/// Adding a title or body here would move user copy to the call site.
public struct UserNotice: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case destinationVerified
        case destinationPinned
        case destinationRepointed
        case destinationEnabled
        case destinationTrustLost
    }

    public var kind: Kind
    public var destination: String
    public var fingerprint: String?
    public var previousFingerprint: String?

    public init(
        kind: Kind,
        destination: String,
        fingerprint: String? = nil,
        previousFingerprint: String? = nil
    ) {
        self.kind = kind
        self.destination = destination
        self.fingerprint = fingerprint
        self.previousFingerprint = previousFingerprint
    }
}

/// R-41: no suppression parameter exists, so no call site can decline to notify.
public protocol UserNotifier: Sendable {
    func notify(_ notice: UserNotice) async throws
}

/// Opaque Keychain (or test-double) reference. The bytes never travel with the handle (AR-18).
public struct SecretHandle: Hashable, Sendable, Codable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public enum SecretStoreError: Error, Equatable {
    case notFound
    case emptyHandle
    case emptySecret
}

/// PSK and similar material. Implementations must not synchronise via iCloud (R-33).
public protocol SecretStore: Sendable {
    func store(_ bytes: [UInt8], handle: SecretHandle) async throws
    func load(_ handle: SecretHandle) async throws -> [UInt8]
    func delete(_ handle: SecretHandle) async throws
    /// R-43: wipe every secret this store owns, not one handle at a time.
    func deleteAll() async throws
}
