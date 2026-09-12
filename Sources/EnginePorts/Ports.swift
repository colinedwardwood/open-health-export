// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

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

public enum QueueEvictionClass: String, Sendable, Equatable {
    case normal
    case pinned
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
    public var evictionClass: QueueEvictionClass

    public init(
        id: BatchID,
        payloadURL: String,
        expectedRecords: Int = 0,
        byteCount: Int = 0,
        metric: MetricID = MetricID(rawValue: ""),
        createdAtEpoch: TimeInterval? = nil,
        rangeStartDay: String? = nil,
        rangeEndDay: String? = nil,
        evictionClass: QueueEvictionClass = .normal
    ) {
        self.id = id
        self.payloadURL = payloadURL
        self.expectedRecords = expectedRecords
        self.byteCount = byteCount
        self.metric = metric
        self.createdAtEpoch = createdAtEpoch
        self.rangeStartDay = rangeStartDay
        self.rangeEndDay = rangeEndDay
        self.evictionClass = evictionClass
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
    public static let minimumPageLimit = 50

    /// UX-29: shortening the owned export window reduces the next HealthKit page,
    /// which is what a 413 response is asking for. Older undelivered samples stay queued.
    /// Thermal ≥ serious also halves the page (reliability thermal policy).
    public static func pageLimit(windowHours: Int, thermalHalved: Bool = false) -> Int {
        let hours = max(1, windowHours)
        let base = max(minimumPageLimit, defaultPageLimit * hours / 24)
        guard thermalHalved else { return base }
        return max(minimumPageLimit, base / 2)
    }
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
    public var expectedRecords: Int

    public init(
        batchID: BatchID,
        rangeDescription: String,
        metric: MetricID = MetricID(rawValue: ""),
        rangeStartDay: String? = nil,
        rangeEndDay: String? = nil,
        expectedRecords: Int = 0
    ) {
        self.batchID = batchID
        self.rangeDescription = rangeDescription
        self.metric = metric
        self.rangeStartDay = rangeStartDay
        self.rangeEndDay = rangeEndDay
        self.expectedRecords = expectedRecords
    }

    /// Queue eviction, TTL expiry, and type purge all copy the pending batch's
    /// count and day extent so `delivered ∪ gap ⊇ read` can be checked later.
    public init(evicting batch: PendingBatch, rangeDescription: String) {
        self.init(
            batchID: batch.id,
            rangeDescription: rangeDescription,
            metric: batch.metric,
            rangeStartDay: batch.rangeStartDay,
            rangeEndDay: batch.rangeEndDay,
            expectedRecords: batch.expectedRecords
        )
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

public struct RunStepTiming: Sendable, Equatable, Codable {
    public var name: String
    public var durationMillis: Int

    public init(name: String, durationMillis: Int) {
        self.name = name
        self.durationMillis = durationMillis
    }
}

/// UX-40 fields that sit beside the journal row. Exact payload bytes stay on disk
/// (`payloadPath`); SQLite keeps a redacted summary and a digest.
public struct RunHistoryFacts: Sendable, Equatable, Codable {
    public var destinationID: String?
    public var metric: String?
    public var windowStartDay: String?
    public var windowEndDay: String?
    public var byteCount: Int
    public var durationMillis: Int
    public var stepTimings: [RunStepTiming]
    public var payloadSHA256: String?
    public var redactedPayload: String?
    public var payloadPath: String?

    public static let empty = RunHistoryFacts()

    public init(
        destinationID: String? = nil,
        metric: String? = nil,
        windowStartDay: String? = nil,
        windowEndDay: String? = nil,
        byteCount: Int = 0,
        durationMillis: Int = 0,
        stepTimings: [RunStepTiming] = [],
        payloadSHA256: String? = nil,
        redactedPayload: String? = nil,
        payloadPath: String? = nil
    ) {
        self.destinationID = destinationID
        self.metric = metric
        self.windowStartDay = windowStartDay
        self.windowEndDay = windowEndDay
        self.byteCount = byteCount
        self.durationMillis = durationMillis
        self.stepTimings = stepTimings
        self.payloadSHA256 = payloadSHA256
        self.redactedPayload = redactedPayload
        self.payloadPath = payloadPath
    }

    public var isEmpty: Bool { self == .empty }

    public func jsonString() -> String? {
        guard !isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(_ json: String?) -> RunHistoryFacts {
        guard let json, let data = json.data(using: .utf8),
              let facts = try? JSONDecoder().decode(RunHistoryFacts.self, from: data)
        else {
            return .empty
        }
        return facts
    }
}

/// A non-terminal export still on disk. Next launch infers interruption from this row
/// (UX-26 / architecture run machine); the killed process cannot write the outcome.
public struct OpenRun: Sendable, Equatable {
    public var destinationID: String
    public var metric: MetricID
    public var phase: String
    public var trigger: RunTrigger
    public var startedAtEpoch: TimeInterval
    public var samplesRead: Int
    public var samplesCommitted: Int
    public var samplesAcked: Int

    public init(
        destinationID: String,
        metric: MetricID,
        phase: String,
        trigger: RunTrigger,
        startedAtEpoch: TimeInterval,
        samplesRead: Int = 0,
        samplesCommitted: Int = 0,
        samplesAcked: Int = 0
    ) {
        self.destinationID = destinationID
        self.metric = metric
        self.phase = phase
        self.trigger = trigger
        self.startedAtEpoch = startedAtEpoch
        self.samplesRead = samplesRead
        self.samplesCommitted = samplesCommitted
        self.samplesAcked = samplesAcked
    }
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
    public var facts: RunHistoryFacts

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
        projectedAtEpoch: TimeInterval? = nil,
        facts: RunHistoryFacts = .empty
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
        self.facts = facts
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
    /// Sum of `accepted` on stored receipts. Used with gaps and pending for
    /// `delivered ∪ gap ⊇ read`.
    func deliveredAccepted() throws -> Int
    func appendJournal(_ event: RunEvent) throws
    func upsertOpenRun(_ run: OpenRun) throws
    func loadOpenRuns() throws -> [OpenRun]
    func closeOpenRun(destinationID: String, metric: MetricID) throws
    func appendFreshnessLatency(_ observation: RunFreshnessLatency) throws
    func loadFreshnessLatencies(
        destinationID: String,
        freshnessClass: FreshnessClass
    ) throws -> [RunFreshnessLatency]
    /// OBS-02: drop runs older than `sinceEpoch`, then anything beyond the most recent
    /// `maximumRuns`. Returns how many rows went, so a caller can assert it happened.
    func pruneJournal(sinceEpoch: TimeInterval, maximumRuns: Int) throws -> Int
    func unprojectedJournal(limit: Int) throws -> [RunEvent]
    func markJournalProjected(runIDs: [RunID], atEpoch: TimeInterval) throws
    func appendLedger(_ entry: EgressEntry) throws
    func loadLedger() throws -> [EgressEntry]
    func upsertCensus(_ row: CensusRow) throws
    func loadCensus(metric: MetricID, day: String) throws -> CensusRow?
    func loadCensusDays(metric: MetricID) throws -> [String]
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
    /// ADR-HK-7: row count for the 48 MB oldest-day cap (counted at ~40 bytes/row).
    func emittedIndexRowCount() throws -> Int
    func oldestEvictableEmittedDay(excluding metrics: Set<MetricID>) throws -> String?
    func emittedIndexMetrics(day: String, excluding metrics: Set<MetricID>) throws -> [MetricID]
    func removeEmittedIndex(day: String, excluding metrics: Set<MetricID>) throws
    func emittedIndexHorizonDay(excluding metrics: Set<MetricID>) throws -> String?
    func loadIndexHorizonDay() throws -> String?
    func upsertIndexHorizonDay(_ day: String) throws
    func loadVerifiedThroughDay(metric: MetricID) throws -> String?
    func clampVerifiedThroughDay(metric: MetricID, horizonDay: String) throws
    func loadAggregateEmitSeq(bucketKey: String) throws -> Int?
    func upsertAggregateEmitSeq(bucketKey: String, emitSeq: Int) throws
    func loadJournal() throws -> [RunEvent]
    func loadTypeStatus(metric: MetricID) throws -> TypeStatus?
    func upsertTypeStatus(_ status: TypeStatus) throws
    func loadAnchorHold(metric: MetricID) throws -> AnchorHold?
    func upsertAnchorHold(_ hold: AnchorHold) throws
    func clearAnchorHold(metric: MetricID) throws
    func loadAnchorHolds() throws -> [AnchorHold]
    /// SEC-16: `nil` is "no scope was ever stored", which the app migration must be able
    /// to tell apart from a stored scope that happens to grant nothing.
    func loadDestinationScope(destinationID: String) throws -> DestinationExportScope?
    func upsertDestinationScope(_ scope: DestinationExportScope) throws
    /// Per-sink breaker blob (`BreakerSnapshot` JSON). Catch-up reads this so a
    /// one-tap re-export into a still-broken destination cannot evict live data.
    func loadDestinationBreaker(destinationID: String) throws -> Data?
    func upsertDestinationBreaker(destinationID: String, bytes: Data) throws
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

/// On-demand HealthKit characteristic read. Never an anchored sample query (HK-30).
public protocol CharacteristicSource: Sendable {
    func read(metric: MetricID, observedAt: String) async throws -> CharacteristicRecord?
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
public enum DestinationSendError: Error, Sendable, Equatable, LocalizedError {
    case localNetworkDenied
    case destinationUnreachable
    case cancelledBySystem
    case budgetExhausted
    case deviceLocked
    case healthDataRestricted
    case lowPowerMode
    case awaitingUnmetered
    case internalFault(String)

    public var errorClass: ErrorClass {
        switch self {
        case .localNetworkDenied: .localNetworkDenied
        case .destinationUnreachable: .destinationUnreachable
        case .cancelledBySystem: .cancelledBySystem
        case .budgetExhausted: .budgetExhausted
        case .deviceLocked: .deviceLocked
        case .healthDataRestricted: .healthDataRestricted
        case .lowPowerMode: .lowPowerMode
        case .awaitingUnmetered: .awaitingUnmetered
        case .internalFault: .internalFault
        }
    }

    public var errorDescription: String? {
        let copy = ErrorClassManifest.record(for: errorClass).userFacingCopy
        return copy.isEmpty ? nil : copy
    }
}

public enum HTTPTransferSchedule: String, Sendable, Equatable {
    /// HK-18 / ADR-R5: first delivery attempt. Freshness matters.
    case immediate
    /// ADR-R5: later-wake retries. The OS may delay the transfer.
    case discretionaryRetry

    @TaskLocal public static var current: HTTPTransferSchedule = .immediate
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
        case queueApproachingLoss
        case exportFailed
        case exportOverdue
        case healthAccessRevoked
        case anchorInvalidated
        case exportInterrupted
    }

    public var kind: Kind
    public var destinationID: String
    public var destination: String
    public var fingerprint: String?
    public var previousFingerprint: String?
    /// Closed error class for UX-32 deep links. Never interpolated into Lock Screen copy.
    public var errorClass: String?
    /// Wall time the interrupted export started. Copy interpolates a clock; never a health value.
    public var startedAtEpoch: TimeInterval?

    public init(
        kind: Kind,
        destinationID: String? = nil,
        destination: String,
        fingerprint: String? = nil,
        previousFingerprint: String? = nil,
        errorClass: String? = nil,
        startedAtEpoch: TimeInterval? = nil
    ) {
        self.kind = kind
        self.destinationID = destinationID ?? destination
        self.destination = destination
        self.fingerprint = fingerprint
        self.previousFingerprint = previousFingerprint
        self.errorClass = errorClass
        self.startedAtEpoch = startedAtEpoch
    }
}

/// Outcome of a notify attempt. Call sites cannot suppress; the OS can still deny (R-40).
public enum NoticeDelivery: Sendable, Equatable {
    case posted
    case skippedAuthorizationDenied
    case skippedRateLimited
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

public enum SecretStoreError: Error, Equatable, LocalizedError {
    case notFound
    case emptyHandle
    case emptySecret
    /// The Data Protection keychain refused the operation, most often because the
    /// host is unsigned (`errSecMissingEntitlement`). Callers must not treat this
    /// as a missing item.
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .notFound, .emptyHandle, .emptySecret:
            "The saved credential was not found."
        case .unavailable:
            "Saved credentials are unavailable on this device."
        }
    }
}

/// PSK and similar material. Implementations must not synchronise via iCloud (R-33).
public protocol SecretStore: Sendable {
    func store(_ bytes: [UInt8], handle: SecretHandle) async throws
    func load(_ handle: SecretHandle) async throws -> [UInt8]
    func delete(_ handle: SecretHandle) async throws
    /// R-43: wipe every secret this store owns, not one handle at a time.
    func deleteAll() async throws
}
