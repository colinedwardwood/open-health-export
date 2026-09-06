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

    public init(
        key: RecordKey,
        metric: MetricID,
        start: String,
        end: String,
        timeZoneOffsetMinutes: Int,
        timeZoneSource: TimeZoneSource,
        value: Double,
        unit: CanonicalUnit,
        observedAt: String
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
