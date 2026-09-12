// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import FileWriteKit
import Foundation

/// UX-25: a month is complete only when every selected type has every window day in it.
public enum ArchiveMonthProgress {
    public static func yearMonth(day: String) -> String {
        String(day.prefix(7))
    }

    public static func months(from startDay: String, through endDay: String) throws -> [String] {
        let days = try ReconcilePlanner.days(from: startDay, through: endDay)
        var seen = Set<String>()
        var ordered: [String] = []
        for day in days {
            let month = yearMonth(day: day)
            if seen.insert(month).inserted {
                ordered.append(month)
            }
        }
        return ordered
    }

    public static func completedCount(
        from startDay: String,
        through endDay: String,
        metrics: [MetricID],
        completed: [BackfillCompletedRange]
    ) throws -> (completed: Int, total: Int) {
        let windowDays = try ReconcilePlanner.days(from: startDay, through: endDay)
        let months = try months(from: startDay, through: endDay)
        let byMetric = Dictionary(
            uniqueKeysWithValues: completed.map { ($0.metric, Set($0.days)) }
        )
        let done = months.filter { month in
            let daysInMonth = windowDays.filter { yearMonth(day: $0) == month }
            return metrics.allSatisfy { metric in
                daysInMonth.allSatisfy { (byMetric[metric] ?? []).contains($0) }
            }
        }
        return (done.count, months.count)
    }
}

/// UX-25: types, record counts, and per-type window bounds after a finished archive.
public struct ArchiveCompletionManifest: Codable, Sendable, Equatable {
    public struct TypeEntry: Codable, Sendable, Equatable {
        public var metric: String
        public var recordCount: Int
        public var windowStartDay: String?
        public var windowEndDay: String?

        public init(
            metric: String,
            recordCount: Int,
            windowStartDay: String?,
            windowEndDay: String?
        ) {
            self.metric = metric
            self.recordCount = recordCount
            self.windowStartDay = windowStartDay
            self.windowEndDay = windowEndDay
        }
    }

    public var windowStartDay: String
    public var windowEndDay: String
    public var types: [TypeEntry]

    public init(windowStartDay: String, windowEndDay: String, types: [TypeEntry]) {
        self.windowStartDay = windowStartDay
        self.windowEndDay = windowEndDay
        self.types = types
    }

    public static func make(from checkpoint: BackfillCheckpoint) -> ArchiveCompletionManifest {
        ArchiveCompletionManifest(
            windowStartDay: checkpoint.plan.windowStartDay,
            windowEndDay: checkpoint.plan.windowEndDay,
            types: checkpoint.plan.metrics.map { metric in
                let range = checkpoint.progress.completed.first { $0.metric == metric }
                return TypeEntry(
                    metric: metric.rawValue,
                    recordCount: range?.samplesRead ?? 0,
                    windowStartDay: range?.days.min(),
                    windowEndDay: range?.days.max()
                )
            }
        )
    }

    public static func url(adjacentToCheckpoint url: URL) -> URL {
        let stem = url.deletingPathExtension().lastPathComponent
        return url.deletingLastPathComponent()
            .appendingPathComponent("\(stem)-manifest.json")
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }

    public func write(to url: URL) throws {
        try FileWriteKit.writeAtomically(try encoded(), to: url)
    }
}