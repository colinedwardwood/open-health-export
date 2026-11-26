// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import CorrectnessEngine
import EnginePorts
import Foundation
import MetricCatalog
import SinkLocalFile
import TestSupport
import Testing
import Watchdog
import WireFormat

private let heart = MetricCatalog.heartRate.id
private let steps = MetricCatalog.stepCount.id

private func day(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: "\(iso)T00:00:00Z")!
}

private func scope(
    _ metrics: Set<MetricID> = [heart],
    id: String = "local-file",
    from start: String? = nil,
    until end: String? = nil
) throws -> DestinationExportScope {
    try DestinationExportScope(
        destinationID: id,
        metrics: metrics,
        startInclusive: start.map(day),
        endExclusive: end.map(day)
    )
}

@Test func wideningIsDetectedForEveryWayAGrantGrows() throws {
    let base = try scope(from: "2024-01-10")
    // Unchanged, narrower or not yet configured grants owe nothing.
    #expect(ScopeWidening.between(old: base, new: base) == nil)
    #expect(ScopeWidening.between(old: base, new: try scope(from: "2024-01-20")) == nil)
    #expect(ScopeWidening.between(old: base, new: try scope([], from: "2024-01-01")) == nil)
    #expect(ScopeWidening.between(old: base, new: try scope(from: nil)) == nil)

    // An earlier start owes the days in between.
    let earlier = try #require(ScopeWidening.between(old: base, new: try scope(from: "2024-01-01")))
    #expect(earlier == ScopeWidening(destinationID: "local-file", metrics: [heart], since: day("2024-01-01")))

    // A new type owes that type's whole window, not the old window's start.
    let added = try #require(
        ScopeWidening.between(old: base, new: try scope([heart, steps], from: "2024-01-15"))
    )
    #expect(added.metrics == [steps])
    #expect(added.since == day("2024-01-15"))

    // A first grant, or one replacing an unconfigured grant, owes everything.
    #expect(ScopeWidening.between(old: nil, new: base)?.since == day("2024-01-10"))
    #expect(ScopeWidening.between(old: try scope([], from: nil), new: base)?.since == day("2024-01-10"))

    // A later end (or none) exposes samples the closed window excluded.
    let closed = try scope(from: "2024-01-01", until: "2024-01-10")
    #expect(ScopeWidening.between(old: closed, new: try scope(from: "2024-01-01", until: "2024-01-20"))?.since == day("2024-01-10"))
    #expect(ScopeWidening.between(old: closed, new: try scope(from: "2024-01-01"))?.since == day("2024-01-10"))
    #expect(ScopeWidening.between(old: closed, new: try scope(from: "2024-01-01", until: "2024-01-05")) == nil)
    #expect(ScopeWidening.between(old: closed, new: closed) == nil)
}

@Test func owedBackfillsMergePerDestinationAndDescribeThemselves() throws {
    let first = ScopeWidening(destinationID: "b", metrics: [heart], since: day("2024-01-10"))
    let second = ScopeWidening(destinationID: "b", metrics: [steps], since: day("2024-01-02"))
    let other = ScopeWidening(destinationID: "a", metrics: [heart], since: day("2024-01-05"))
    let merged = ScopeWidening.recording(second, in: ScopeWidening.recording(first, in: [other]))
    #expect(merged.map(\.destinationID) == ["a", "b"])
    #expect(merged[1].since == day("2024-01-02"))
    #expect(Set(merged[1].metrics) == [heart, steps])
    #expect(ScopeWidening.statusCopy([]) == nil)
    #expect(ScopeWidening.statusCopy(merged) != nil)
}

// MARK: Repository

private final class OwedStore: PendingBackfillStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var owed: [ScopeWidening] = []
    func pending() -> [ScopeWidening] { lock.withLock { owed } }
    func record(_ widening: ScopeWidening) throws {
        lock.withLock { owed = ScopeWidening.recording(widening, in: owed) }
    }
    func clear(destinationIDs: [String]) throws {
        lock.withLock { owed.removeAll { destinationIDs.contains($0.destinationID) } }
    }
}

private struct SavedScopes: DestinationScopeStorage {
    final class Box: @unchecked Sendable { var scopes: [String: DestinationExportScope] = [:] }
    let box = Box()
    func loadScope(_ destinationID: String) async throws -> DestinationExportScope? { box.scopes[destinationID] }
    func saveScope(_ scope: DestinationExportScope) async throws { box.scopes[scope.destinationID] = scope }
    func reenable(_ metric: MetricID, reason: String) async throws {}
}

private struct NoRecords: DestinationRecordStorage {
    func verification(_ destinationID: String) -> DestinationVerificationSummary? { nil }
    func setPropagateTraceparent(_ enabled: Bool, destinationID: String) throws {}
    func exists(_ sidecar: DestinationSidecar) -> Bool { false }
    func remove(_ sidecar: DestinationSidecar) {}
}

private struct NoPreferences: DestinationPreferenceStorage {
    func exportRole(_ destinationID: String) -> String? { nil }
    func setExportRole(_ rawValue: String, destinationID: String) {}
    func allowsMeteredNetwork(_ destinationID: String) -> Bool { false }
    func companionPropagatesTraceparent() -> Bool { false }
    func setCompanionPropagatesTraceparent(_ enabled: Bool) {}
}

private struct NoSnapshots: DestinationSnapshotStorage {
    func exportRole(_ destinationID: String) -> DestinationExportRole? { nil }
    func applyExportRole(_ role: DestinationExportRole, destinationID: String, at now: Date) throws {}
}

private struct NoFolder: LocalExportFolderStorage {
    func saveFolder(_ url: URL) throws {}
    func accessibleFolderName() -> String? { nil }
}

private func repository(owed: any PendingBackfillStorage) -> DestinationRepository {
    DestinationRepository(
        records: NoRecords(),
        preferences: NoPreferences(),
        snapshots: NoSnapshots(),
        scopes: SavedScopes(),
        folder: NoFolder(),
        now: { Date(timeIntervalSince1970: 0) },
        pendingBackfill: owed
    )
}

@Test func savingAWiderScopeRecordsOwedHistoryUntilBackfillCompletes() async throws {
    let owed = OwedStore()
    let repository = repository(owed: owed)
    try await repository.saveScope(try scope(from: "2024-01-10"))
    // The first grant owes its whole window; a backfill clears it.
    #expect(repository.pendingBackfills().map(\.since) == [day("2024-01-10")])
    try repository.backfillCompleted(for: ["local-file"])
    #expect(repository.pendingBackfills().isEmpty)

    try await repository.saveScope(try scope(from: "2024-01-10"))
    #expect(repository.pendingBackfills().isEmpty, "an unchanged grant owes nothing")
    try await repository.saveScope(try scope(from: "2024-01-01"))
    #expect(repository.pendingBackfills().map(\.since) == [day("2024-01-01")])
}

@Test func aRepositoryWithoutBackfillStorageStillSavesScopes() async throws {
    let repository = repository(owed: NoPendingBackfill())
    try await repository.saveScope(try scope(from: "2024-01-01"))
    #expect(repository.pendingBackfills().isEmpty)
    try repository.backfillCompleted(for: ["local-file"])
    #expect(try await repository.scope("local-file").startInclusive == day("2024-01-01"))
}

// MARK: Engine

private func delivered(_ directory: URL) throws -> String {
    try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "ndjson" }
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .joined()
}

private func occurrences(of needle: String, in text: String) -> Int {
    text.components(separatedBy: needle).count - 1
}

private let oldID = "a0000000-0000-4000-8000-000000000001"
private let recentID = "a0000000-0000-4000-8000-000000000002"

private func fixtures() -> (old: SampleRecord, recent: SampleRecord) {
    (
        heartSample(oldID, start: "2024-01-03T10:00:00Z"),
        heartSample(recentID, start: "2024-01-12T10:00:00Z")
    )
}

private func backfillDays() throws -> [String] {
    try ReconcilePlanner.days(from: "2024-01-01", through: "2024-01-12")
}

/// #61: the anchor already passed the days before the old start, so only a backfill
/// can deliver them. It must deliver them once and leave the rest alone.
@Test func wideningAStartDateBackfillsTheNewDaysExactlyOnce() async throws {
    let (old, recent) = fixtures()
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-widen-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let out = root.appendingPathComponent("out")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let store = MemoryStateStore()
    let narrow = try scope(from: "2024-01-10")
    _ = try await ExportRun(
        source: FixtureSource(pages: [SamplePage(
            samples: [recent], tombstones: [], metric: heart,
            anchorBlob: Data([0x01]), observedThrough: Date(timeIntervalSince1970: 0)
        )]),
        destination: .testing(LocalFileSink(directory: out)),
        store: store,
        metric: heart,
        scratchDirectory: root.appendingPathComponent("scratch"),
        envelope: testEnvelope(),
        scope: narrow
    ).run()
    #expect(occurrences(of: recentID, in: try delivered(out)) == 1)

    let widened = try scope(from: "2024-01-01")
    let widening = try #require(ScopeWidening.between(old: narrow, new: widened))
    #expect(widening.since == day("2024-01-01"))
    let sweep = ReconcileSweep(
        observations: FixtureDays(byDay: ["2024-01-03": [old], "2024-01-12": [recent]]),
        destination: .testing(LocalFileSink(directory: out)),
        store: store,
        metric: heart,
        scratchDirectory: root.appendingPathComponent("scratch-backfill"),
        envelope: testEnvelope(),
        scope: widened
    )
    _ = try await sweep.runBackfill(days: try backfillDays(), mode: .raw)
    let text = try delivered(out)
    #expect(occurrences(of: oldID, in: text) == 1)
    #expect(occurrences(of: recentID, in: text) == 1)

    // A second backfill is a no-op: nothing is delivered twice.
    _ = try await sweep.runBackfill(days: try backfillDays(), mode: .raw)
    #expect(occurrences(of: oldID, in: try delivered(out)) == 1)
    #expect(occurrences(of: recentID, in: try delivered(out)) == 1)
}

/// The same hole opens when a second destination starts earlier than the first: the
/// shared cursor is already past its history.
@Test func aNewDestinationWithAnEarlierStartIsBackfilledWithoutResendingToTheFirst() async throws {
    let (old, recent) = fixtures()
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-second-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("first")
    let second = root.appendingPathComponent("second")
    for url in [first, second] {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    let store = MemoryStateStore()
    let narrow = try scope(from: "2024-01-10")
    _ = try await ExportRun(
        source: FixtureSource(pages: [SamplePage(
            samples: [recent], tombstones: [], metric: heart,
            anchorBlob: Data([0x01]), observedThrough: Date(timeIntervalSince1970: 0)
        )]),
        destination: .testing(LocalFileSink(directory: first)),
        store: store,
        metric: heart,
        scratchDirectory: root.appendingPathComponent("scratch"),
        envelope: testEnvelope(),
        scope: narrow
    ).run()

    let earlier = try scope(from: "2024-01-01")
    #expect(ScopeWidening.between(old: nil, new: earlier)?.since == day("2024-01-01"))
    let sweep = ReconcileSweep(
        observations: FixtureDays(byDay: ["2024-01-03": [old], "2024-01-12": [recent]]),
        destination: .testing(LocalFileSink(directory: second)),
        store: store,
        metric: heart,
        scratchDirectory: root.appendingPathComponent("scratch-backfill"),
        envelope: testEnvelope(),
        destinations: [
            RunDestination(id: "local-file", destination: .testing(LocalFileSink(directory: second)), scope: earlier),
        ]
    )
    _ = try await sweep.runBackfill(days: try backfillDays(), mode: .raw)
    let secondText = try delivered(second)
    #expect(occurrences(of: oldID, in: secondText) == 1)
    // Days the first destination already exported are in the shared emitted index, so
    // a sweep does not re-send them to a destination that never had them. That overlap
    // is a separate gap (no per-destination delivery index); only the days before the
    // shared anchor are asserted here.
    let firstText = try delivered(first)
    #expect(occurrences(of: oldID, in: firstText) == 0)
    #expect(occurrences(of: recentID, in: firstText) == 1)
}

// MARK: Saved backfill jobs

private func checkpoint(
    destinations: [String] = ["local-file"],
    metrics: [MetricID] = [heart],
    from start: String = "2024-01-01",
    completedDays: [String] = []
) throws -> BackfillCheckpoint {
    var checkpoint = try BackfillCheckpoint(
        jobID: "job",
        createdAt: "2024-01-01T00:00:00Z",
        hostModel: "test",
        plan: BackfillPlan(
            windowStartDay: start,
            windowEndDay: "2024-01-03",
            metrics: metrics,
            destinations: destinations
        )
    )
    checkpoint.progress.completed = metrics.map {
        BackfillCompletedRange(metric: $0, days: completedDays)
    }
    return checkpoint
}

@Test func aSavedBackfillIsReplacedOnlyWhenItCannotCoverWhatIsOwed() throws {
    let owed = [ScopeWidening(destinationID: "local-file", metrics: [heart], since: day("2024-01-02"))]
    let planned = ["local-file"]
    let all = ["2024-01-01", "2024-01-02", "2024-01-03"]
    // Nothing owed to a planned destination leaves the job alone.
    #expect(!ScopeWidening.supersedes(try checkpoint(completedDays: all), owed: [], planned: planned))
    #expect(!ScopeWidening.supersedes(try checkpoint(completedDays: all), owed: owed, planned: ["https"]))
    // A finished job never runs again, so it is replaced.
    #expect(ScopeWidening.supersedes(try checkpoint(completedDays: all), owed: owed, planned: planned))
    // An unfinished job that already spans the owed days resumes.
    #expect(!ScopeWidening.supersedes(try checkpoint(completedDays: ["2024-01-03"]), owed: owed, planned: planned))
    // One planned without the destination, the type or the earlier days cannot.
    #expect(ScopeWidening.supersedes(try checkpoint(destinations: ["https"]), owed: owed, planned: planned))
    #expect(ScopeWidening.supersedes(try checkpoint(metrics: [steps]), owed: owed, planned: planned))
    #expect(ScopeWidening.supersedes(try checkpoint(from: "2024-01-03"), owed: owed, planned: planned))
    #expect(ScopeWidening.supersedes(try checkpoint(from: "not-a-day"), owed: owed, planned: planned))
    #expect(NoPendingBackfill().pending().isEmpty)
    #expect(throws: Never.self) {
        try NoPendingBackfill().record(owed[0])
        try NoPendingBackfill().clear(destinationIDs: planned)
    }
}
