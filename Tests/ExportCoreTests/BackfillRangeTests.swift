// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import CorrectnessEngine
import Foundation
import MetricCatalog
import Testing

private let heart = MetricCatalog.heartRate.id

private func window(_ first: String, _ last: String) -> BackfillWindow {
    BackfillWindow(metrics: [heart], firstDay: first, lastDay: last)
}

private func job(start: String, end: String, done: Bool) throws -> BackfillCheckpoint {
    var checkpoint = try BackfillCheckpoint(
        jobID: "job",
        createdAt: "2026-01-01T00:00:00Z",
        hostModel: "test",
        plan: BackfillPlan(
            windowStartDay: start,
            windowEndDay: end,
            metrics: [heart],
            destinations: ["local-file"]
        )
    )
    if done {
        let days = try ReconcilePlanner.days(from: start, through: end)
        checkpoint.progress.completed = [BackfillCompletedRange(metric: heart, days: days)]
    }
    return checkpoint
}

@Test func rangesCountBackFromTodayInclusive() {
    #expect(BackfillRange.days7.firstDay(today: "2026-03-08") == "2026-03-02")
    #expect(BackfillRange.days30.firstDay(today: "2026-03-08") == "2026-02-07")
    #expect(BackfillRange.days90.firstDay(today: "2026-01-10") == "2025-10-13")
    #expect(BackfillRange.all.firstDay(today: "2026-03-08") == nil)
}

@Test func aRangeOnlyNarrowsTheWindow() {
    let held = window("2026-01-01", "2026-03-08")
    #expect(BackfillRange.days7.clamp(held, today: "2026-03-08") == window("2026-03-02", "2026-03-08"))
    #expect(BackfillRange.all.clamp(held, today: "2026-03-08") == held)
    // Health holds less than was asked for: the range never reaches earlier than that.
    let short = window("2026-03-05", "2026-03-08")
    #expect(BackfillRange.days90.clamp(short, today: "2026-03-08") == short)
    // The history ended before the range begins.
    #expect(BackfillRange.days7.clamp(window("2025-01-01", "2025-02-01"), today: "2026-03-08") == nil)
}

@Test func aSavedJobIsReplacedWhenFinishedOrForAnotherSpan() throws {
    let today = "2026-03-08"
    let same = try job(start: "2026-03-02", end: today, done: false)
    #expect(!BackfillRange.days7.supersedes(same, today: today))
    #expect(BackfillRange.days30.supersedes(same, today: today))
    #expect(!BackfillRange.all.supersedes(same, today: today))
    let finished = try job(start: "2026-03-02", end: today, done: true)
    #expect(finished.isFinished)
    #expect(BackfillRange.days7.supersedes(finished, today: today))
    #expect(BackfillRange.all.supersedes(finished, today: today))
}

@Test func reportsAreReadFromTheRunLines() {
    #expect(
        BackfillReport.parse([
            "aggregateOnly backfill complete", "Destinations: a", "Samples read: 12", "Batches enqueued: 3",
        ]) == .completed(samples: 12, batches: 3)
    )
    #expect(
        BackfillReport.parse(["raw backfill parked", "Queue is full", "Samples read: 1"])
            == .parked(reason: "Queue is full")
    )
    #expect(BackfillReport.parse([ExportPlan.noBackfillHistoryLine]) == .nothingToDo(ExportPlan.noBackfillHistoryLine))
    #expect(BackfillReport.parse(["blocked: nowhere"]) == .blocked("blocked: nowhere"))
    #expect(BackfillReport.parse([]) == .nothingToDo(""))
}

@Test func anOwedDestinationIsSettledOnlyWhenTheRunReachedItsFirstDay() {
    func day(_ iso: String) -> Date { ISO8601DateFormatter().date(from: "\(iso)T00:00:00Z")! }
    let owed = [ScopeWidening(destinationID: "a", metrics: [heart], since: day("2026-01-10"))]
    #expect(ScopeWidening.settled(destinations: ["a", "b"], owed: owed, firstDay: "2026-03-02") == ["b"])
    #expect(ScopeWidening.settled(destinations: ["a", "b"], owed: owed, firstDay: "2026-01-10") == ["a", "b"])
}

@Test func resumeKeepsASavedJobOnlyWhenNothingSupersedesIt() throws {
    let today = "2026-03-08"
    let saved = try job(start: "2026-03-02", end: today, done: false)
    func resolve(
        _ checkpoint: BackfillCheckpoint?,
        range: BackfillRange?,
        owed: [ScopeWidening] = []
    ) -> BackfillCheckpoint? {
        BackfillCheckpoint.resolveResume(
            saved: checkpoint, range: range, today: today, owed: owed, planned: ["local-file"]
        )
    }
    #expect(resolve(nil, range: nil) == nil)
    #expect(resolve(saved, range: nil) == saved)
    #expect(resolve(saved, range: .days7) == saved)
    // A different span starts its own job.
    #expect(resolve(saved, range: .days30) == nil)
    // A grant that grew past the job's first day cannot resume it.
    let earlier = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")!
    let owed = [ScopeWidening(destinationID: "local-file", metrics: [heart], since: earlier)]
    #expect(resolve(saved, range: nil, owed: owed) == nil)
}

@Test func dayStringIsTheUTCDayOfADate() {
    #expect(ExportScopeGate.dayString(Date(timeIntervalSince1970: 1_772_928_000)) == "2026-03-08")
    #expect(ExportScopeGate.dayString(Date(timeIntervalSince1970: 1_772_927_999)) == "2026-03-07")
}
