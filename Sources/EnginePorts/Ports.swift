import CoreDomain
import Foundation

public struct SamplePage: Sendable {
    public var samples: [SampleRecord]
    public var categories: [CategoryRecord]
    public var correlations: [CorrelationRecord]
    public var workouts: [WorkoutRecord]
    public var minds: [StateOfMindRecord]
    public var electrocardiograms: [ECGRecord]
    public var audiograms: [AudiogramRecord]
    public var medicationDoses: [MedicationDoseRecord]
    public var series: [SeriesRecord]
    public var tombstones: [TombstoneRecord]
    public var metric: MetricID
    public var anchorBlob: Data
    public var observedThrough: Date

    public init(
        samples: [SampleRecord],
        categories: [CategoryRecord] = [],
        correlations: [CorrelationRecord] = [],
        workouts: [WorkoutRecord] = [],
        minds: [StateOfMindRecord] = [],
        electrocardiograms: [ECGRecord] = [],
        audiograms: [AudiogramRecord] = [],
        medicationDoses: [MedicationDoseRecord] = [],
        series: [SeriesRecord] = [],
        tombstones: [TombstoneRecord],
        metric: MetricID,
        anchorBlob: Data,
        observedThrough: Date
    ) {
        self.samples = samples
        self.categories = categories
        self.correlations = correlations
        self.workouts = workouts
        self.minds = minds
        self.electrocardiograms = electrocardiograms
        self.audiograms = audiograms
        self.medicationDoses = medicationDoses
        self.series = series
        self.tombstones = tombstones
        self.metric = metric
        self.anchorBlob = anchorBlob
        self.observedThrough = observedThrough
    }

    public var hasRecords: Bool {
        !samples.isEmpty || !categories.isEmpty || !correlations.isEmpty
            || !workouts.isEmpty || !minds.isEmpty || !electrocardiograms.isEmpty
            || !audiograms.isEmpty || !medicationDoses.isEmpty || !series.isEmpty
            || !tombstones.isEmpty
    }

    public var censusKeys: [(uuid: String, day: String)] {
        samples.map { ($0.key.uuid, String($0.start.prefix(10))) }
            + categories.map { ($0.key.uuid, String($0.start.prefix(10))) }
            + correlations.map { ($0.key.uuid, String($0.start.prefix(10))) }
            + workouts.map { ($0.key.uuid, String($0.start.prefix(10))) }
            + minds.map { ($0.key.uuid, String($0.start.prefix(10))) }
            + electrocardiograms.map { ($0.key.uuid, String($0.start.prefix(10))) }
            + audiograms.map { ($0.key.uuid, String($0.start.prefix(10))) }
            + medicationDoses.map { ($0.key.uuid, String($0.start.prefix(10))) }
            + series.map { ($0.uuid, String($0.parentStart.prefix(10))) }
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
    public var metric: MetricID
    public var createdAtEpoch: TimeInterval?
    public var rangeStartDay: String?
    public var rangeEndDay: String?

    public init(
        id: BatchID,
        payloadURL: String,
        expectedRecords: Int = 0,
        byteCount: Int = 0,
        metric: MetricID = MetricID(rawValue: ""),
        createdAtEpoch: TimeInterval? = nil,
        rangeStartDay: String? = nil,
        rangeEndDay: String? = nil
    ) {
        self.id = id
        self.payloadURL = payloadURL
        self.expectedRecords = expectedRecords
        self.byteCount = byteCount
        self.metric = metric
        self.createdAtEpoch = createdAtEpoch
        self.rangeStartDay = rangeStartDay
        self.rangeEndDay = rangeEndDay
    }
}

public enum TypeDisableReason {
    public static let authorizationRevoked = "authorization_revoked"
    public static let historyClipped = "history_clipped"
    public static let mdmRestricted = "health_data_restricted"
    public static let explicitStop = "explicit_stop"
}

public enum SamplePaging {
    public static let defaultPageLimit = 1000
}

public struct TypeStatus: Sendable, Equatable {
    public var metric: MetricID
    public var disabled: Bool
    public var reason: String
    public var generation: UInt32

    public init(
        metric: MetricID,
        disabled: Bool,
        reason: String,
        generation: UInt32 = 1
    ) {
        self.metric = metric
        self.disabled = disabled
        self.reason = reason
        self.generation = generation
    }
}

/// QA-17: a metric whose anchor can no longer be trusted. The hold stops the metric
/// exporting until someone decides what to do, because the alternative — reading with
/// no anchor — is a full re-export of the whole store that nobody asked for.
public struct AnchorHold: Sendable, Equatable {
    public enum Reason: String, Sendable, Equatable, CaseIterable {
        /// No cursor, but this metric has exported before. The anchor was lost, not absent.
        case cursorLost
        /// A delta run returned more than a delta plausibly can.
        case replaySuspected
    }

    /// What was decided about the hold. `nil` means nobody has decided yet, which is
    /// the state that keeps the metric stopped.
    public enum Decision: String, Sendable, Equatable, CaseIterable {
        /// The user accepted the cost and asked for the history to be sent again.
        case reexportAuthorized
    }

    public var metric: MetricID
    public var reason: Reason
    public var detectedAtEpoch: TimeInterval
    /// What the run saw: samples returned for a replay, 0 for a lost cursor.
    public var observedSamples: Int
    /// The last day we know reached a destination, so the decision can be costed.
    public var lastEmittedDay: String?
    public var decision: Decision?

    public init(
        metric: MetricID,
        reason: Reason,
        detectedAtEpoch: TimeInterval,
        observedSamples: Int = 0,
        lastEmittedDay: String? = nil,
        decision: Decision? = nil
    ) {
        self.metric = metric
        self.reason = reason
        self.detectedAtEpoch = detectedAtEpoch
        self.observedSamples = observedSamples
        self.lastEmittedDay = lastEmittedDay
        self.decision = decision
    }
}

public enum AuthGrant: String, Sendable, Equatable {
    case unknown
    case granted
    case denied
}

public struct GapRecord: Sendable {
    public var batchID: BatchID
    public var rangeDescription: String
    public var metric: MetricID
    public var rangeStartDay: String?
    public var rangeEndDay: String?

    public init(
        batchID: BatchID,
        rangeDescription: String,
        metric: MetricID = MetricID(rawValue: ""),
        rangeStartDay: String? = nil,
        rangeEndDay: String? = nil
    ) {
        self.batchID = batchID
        self.rangeDescription = rangeDescription
        self.metric = metric
        self.rangeStartDay = rangeStartDay
        self.rangeEndDay = rangeEndDay
    }
}

public struct DeliveryReceipt: Sendable {
    public var batchID: BatchID
    public var accepted: Int
    public var statusOnly: Bool
    public var unconfirmed: Int
    public var traceparentAutoDisabled: Bool
    public init(
        batchID: BatchID,
        accepted: Int,
        statusOnly: Bool,
        unconfirmed: Int = 0,
        traceparentAutoDisabled: Bool = false
    ) {
        self.batchID = batchID
        self.accepted = accepted
        self.statusOnly = statusOnly
        self.unconfirmed = unconfirmed
        self.traceparentAutoDisabled = traceparentAutoDisabled
    }
}

public enum RunTrigger: String, Sendable, Codable, Equatable, CaseIterable {
    case manual
    case observerQuery
    case bgAppRefresh
    case bgProcessing
    case shortcut
    case appForeground
    case widgetControl
    case launch
}

public struct RunEvent: Sendable, Equatable {
    public var runID: RunID
    public var outcomeKind: String
    public var detail: String
    public var trigger: RunTrigger
    public var samplesRead: Int
    public var samplesCommitted: Int
    public var samplesAcked: Int
    public var wallTimeEpoch: TimeInterval
    public var errorClass: String?
    public var projectedAtEpoch: TimeInterval?

    public init(
        runID: RunID,
        outcomeKind: String,
        detail: String,
        trigger: RunTrigger = .manual,
        samplesRead: Int = 0,
        samplesCommitted: Int = 0,
        samplesAcked: Int = 0,
        wallTimeEpoch: TimeInterval = 0,
        errorClass: String? = nil,
        projectedAtEpoch: TimeInterval? = nil
    ) {
        self.runID = runID
        self.outcomeKind = outcomeKind
        self.detail = detail
        self.trigger = trigger
        self.samplesRead = samplesRead
        self.samplesCommitted = samplesCommitted
        self.samplesAcked = samplesAcked
        self.wallTimeEpoch = wallTimeEpoch
        self.errorClass = errorClass
        self.projectedAtEpoch = projectedAtEpoch
    }

    public var isProblemOutcome: Bool {
        switch outcomeKind {
        case "success", "successNothingDue":
            false
        default:
            true
        }
    }
}

/// Newest problems first, then remaining runs newest-first. Caps the on-device history list.
public enum RunHistory {
    public static func problemsFirst(_ events: [RunEvent], limit: Int = 50) -> [RunEvent] {
        let ranked = events.enumerated().sorted { lhs, rhs in
            if lhs.element.isProblemOutcome != rhs.element.isProblemOutcome {
                return lhs.element.isProblemOutcome
            }
            return lhs.offset > rhs.offset
        }
        return Array(ranked.prefix(limit).map(\.element))
    }
}

public struct EgressEntry: Sendable, Equatable {
    public var destination: String
    public var sampleCount: Int
    public var outcomeKind: String
    public var byteCount: Int
    public var detail: String
    public var wallTimeEpoch: TimeInterval
    public var sequence: Int
    public var previousHash: String
    public var entryHash: String

    public init(
        destination: String,
        sampleCount: Int,
        outcomeKind: String,
        byteCount: Int = 0,
        detail: String = "",
        wallTimeEpoch: TimeInterval = 0,
        sequence: Int = 0,
        previousHash: String = "",
        entryHash: String = ""
    ) {
        self.destination = destination
        self.sampleCount = sampleCount
        self.outcomeKind = outcomeKind
        self.byteCount = byteCount
        self.detail = detail
        self.wallTimeEpoch = wallTimeEpoch
        self.sequence = sequence
        self.previousHash = previousHash
        self.entryHash = entryHash
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
    func loadBackfillCheckpoint(jobID: String) throws -> Data?
    func upsertBackfillCheckpoint(jobID: String, bytes: Data) throws
    func enqueuePending(_ batch: PendingBatch) throws
    func commitBatch(_ batch: PendingBatch, advancing: CursorAdvance) throws
    /// Batches survive process death until a receipt confirms every expected record.
    func pendingBatches() throws -> [PendingBatch]
    func queuedBytes() throws -> Int
    func loadGaps() throws -> [GapRecord]
    func evict(_ batchID: BatchID, recording: GapRecord) throws
    func recordDelivery(_ receipt: DeliveryReceipt) throws
    func appendJournal(_ event: RunEvent) throws
    func unprojectedJournal(limit: Int) throws -> [RunEvent]
    func markJournalProjected(runIDs: [RunID], atEpoch: TimeInterval) throws
    func appendLedger(_ entry: EgressEntry) throws
    func loadLedger() throws -> [EgressEntry]
    func upsertCensus(_ row: CensusRow) throws
    func loadCensus(metric: MetricID, day: String) throws -> CensusRow?
    func markDirty(metric: MetricID, day: String) throws
    func dirtyDays(metric: MetricID) throws -> [String]
    func clearDirty(metric: MetricID, day: String) throws
    func upsertEmittedIndex(_ row: EmittedIndexRow) throws
    func loadEmittedIndex(uuid: String) throws -> EmittedIndexRow?
    func removeEmittedIndex(uuid: String) throws
    func loadEmittedIndex(metric: MetricID, day: String) throws -> [EmittedIndexRow]
    /// R-69: the latest day this metric has actually been emitted for, so the browser
    /// can say what was sent from the export's own record rather than from a guess.
    func latestEmittedDay(metric: MetricID) throws -> String?
    func loadAggregateEmitSeq(bucketKey: String) throws -> Int?
    func upsertAggregateEmitSeq(bucketKey: String, emitSeq: Int) throws
    func loadJournal() throws -> [RunEvent]
    func loadTypeStatus(metric: MetricID) throws -> TypeStatus?
    func upsertTypeStatus(_ status: TypeStatus) throws
    func loadAnchorHold(metric: MetricID) throws -> AnchorHold?
    func upsertAnchorHold(_ hold: AnchorHold) throws
    func clearAnchorHold(metric: MetricID) throws
    func loadAnchorHolds() throws -> [AnchorHold]
    func purgeMetricState(metric: MetricID) throws
    /// Clears every table. Returns pending payload paths to unlink after COMMIT (R-43).
    func wipe(atEpoch: TimeInterval) throws -> [String]
}

public protocol StateStore: Sendable {
    /// Synchronous body: no suspension point inside the transaction.
    func transact<T: Sendable>(
        _ body: (any StateTransaction) throws -> T
    ) async throws -> T
    /// R-43: drop durable state. Payload files named by wipe() are unlinked after COMMIT.
    func wipe(atEpoch: TimeInterval) async throws
}

public protocol StatisticsSource: Sendable {
    /// P1D bucket from HealthKit statistics. Unimplemented until the HealthKit wedge.
    func dailyBucket(metric: MetricID, day: String) async throws -> AggregateRecord?
}

public protocol SampleSource: Sendable {
    func page(metric: MetricID, afterAnchor: Data?) async throws -> SamplePage
}

/// Date-ranged observations for R-08. Does not use the HealthKit anchored query.
public protocol DayObservationSource: Sendable {
    func samples(metric: MetricID, day: String) async throws -> [SampleRecord]
}

/// A date-ranged source that can discover the complete day span available for a metric.
public protocol BoundedDayObservationSource: DayObservationSource {
    func availableDayRange(metric: MetricID) async throws -> ClosedRange<String>?
}

/// Classified destination failure. Call sites must not invent a `RunOutcome`.
public enum DestinationSendError: Error, Sendable, Equatable {
    case localNetworkDenied
    case destinationUnreachable
    case cancelledBySystem
    case budgetExhausted
    case deviceLocked
    case internalFault(String)

    public var errorClass: ErrorClass {
        switch self {
        case .localNetworkDenied: .localNetworkDenied
        case .destinationUnreachable: .destinationUnreachable
        case .cancelledBySystem: .cancelledBySystem
        case .budgetExhausted: .budgetExhausted
        case .deviceLocked: .deviceLocked
        case .internalFault: .internalFault
        }
    }
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
        case queueEvicted
        case queueExpired
        case exportOverdue
        case healthAccessRevoked
        case anchorInvalidated
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

/// Outcome of a notify attempt. Call sites cannot suppress; the OS can still deny (R-40).
public enum NoticeDelivery: Sendable, Equatable {
    case posted
    case skippedAuthorizationDenied
    case notRequired
}

/// R-41: no suppression parameter exists, so no call site can decline to notify.
public protocol UserNotifier: Sendable {
    func notify(_ notice: UserNotice) async throws -> NoticeDelivery
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
