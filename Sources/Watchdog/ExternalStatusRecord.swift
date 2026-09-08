import CoreDomain
import EnginePorts
import Foundation

/// R-27 status signal written beside user-owned exports. It contains no health values.
public struct ExternalStatusRecord: Sendable, Equatable, Codable {
    public var schemaVersion: Int
    public var exporterInstanceID: String
    public var destinationID: String
    public var runSeq: Int
    public var runAt: String
    public var lastSuccessAt: String?
    public var lastConfirmedAckAt: String?
    public var ageSeconds: TimeInterval?
    public var outcome: String
    public var attribution: String
    public var attributionConfidence: String
    public var errorClass: String
    public var samplesRead: Int
    public var samplesSent: Int
    public var samplesAcked: Int
    public var samplesRejected: Int
    public var cadenceClass: String?
    public var staleThresholdSeconds: TimeInterval?
    public var overdueThresholdSeconds: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case exporterInstanceID = "exporter_instance_id"
        case destinationID = "destination_id"
        case runSeq = "run_seq"
        case runAt = "run_at"
        case lastSuccessAt = "last_success_at"
        case lastConfirmedAckAt = "last_confirmed_ack_at"
        case ageSeconds = "age_seconds"
        case outcome
        case attribution
        case attributionConfidence = "attribution_confidence"
        case errorClass = "error_class"
        case samplesRead = "samples_read"
        case samplesSent = "samples_sent"
        case samplesAcked = "samples_acked"
        case samplesRejected = "samples_rejected"
        case cadenceClass = "cadence_class"
        case staleThresholdSeconds = "stale_threshold_s"
        case overdueThresholdSeconds = "overdue_threshold_s"
    }

    public static func next(
        prior: ExternalStatusRecord?,
        exporterInstanceID: String,
        destinationID: String,
        runAt: String,
        runAtEpoch: TimeInterval,
        outcome: RunOutcome,
        tally: RunTally,
        trigger: RunTrigger,
        staleThresholdSeconds: TimeInterval? = nil,
        overdueThresholdSeconds: TimeInterval? = nil
    ) -> ExternalStatusRecord {
        let succeeded = outcome.kind == .success || outcome.kind == .successNothingDue
        let confirmed = outcome.ackEvidence == .receiptFull
        let lastSuccessAt = succeeded ? runAt : prior?.lastSuccessAt
        let lastSuccessEpoch = succeeded
            ? runAtEpoch
            : prior?.lastSuccessAt.flatMap { ISO8601DateFormatter().date(from: $0)?.timeIntervalSince1970 }
        return ExternalStatusRecord(
            schemaVersion: 1,
            exporterInstanceID: exporterInstanceID,
            destinationID: destinationID,
            runSeq: (prior?.runSeq ?? 0) + 1,
            runAt: runAt,
            lastSuccessAt: lastSuccessAt,
            lastConfirmedAckAt: confirmed ? runAt : prior?.lastConfirmedAckAt,
            ageSeconds: lastSuccessEpoch.map { max(0, runAtEpoch - $0) },
            outcome: outcome.kind.rawValue,
            attribution: attribution(for: trigger),
            attributionConfidence: "evidenced",
            errorClass: tally.terminalError.rawValue,
            samplesRead: tally.read,
            samplesSent: tally.committed,
            samplesAcked: tally.acked,
            samplesRejected: max(0, tally.committed - tally.acked - tally.unconfirmed),
            cadenceClass: nil,
            staleThresholdSeconds: staleThresholdSeconds,
            overdueThresholdSeconds: overdueThresholdSeconds
        )
    }

    private static func attribution(for trigger: RunTrigger) -> String {
        switch trigger {
        case .observerQuery, .bgAppRefresh, .bgProcessing:
            "scheduling"
        case .manual, .shortcut, .widgetControl, .appForeground, .launch:
            "execution"
        }
    }
}

public enum ExternalStatusRecordFile {
    public static func read(from url: URL) throws -> ExternalStatusRecord {
        try JSONDecoder().decode(ExternalStatusRecord.self, from: Data(contentsOf: url))
    }

    public static func write(_ record: ExternalStatusRecord, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(record).write(to: url, options: .atomic)
    }
}
