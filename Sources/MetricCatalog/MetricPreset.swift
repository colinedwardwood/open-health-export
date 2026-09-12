// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation

public struct MetricPreset: Sendable, Equatable {
    public var id: String
    public var version: Int
    public var metrics: [MetricDeclaration]

    public init(id: String, version: Int, metrics: [MetricDeclaration]) {
        self.id = id
        self.version = version
        self.metrics = metrics
    }

    public var metricIDs: Set<MetricID> {
        Set(metrics.map(\.id))
    }

    public static func == (lhs: MetricPreset, rhs: MetricPreset) -> Bool {
        lhs.id == rhs.id && lhs.version == rhs.version && lhs.metricIDs == rhs.metricIDs
    }
}

public struct MetricPresetDiff: Sendable, Equatable {
    public var added: Set<MetricID>
    public var removed: Set<MetricID>

    public init(added: Set<MetricID>, removed: Set<MetricID>) {
        self.added = added
        self.removed = removed
    }

    public static func between(from: MetricPreset, to: MetricPreset) -> MetricPresetDiff {
        MetricPresetDiff(
            added: to.metricIDs.subtracting(from.metricIDs),
            removed: from.metricIDs.subtracting(to.metricIDs)
        )
    }

    public var summary: String {
        "This update adds \(Self.countPhrase(added.count)) and removes \(Self.countPhrase(removed.count)). Your current selection stays until you apply it."
    }

    private static func countPhrase(_ count: Int) -> String {
        count == 1 ? "1 type" : "\(count) types"
    }
}

/// UX-18: a newer preset version is offered as a diff. Selection does not change until accept.
public enum MetricPresetAdoption {
    public enum Action: Sendable, Equatable {
        case applyNow
        case offerDiff(MetricPresetDiff)
    }

    public static func nextAction(
        shipped: MetricPreset,
        appliedVersion: Int?,
        snapshots: [Int: MetricPreset]
    ) -> Action {
        guard let applied = appliedVersion, applied < shipped.version else {
            return .applyNow
        }
        let from = snapshots[applied] ?? MetricPreset(id: shipped.id, version: applied, metrics: [])
        return .offerDiff(.between(from: from, to: shipped))
    }
}

public enum CoreDailyPreset {
    public static let id = "coreDaily"
    public static let version = 1
    public static let applyLabel = "Use Core Daily"
    public static let reviewUpgradeLabel = "Review Core Daily update"
    public static let acceptUpgradeLabel = "Apply Core Daily update"
    public static let keepCurrentLabel = "Keep current types"

    public static var current: MetricPreset {
        MetricPreset(id: id, version: version, metrics: MetricCatalog.coreDaily)
    }

    public static var snapshots: [Int: MetricPreset] {
        [version: current]
    }
}
