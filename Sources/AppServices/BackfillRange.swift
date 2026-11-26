// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import CorrectnessEngine
import Foundation

/// How far back a person asks a backfill to reach. It narrows the window the granted
/// scopes and Health's own history already define; it never widens it.
public enum BackfillRange: String, Sendable, CaseIterable, Equatable {
    case days7
    case days30
    case days90
    /// Everything the granted scopes and Health hold.
    case all

    /// The number of UTC days ending today, or nil for everything.
    public var dayCount: Int? {
        switch self {
        case .days7: 7
        case .days30: 30
        case .days90: 90
        case .all: nil
        }
    }

    /// The first UTC day (`yyyy-MM-dd`) this range reaches, counting `today`.
    public func firstDay(today: String) -> String? {
        guard let count = dayCount, let end = ExportScopeGate.dayStartUTC(today) else { return nil }
        let start = end.addingTimeInterval(-TimeInterval(count - 1) * 86_400)
        return String(start.ISO8601Format().prefix(10))
    }

    /// `window` cut to this range. Nil when nothing of the window is left.
    public func clamp(_ window: BackfillWindow, today: String) -> BackfillWindow? {
        guard let start = firstDay(today: today) else { return window }
        let first = max(window.firstDay, start)
        guard first <= window.lastDay else { return nil }
        return BackfillWindow(metrics: window.metrics, firstDay: first, lastDay: window.lastDay)
    }

    /// Whether a saved job must be dropped so this range can run. A finished job is
    /// never run again, and one for a different span would resume the wrong days.
    public func supersedes(_ checkpoint: BackfillCheckpoint, today: String) -> Bool {
        if checkpoint.isFinished { return true }
        guard let start = firstDay(today: today) else { return false }
        return checkpoint.plan.windowStartDay != start
    }
}

extension BackfillCheckpoint {
    /// Every type has every day of the window done.
    public var isFinished: Bool {
        let windowDays = (try? ReconcilePlanner.days(
            from: plan.windowStartDay,
            through: plan.windowEndDay
        ).count) ?? 0
        return plan.metrics.allSatisfy { metric in
            (progress.completed.first { $0.metric == metric }?.days.count ?? 0) >= windowDays
        }
    }
}

/// What a finished `runBackfill` call means, read from its report lines.
public enum BackfillReport: Sendable, Equatable {
    case completed(samples: Int, batches: Int)
    /// Stopped early with the job saved, so a later run resumes it.
    case parked(reason: String)
    /// Nothing to send, with the reason.
    case nothingToDo(String)
    case blocked(String)

    public static func parse(_ lines: [String]) -> BackfillReport {
        guard let first = lines.first else { return .nothingToDo("") }
        if first.hasPrefix("blocked:") { return .blocked(first) }
        if first.hasSuffix(" backfill parked") {
            return .parked(reason: lines.dropFirst().first ?? "")
        }
        if first.hasSuffix(" backfill complete") {
            return .completed(samples: count("Samples read: ", in: lines), batches: count("Batches enqueued: ", in: lines))
        }
        return .nothingToDo(first)
    }

    private static func count(_ prefix: String, in lines: [String]) -> Int {
        lines.first { $0.hasPrefix(prefix) }.flatMap { Int($0.dropFirst(prefix.count)) } ?? 0
    }
}
