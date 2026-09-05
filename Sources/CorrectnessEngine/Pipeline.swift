import CoreDomain
import EnginePorts
import MetricCatalog

public struct Pipeline {
    public init() {}

    public func outcome(for tally: RunTally) -> RunOutcome {
        RunOutcome.derive(from: tally)
    }

    public var hkStatisticsExceptions: [MetricID] {
        MetricCatalog.hkStatisticsExceptions
    }
}
