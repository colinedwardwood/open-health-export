import CoreDomain
import EnginePorts

public enum ReconcileRepair: Sendable, Equatable {
    case reemitDay
    case emitAbsenceTombstones([TombstoneRecord])
}

public struct ReconcileDayPlan: Sendable, Equatable {
    public var metric: MetricID
    public var day: String
    public var outcome: ReconcileCellOutcome
    public var repairs: [ReconcileRepair]

    public init(
        metric: MetricID,
        day: String,
        outcome: ReconcileCellOutcome,
        repairs: [ReconcileRepair]
    ) {
        self.metric = metric
        self.day = day
        self.outcome = outcome
        self.repairs = repairs
    }

    public var isClean: Bool { outcome == .identical && repairs.isEmpty }
}

/// Fixture-friendly R-08 planner: classify one (metric, day) cell and name the repairs.
/// Does not touch HealthKit or the store; the caller supplies stored census, index, and observed samples.
public enum ReconcilePlanner {
    public static func planDay(
        metric: MetricID,
        day: String,
        stored: CensusRow?,
        indexed: [EmittedIndexRow],
        observed: [SampleRecord]
    ) -> ReconcileDayPlan {
        let observedUUIDs = observed.map(\.key.uuid)
        let observedFold = ReconcileCompare.fold(uuids: observedUUIDs)
        let storedRow = stored ?? CensusRow(
            metric: metric,
            day: day,
            sampleCount: 0,
            digest: "0"
        )
        let outcome = ReconcileCompare.compare(stored: storedRow, observed: observedFold)
        var repairs: [ReconcileRepair] = []
        switch outcome {
        case .identical:
            break
        case .countGreater, .digestMismatch:
            repairs.append(.reemitDay)
        case .countSmaller:
            let tombs = ReconcileCompare.tombstonesForAbsence(
                indexed: indexed,
                observedUUIDs: Set(observedUUIDs),
                metric: metric
            )
            if !tombs.isEmpty {
                repairs.append(.emitAbsenceTombstones(tombs))
            }
            // Also re-emit so aggregates catch up after the deletion set-diff.
            repairs.append(.reemitDay)
        }
        return ReconcileDayPlan(metric: metric, day: day, outcome: outcome, repairs: repairs)
    }

    /// Default trailing window (R-08): seven ISO calendar days ending at `throughDay` inclusive.
    public static func trailingDays(throughDay: String, count: Int = 7) -> [String] {
        guard count > 0 else { return [] }
        let parts = throughDay.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return [throughDay] }
        var y = parts[0], m = parts[1], d = parts[2]
        var days: [String] = []
        for _ in 0..<count {
            days.append(String(format: "%04d-%02d-%02d", y, m, d))
            d -= 1
            if d == 0 {
                m -= 1
                if m == 0 {
                    m = 12
                    y -= 1
                }
                d = daysInMonth(year: y, month: m)
            }
        }
        return days.reversed()
    }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
            return leap ? 29 : 28
        default: return 30
        }
    }
}
