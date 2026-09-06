import CoreDomain
import EnginePorts
import Foundation

/// R-44: per-type queue purge indexed by metric. Clock starts at observation or explicit stop,
/// never at an undetectable HealthKit revocation and never from an empty read (R-60).
public enum TypePurge {
    public static let observationSLA: TimeInterval = 60

    public static func due(
        previous: AuthGrant,
        observed: AuthGrant,
        explicitStop: Bool
    ) -> Bool {
        if explicitStop { return true }
        return previous == .granted && observed == .denied
    }

    @discardableResult
    public static func apply(
        metric: MetricID,
        reason: String,
        destination: String,
        atEpoch: TimeInterval,
        on tx: any StateTransaction
    ) throws -> [String] {
        let victims = try tx.pendingBatches().filter { $0.metric == metric }
        for victim in victims {
            try tx.evict(
                victim.id,
                recording: GapRecord(
                    batchID: victim.id,
                    rangeDescription: "purged_by_revocation:\(reason)"
                )
            )
        }
        try tx.upsertTypeStatus(
            TypeStatus(metric: metric, disabled: true, reason: reason)
        )
        try tx.appendLedger(
            EgressEntry(
                destination: destination,
                sampleCount: 0,
                outcomeKind: "types_purged",
                wallTimeEpoch: atEpoch
            )
        )
        try tx.appendJournal(
            RunEvent(
                runID: RunID(rawValue: "purge-\(metric.rawValue)"),
                outcomeKind: "purged",
                detail: reason,
                trigger: .manual
            )
        )
        return victims.map(\.payloadURL)
    }
}

extension StateStore {
    public func purgeType(
        metric: MetricID,
        reason: String,
        destination: String,
        atEpoch: TimeInterval
    ) async throws {
        let urls = try await transact { tx in
            try TypePurge.apply(
                metric: metric,
                reason: reason,
                destination: destination,
                atEpoch: atEpoch,
                on: tx
            )
        }
        for path in urls {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
