/// Domain values. No I/O, no Foundation calendars, no HealthKit.
public struct MetricID: Hashable, Sendable, Codable, RawRepresentable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct RecordKey: Hashable, Sendable, Codable {
    public var uuid: String
    public init(uuid: String) { self.uuid = uuid }
}

public struct BatchID: Hashable, Sendable, Codable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct RunID: Hashable, Sendable, Codable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct InstallationID: Hashable, Sendable, Codable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public enum SensitivityClass: String, Sendable, Codable, CaseIterable {
    case routine
    case sensitive
}

public enum TimeZoneSource: String, Sendable, Codable {
    case sampleMetadata
    case inferred
    case deviceCurrent
    case unknown
}

public struct CanonicalUnit: Hashable, Sendable, Codable {
    public var symbol: String
    public init(symbol: String) { self.symbol = symbol }
}

public struct SampleSourceIdentity: Sendable, Codable, Equatable {
    public var name: String
    public var bundleIdentifier: String?
    public var productType: String?

    public init(
        name: String,
        bundleIdentifier: String? = nil,
        productType: String? = nil
    ) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.productType = productType
    }
}

public struct SampleDevice: Sendable, Codable, Equatable {
    public var name: String?
    public var manufacturer: String?
    public var model: String?
    public var hardwareVersion: String?
    public var softwareVersion: String?

    public init(
        name: String? = nil,
        manufacturer: String? = nil,
        model: String? = nil,
        hardwareVersion: String? = nil,
        softwareVersion: String? = nil
    ) {
        self.name = name
        self.manufacturer = manufacturer
        self.model = model
        self.hardwareVersion = hardwareVersion
        self.softwareVersion = softwareVersion
    }
}

public struct SampleRecord: Sendable, Codable, Equatable {
    public var key: RecordKey
    public var metric: MetricID
    public var start: String
    public var end: String
    public var timeZoneOffsetMinutes: Int
    public var timeZoneSource: TimeZoneSource
    public var value: Double
    public var unit: CanonicalUnit
    public var observedAt: String
    public var source: SampleSourceIdentity?
    public var device: SampleDevice?
    public var wasUserEntered: Bool?

    public init(
        key: RecordKey,
        metric: MetricID,
        start: String,
        end: String,
        timeZoneOffsetMinutes: Int,
        timeZoneSource: TimeZoneSource,
        value: Double,
        unit: CanonicalUnit,
        observedAt: String,
        source: SampleSourceIdentity? = nil,
        device: SampleDevice? = nil,
        wasUserEntered: Bool? = nil
    ) {
        self.key = key
        self.metric = metric
        self.start = start
        self.end = end
        self.timeZoneOffsetMinutes = timeZoneOffsetMinutes
        self.timeZoneSource = timeZoneSource
        self.value = value
        self.unit = unit
        self.observedAt = observedAt
        self.source = source
        self.device = device
        self.wasUserEntered = wasUserEntered
    }
}

public struct CategoryRecord: Sendable, Codable, Equatable {
    public var key: RecordKey
    public var metric: MetricID
    public var healthKitIdentifier: String
    public var start: String
    public var end: String
    public var timeZoneOffsetMinutes: Int
    public var timeZoneSource: TimeZoneSource
    public var categoryValue: Int
    public var categoryName: String
    public var durationSeconds: Double?
    public var observedAt: String
    public var source: SampleSourceIdentity?
    public var device: SampleDevice?
    public var wasUserEntered: Bool?

    public init(
        key: RecordKey,
        metric: MetricID,
        healthKitIdentifier: String,
        start: String,
        end: String,
        timeZoneOffsetMinutes: Int,
        timeZoneSource: TimeZoneSource,
        categoryValue: Int,
        categoryName: String,
        durationSeconds: Double? = nil,
        observedAt: String,
        source: SampleSourceIdentity? = nil,
        device: SampleDevice? = nil,
        wasUserEntered: Bool? = nil
    ) {
        self.key = key
        self.metric = metric
        self.healthKitIdentifier = healthKitIdentifier
        self.start = start
        self.end = end
        self.timeZoneOffsetMinutes = timeZoneOffsetMinutes
        self.timeZoneSource = timeZoneSource
        self.categoryValue = categoryValue
        self.categoryName = categoryName
        self.durationSeconds = durationSeconds
        self.observedAt = observedAt
        self.source = source
        self.device = device
        self.wasUserEntered = wasUserEntered
    }
}

public struct CorrelationComponent: Sendable, Codable, Equatable {
    public var key: RecordKey
    public var metric: MetricID
    public var healthKitIdentifier: String
    public var value: Double
    public var unit: CanonicalUnit

    public init(
        key: RecordKey,
        metric: MetricID,
        healthKitIdentifier: String,
        value: Double,
        unit: CanonicalUnit
    ) {
        self.key = key
        self.metric = metric
        self.healthKitIdentifier = healthKitIdentifier
        self.value = value
        self.unit = unit
    }
}

public struct CorrelationRecord: Sendable, Codable, Equatable {
    public var key: RecordKey
    public var metric: MetricID
    public var healthKitIdentifier: String
    public var correlationType: String
    public var start: String
    public var end: String
    public var timeZoneOffsetMinutes: Int
    public var timeZoneSource: TimeZoneSource
    public var components: [CorrelationComponent]
    public var observedAt: String
    public var source: SampleSourceIdentity?
    public var device: SampleDevice?
    public var wasUserEntered: Bool?

    public init(
        key: RecordKey,
        metric: MetricID,
        healthKitIdentifier: String,
        correlationType: String,
        start: String,
        end: String,
        timeZoneOffsetMinutes: Int,
        timeZoneSource: TimeZoneSource,
        components: [CorrelationComponent],
        observedAt: String,
        source: SampleSourceIdentity? = nil,
        device: SampleDevice? = nil,
        wasUserEntered: Bool? = nil
    ) {
        self.key = key
        self.metric = metric
        self.healthKitIdentifier = healthKitIdentifier
        self.correlationType = correlationType
        self.start = start
        self.end = end
        self.timeZoneOffsetMinutes = timeZoneOffsetMinutes
        self.timeZoneSource = timeZoneSource
        self.components = components
        self.observedAt = observedAt
        self.source = source
        self.device = device
        self.wasUserEntered = wasUserEntered
    }
}

public struct WorkoutTotal: Sendable, Codable, Equatable {
    public var value: Double
    public var unit: CanonicalUnit
    public var statistic: AggregateStatistic

    public init(value: Double, unit: CanonicalUnit, statistic: AggregateStatistic) {
        self.value = value
        self.unit = unit
        self.statistic = statistic
    }
}

public struct WorkoutEventRecord: Sendable, Codable, Equatable {
    public var timestamp: String
    public var type: String
    public var durationSeconds: Double

    public init(timestamp: String, type: String, durationSeconds: Double) {
        self.timestamp = timestamp
        self.type = type
        self.durationSeconds = durationSeconds
    }
}

public struct WorkoutRecord: Sendable, Codable, Equatable {
    public var key: RecordKey
    public var metric: MetricID
    public var activityType: String
    public var activityTypeRaw: Int
    public var start: String
    public var end: String
    public var timeZoneOffsetMinutes: Int
    public var timeZoneSource: TimeZoneSource
    public var durationSeconds: Double
    public var isIndoor: Bool?
    public var totals: [String: WorkoutTotal]
    public var events: [WorkoutEventRecord]
    public var hasRoute: Bool
    public var seriesIncluded: [String]
    public var observedAt: String
    public var source: SampleSourceIdentity?
    public var device: SampleDevice?
    public var wasUserEntered: Bool?

    public init(
        key: RecordKey,
        metric: MetricID = MetricID(rawValue: "workout"),
        activityType: String,
        activityTypeRaw: Int,
        start: String,
        end: String,
        timeZoneOffsetMinutes: Int,
        timeZoneSource: TimeZoneSource,
        durationSeconds: Double,
        isIndoor: Bool? = nil,
        totals: [String: WorkoutTotal] = [:],
        events: [WorkoutEventRecord] = [],
        hasRoute: Bool,
        seriesIncluded: [String] = [],
        observedAt: String,
        source: SampleSourceIdentity? = nil,
        device: SampleDevice? = nil,
        wasUserEntered: Bool? = nil
    ) {
        self.key = key
        self.metric = metric
        self.activityType = activityType
        self.activityTypeRaw = activityTypeRaw
        self.start = start
        self.end = end
        self.timeZoneOffsetMinutes = timeZoneOffsetMinutes
        self.timeZoneSource = timeZoneSource
        self.durationSeconds = durationSeconds
        self.isIndoor = isIndoor
        self.totals = totals
        self.events = events
        self.hasRoute = hasRoute
        self.seriesIncluded = seriesIncluded
        self.observedAt = observedAt
        self.source = source
        self.device = device
        self.wasUserEntered = wasUserEntered
    }
}

public struct TombstoneRecord: Sendable, Codable, Equatable {
    public var key: RecordKey
    public var metric: MetricID
    public init(key: RecordKey, metric: MetricID) {
        self.key = key
        self.metric = metric
    }
}

public enum AggregateStatistic: String, Sendable, Codable, Equatable {
    case sum
    case mean
    case min
    case max
    case count
}

public enum AggregateComputation: String, Sendable, Codable, Equatable {
    case healthKitStatisticsCollectionQuery
    case healthKitStatisticsQuery
    case localSampleFold
}

public enum AggregateSourceScope: String, Sendable, Codable, Equatable {
    case all
    case preferred
    case single
}

public enum AggregateBucketState: String, Sendable, Codable, Equatable {
    case open
    case final
    case revised
}

public struct AggregateRecord: Sendable, Codable, Equatable {
    public var bucketKey: String
    public var metric: MetricID
    public var statistic: AggregateStatistic
    public var computation: AggregateComputation
    public var sourceScope: AggregateSourceScope
    public var granularity: String
    public var bucketStart: String
    public var bucketEnd: String
    public var bucketDurationSeconds: Int
    public var timeZoneIdentifier: String
    public var localStart: String
    public var value: Double?
    public var unit: CanonicalUnit
    public var sampleCount: Int
    public var state: AggregateBucketState
    public var emitSeq: Int
    public var computedAt: String
    public var observedAt: String
    public var supersedes: Int?

    public init(
        bucketKey: String,
        metric: MetricID,
        statistic: AggregateStatistic,
        computation: AggregateComputation,
        sourceScope: AggregateSourceScope,
        granularity: String,
        bucketStart: String,
        bucketEnd: String,
        bucketDurationSeconds: Int,
        timeZoneIdentifier: String,
        localStart: String,
        value: Double?,
        unit: CanonicalUnit,
        sampleCount: Int,
        state: AggregateBucketState,
        emitSeq: Int,
        computedAt: String,
        observedAt: String,
        supersedes: Int? = nil
    ) {
        self.bucketKey = bucketKey
        self.metric = metric
        self.statistic = statistic
        self.computation = computation
        self.sourceScope = sourceScope
        self.granularity = granularity
        self.bucketStart = bucketStart
        self.bucketEnd = bucketEnd
        self.bucketDurationSeconds = bucketDurationSeconds
        self.timeZoneIdentifier = timeZoneIdentifier
        self.localStart = localStart
        self.value = value
        self.unit = unit
        self.sampleCount = sampleCount
        self.state = state
        self.emitSeq = emitSeq
        self.computedAt = computedAt
        self.observedAt = observedAt
        self.supersedes = supersedes
    }
}

public enum ErrorClass: String, Sendable, Codable, CaseIterable {
    case none
    case deviceLocked
    case localNetworkDenied
    case destinationUnreachable
    case budgetExhausted
    case cancelledBySystem
    case internalFault
}

public struct RunTally: Sendable, Equatable {
    public var read: Int
    public var committed: Int
    public var acked: Int
    public var unconfirmed: Int
    public var failed: Int
    public var terminalError: ErrorClass
    public var nothingDue: Bool
    public var ackEvidenceStatusOnly: Bool
    public var partialCause: String?

    public init(
        read: Int = 0,
        committed: Int = 0,
        acked: Int = 0,
        unconfirmed: Int = 0,
        failed: Int = 0,
        terminalError: ErrorClass = .none,
        nothingDue: Bool = false,
        ackEvidenceStatusOnly: Bool = false,
        partialCause: String? = nil
    ) {
        self.read = read
        self.committed = committed
        self.acked = acked
        self.unconfirmed = unconfirmed
        self.failed = failed
        self.terminalError = terminalError
        self.nothingDue = nothingDue
        self.ackEvidenceStatusOnly = ackEvidenceStatusOnly
        self.partialCause = partialCause
    }
}

/// Closed outcome set. Cases are not assigned at call sites — only `derive`.
public struct RunOutcome: Sendable, Equatable, CustomStringConvertible {
    public enum Kind: String, Sendable, CaseIterable {
        case success
        case successNothingDue
        case partial
        case unknownAck
        case failed
        case abandonedNoBudget
        case cancelledBySystem
        case blockedDeviceLocked
        case localNetworkDenied
    }

    public let kind: Kind
    public let partialCause: String?
    public let ackEvidence: AckEvidence

    public enum AckEvidence: String, Sendable, Equatable {
        case none
        case statusOnly
        case receiptFull
    }

    init(kind: Kind, partialCause: String? = nil, ackEvidence: AckEvidence = .none) {
        self.kind = kind
        self.partialCause = partialCause
        self.ackEvidence = ackEvidence
    }

    public var description: String { kind.rawValue }

    /// The only way to obtain a `RunOutcome`.
    public static func derive(from tally: RunTally) -> RunOutcome {
        if tally.terminalError == .deviceLocked {
            return RunOutcome(kind: .blockedDeviceLocked)
        }
        if tally.terminalError == .localNetworkDenied {
            return RunOutcome(kind: .localNetworkDenied)
        }
        if tally.terminalError == .budgetExhausted {
            return RunOutcome(kind: .abandonedNoBudget)
        }
        if tally.terminalError == .cancelledBySystem {
            return RunOutcome(kind: .cancelledBySystem)
        }
        if tally.terminalError == .destinationUnreachable || tally.terminalError == .internalFault {
            return RunOutcome(kind: .failed, partialCause: tally.partialCause)
        }
        if tally.nothingDue, tally.read == 0 {
            return RunOutcome(kind: .successNothingDue)
        }
        if tally.acked < tally.read {
            if tally.unconfirmed > 0, tally.acked == 0, tally.failed == 0 {
                return RunOutcome(kind: .unknownAck)
            }
            let cause = tally.partialCause ?? "unspecified"
            return RunOutcome(kind: .partial, partialCause: cause)
        }
        let evidence: AckEvidence = tally.ackEvidenceStatusOnly ? .statusOnly : .receiptFull
        return RunOutcome(kind: .success, ackEvidence: evidence)
    }
}
