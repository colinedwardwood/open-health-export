// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

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
