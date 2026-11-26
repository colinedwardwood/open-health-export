// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import CoreDomain
import CorrectnessEngine
import Foundation

/// #61: history a destination was just granted and has never been sent. Cursors are
/// per type and shared by every destination, so a read never goes back for samples
/// older than the anchor. Widening a grant (an earlier start, a later end, a new
/// type, a new destination) therefore owes that destination a backfill.
public struct ScopeWidening: Sendable, Codable, Equatable {
    public var destinationID: String
    /// The types whose grant grew, sorted by identifier.
    public var metrics: [MetricID]
    /// The earliest instant the grant now reaches that it did not reach before.
    public var since: Date

    public init(destinationID: String, metrics: [MetricID], since: Date) {
        self.destinationID = destinationID
        self.metrics = metrics.sorted { $0.rawValue < $1.rawValue }
        self.since = since
    }

    /// What `new` reaches beyond `old`. Nil when nothing grew, or when `new` grants
    /// nothing yet. A missing or unconfigured `old` grants nothing, so everything in
    /// `new` is owed.
    public static func between(
        old: DestinationExportScope?,
        new: DestinationExportScope
    ) -> ScopeWidening? {
        guard new.isConfigured, let newStart = new.startInclusive else { return nil }
        let previous = old?.isConfigured == true ? old : nil
        var grown: [MetricID] = []
        var since: Date?
        for metric in new.metrics {
            guard let reached = addedStart(metric: metric, old: previous, new: new, newStart: newStart)
            else { continue }
            grown.append(metric)
            since = min(since ?? reached, reached)
        }
        guard let since, !grown.isEmpty else { return nil }
        return ScopeWidening(destinationID: new.destinationID, metrics: grown, since: since)
    }

    /// The start of the earliest slice of `metric` that `new` adds, if any.
    private static func addedStart(
        metric: MetricID,
        old: DestinationExportScope?,
        new: DestinationExportScope,
        newStart: Date
    ) -> Date? {
        guard let old, old.metrics.contains(metric), let oldStart = old.startInclusive else {
            return newStart
        }
        if newStart < oldStart { return newStart }
        // A later end (or none) exposes samples the old window excluded.
        guard let oldEnd = old.endExclusive else { return nil }
        if let newEnd = new.endExclusive, newEnd <= oldEnd { return nil }
        return oldEnd
    }

    /// Two owed backfills for one destination are one backfill reaching both.
    public func merged(with other: ScopeWidening) -> ScopeWidening {
        ScopeWidening(
            destinationID: destinationID,
            metrics: Array(Set(metrics).union(other.metrics)),
            since: min(since, other.since)
        )
    }

    /// Adds `widening` to `pending`, merging with that destination's earlier entry.
    public static func recording(_ widening: ScopeWidening, in pending: [ScopeWidening]) -> [ScopeWidening] {
        Dictionary((pending + [widening]).map { ($0.destinationID, $0) }) { $0.merged(with: $1) }
            .values.sorted { $0.destinationID < $1.destinationID }
    }

    /// Whether a saved backfill job must be dropped so a new one can span `owed`. A
    /// finished job is never run again, and one planned before the grant grew would
    /// resume without the new days, destinations or types.
    public static func supersedes(
        _ checkpoint: BackfillCheckpoint,
        owed: [ScopeWidening],
        planned: [String]
    ) -> Bool {
        let relevant = owed.filter { planned.contains($0.destinationID) }
        guard !relevant.isEmpty else { return false }
        let plan = checkpoint.plan
        let windowStart = ExportScopeGate.dayStartUTC(plan.windowStartDay)
        let covered = windowStart.map { windowStart in
            relevant.allSatisfy {
                plan.destinations.contains($0.destinationID)
                    && Set($0.metrics).isSubset(of: plan.metrics)
                    && $0.since >= windowStart
            }
        } ?? false
        guard covered else { return true }
        return checkpoint.isFinished
    }

    /// The destinations a backfill starting at `firstDay` has caught up, which is those
    /// that are owed nothing from before it.
    public static func settled(
        destinations: [String],
        owed: [ScopeWidening],
        firstDay: String
    ) -> [String] {
        guard let start = ExportScopeGate.dayStartUTC(firstDay) else { return [] }
        let behind = Set(owed.filter { $0.since < start }.map(\.destinationID))
        return destinations.filter { !behind.contains($0) }
    }

    /// What Status says while any destination is owed history.
    public static func statusCopy(_ pending: [ScopeWidening]) -> LocalizedCopy? {
        pending.isEmpty ? nil : LocalizedCopy(
            "Earlier health history is waiting to be sent. Open Settings and run a backfill."
        )
    }
}

/// Where owed backfills are kept between launches.
public protocol PendingBackfillStorage: Sendable {
    func pending() -> [ScopeWidening]
    func record(_ widening: ScopeWidening) throws
    func clear(destinationIDs: [String]) throws
}

/// Records nothing: the default for a repository whose owner does not track owed history.
public struct NoPendingBackfill: PendingBackfillStorage {
    public init() {}
    public func pending() -> [ScopeWidening] { [] }
    public func record(_ widening: ScopeWidening) throws {}
    public func clear(destinationIDs: [String]) throws {}
}
