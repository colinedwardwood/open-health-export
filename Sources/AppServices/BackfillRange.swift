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

    /// The first UTC day (`yyyy-MM-dd`) this range reaches, counting `today`.
    public func firstDay(today: String) -> String? {
        let count: Int
        switch self {
        case .days7: count = 7
        case .days30: count = 30
        case .days90: count = 90
        case .all: return nil
        }
        guard let end = ExportScopeGate.dayStartUTC(today) else { return nil }
        return ExportScopeGate.dayString(end.addingTimeInterval(-TimeInterval(count - 1) * 86_400))
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
        let windowDays: Int
        if let first = ExportScopeGate.dayStartUTC(plan.windowStartDay),
           let last = ExportScopeGate.dayStartUTC(plan.windowEndDay) {
            windowDays = max(0, Int(last.timeIntervalSince(first) / 86_400) + 1)
        } else {
            windowDays = 0
        }
        return plan.metrics.allSatisfy { metric in
            (progress.completed.first { $0.metric == metric }?.days.count ?? 0) >= windowDays
        }
    }

    /// The saved job a backfill may resume, or nil when there is none or it must be
    /// dropped. A chosen `range` starts its own job (Settings resumes a saved one only
    /// when it spans exactly that range), and #61: a job that cannot reach history a
    /// widened scope now owes would either never run again or resume without it.
    public static func resolveResume(
        saved: BackfillCheckpoint?,
        range: BackfillRange?,
        today: String,
        owed: [ScopeWidening],
        planned: [String]
    ) -> BackfillCheckpoint? {
        guard let saved else { return nil }
        if let range, range.supersedes(saved, today: today) { return nil }
        if ScopeWidening.supersedes(saved, owed: owed, planned: planned) { return nil }
        return saved
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
