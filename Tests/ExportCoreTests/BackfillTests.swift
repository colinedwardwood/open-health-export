import CoreDomain
import CoreTemporal
import CorrectnessEngine
import Foundation
import StorageSQLite
import TestSupport
import Testing

private enum BackfillProcessorFailure: Error {
    case interrupted
}

private actor RecordingBackfillProcessor: BackfillChunkProcessor {
    private var calls: [(MetricID, String, BackfillMode)] = []
    private var failOnCall: Int?

    init(failOnCall: Int? = nil) {
        self.failOnCall = failOnCall
    }

    func process(
        metric: MetricID,
        days: [String],
        mode: BackfillMode
    ) async throws -> BackfillChunkResult {
        let day = days[0]
        calls.append((metric, day, mode))
        if calls.count == failOnCall {
            failOnCall = nil
            throw BackfillProcessorFailure.interrupted
        }
        return BackfillChunkResult(samplesRead: 10, batchesEnqueued: 1)
    }

    func recordedDays() -> [String] {
        calls.map(\.1)
    }
}

private func backfillCheckpoint(
    mode: BackfillMode = .aggregateOnly
) throws -> BackfillCheckpoint {
    try BackfillCheckpoint(
        jobID: "01J9F0K2QW8Z4YB7M3T5X6",
        createdAt: "2026-09-03T08:14:02Z",
        hostModel: "test-host",
        plan: BackfillPlan(
            windowStartDay: "2024-01-01",
            windowEndDay: "2024-01-03",
            mode: mode,
            metrics: [MetricID(rawValue: "heartRate")],
            destinations: ["local-file"]
        )
    )
}

@Test func backfillKillAndResumeHasNoSkipAndAtMostOneRepeatedChunk() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-backfill-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let processor = RecordingBackfillProcessor(failOnCall: 2)
    let job = BackfillJob(
        checkpointURL: url,
        processor: processor,
        clock: FrozenClock(instant: Date(timeIntervalSince1970: 1))
    )
    try await job.create(try backfillCheckpoint())

    await #expect(throws: BackfillProcessorFailure.interrupted) {
        _ = try await job.run()
    }
    let paused = try BackfillCheckpoint.read(from: url)
    #expect(paused.progress.completed[0].days == ["2024-01-03"])
    #expect(paused.progress.cursor?.day == "2024-01-02")
    #expect(paused.progress.pausedReason == "processor_error")

    let complete = try await job.run()
    #expect(
        await processor.recordedDays()
            == ["2024-01-03", "2024-01-02", "2024-01-02", "2024-01-01"]
    )
    #expect(
        complete.progress.completed[0].days
            == ["2024-01-01", "2024-01-02", "2024-01-03"]
    )
    #expect(complete.progress.cursor == nil)
    #expect(complete.progress.pausedReason == nil)
    #expect(complete.progress.samplesRead == 30)
    #expect(complete.progress.batchesEnqueued == 3)
}

@Test func backfillCheckpointIntegrityMismatchFailsExplicitly() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-backfill-corrupt-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    var checkpoint = try backfillCheckpoint()
    checkpoint.hostModel = "tampered-after-seal"
    try checkpoint.encoded().write(to: url)

    #expect(throws: BackfillError.corruptCheckpoint) {
        _ = try BackfillCheckpoint.read(from: url)
    }
}

@Test func backfillCheckpointRejectsForwardSchemaWithoutSilentMigration() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-backfill-forward-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    var checkpoint = try backfillCheckpoint()
    checkpoint.schemaVersion = BackfillCheckpoint.currentSchemaVersion + 1
    try checkpoint.reseal()
    try checkpoint.encoded().write(to: url)

    #expect(
        throws: BackfillError.unsupportedSchema(
            BackfillCheckpoint.currentSchemaVersion + 1
        )
    ) {
        _ = try BackfillCheckpoint.read(from: url)
    }
}

@Test func firstRunBackfillDefaultsToAggregateOnlyAndRawIsExplicit() throws {
    #expect(try backfillCheckpoint().plan.mode == .aggregateOnly)
    #expect(try backfillCheckpoint(mode: .raw).plan.mode == .raw)
}

@Test func backfillCheckpointFileAndSQLiteMirrorMustAgree() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-backfill-mirror-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("backfill.json")
    let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
    let processor = RecordingBackfillProcessor()
    let job = BackfillJob(
        checkpointURL: url,
        processor: processor,
        clock: FrozenClock(instant: Date(timeIntervalSince1970: 1)),
        store: store
    )
    let checkpoint = try backfillCheckpoint()
    try await job.create(checkpoint)
    let mirrored = try await store.transact {
        try $0.loadBackfillCheckpoint(jobID: checkpoint.jobID)
    }
    let fileBytes = try Data(contentsOf: url)
    #expect(mirrored == fileBytes)

    try await store.transact {
        try $0.upsertBackfillCheckpoint(
            jobID: checkpoint.jobID,
            bytes: Data("tampered-sqlite-mirror".utf8)
        )
    }
    await #expect(throws: BackfillError.corruptCheckpoint) {
        _ = try await job.run()
    }
}
