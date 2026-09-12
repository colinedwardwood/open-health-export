// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CoreTemporal
import CorrectnessEngine
import Foundation
import StorageSQLite
import TestSupport
import Testing
import WireFormat

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

@Test func backfillParksWhenDestinationBreakerIsOpen() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-backfill-breaker-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let store = MemoryStateStore()
    try await store.transact { tx in
        try DestinationBreaker.save(
            BreakerSnapshot(state: .open, consecutiveFailures: 5),
            to: tx,
            destinationID: "local-file"
        )
    }
    let processor = RecordingBackfillProcessor()
    let job = BackfillJob(
        checkpointURL: url,
        processor: processor,
        clock: FrozenClock(instant: Date(timeIntervalSince1970: 1)),
        store: store
    )
    try await job.create(try backfillCheckpoint())
    let paused = try await job.run()
    #expect(paused.progress.pausedReason == CatchUpAdmission.destinationParkedJournalDetail)
    #expect(await processor.recordedDays().isEmpty)
}

@Test func backfillParksOnLowPowerAndThermalWithoutReadingADay() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-backfill-park-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let lowPowerProcessor = RecordingBackfillProcessor()
    let lowPower = BackfillJob(
        checkpointURL: url,
        processor: lowPowerProcessor,
        clock: FrozenClock(instant: Date(timeIntervalSince1970: 1)),
        deferForLowPower: true
    )
    try await lowPower.create(try backfillCheckpoint())
    let lowPowerPaused = try await lowPower.run()
    #expect(lowPowerPaused.progress.pausedReason == CatchUpAdmission.lowPowerParkedJournalDetail)
    #expect(lowPowerPaused.progress.completed[0].days.isEmpty)
    #expect(await lowPowerProcessor.recordedDays().isEmpty)

    let thermalURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-backfill-thermal-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: thermalURL) }
    let thermalProcessor = RecordingBackfillProcessor()
    let thermal = BackfillJob(
        checkpointURL: thermalURL,
        processor: thermalProcessor,
        clock: FrozenClock(instant: Date(timeIntervalSince1970: 1)),
        deferForThermal: true
    )
    try await thermal.create(try backfillCheckpoint())
    let thermalPaused = try await thermal.run()
    #expect(thermalPaused.progress.pausedReason == CatchUpAdmission.thermalParkedJournalDetail)
    #expect(await thermalProcessor.recordedDays().isEmpty)
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

@Test func backfillProgressNamesDayAndTypeTotals() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-backfill-progress-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let processor = RecordingBackfillProcessor()
    let job = BackfillJob(
        checkpointURL: url,
        processor: processor,
        clock: FrozenClock(instant: Date(timeIntervalSince1970: 1))
    )
    try await job.create(try backfillCheckpoint())
    let log = ProgressLog()
    _ = try await job.run { line in
        await log.add(line)
    }
    let lines = await log.snapshot()
    #expect(lines.contains("Archive month 0 of 1 · type 1 of 1"))
    #expect(NamedWorkProgress.archive(completedMonths: 1, totalMonths: 3, type: 2, types: 4)
        == "Archive month 1 of 3 · type 2 of 4")
    #expect(NamedWorkProgress.reconcile(current: 2, total: 5) == "Reconciling 2 of 5 types")
    #expect(NamedWorkProgress.types(current: 3, total: 12) == "Reading 3 of 12 types")

    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let harness = try String(
        contentsOf: root.appendingPathComponent("Apps/Exporter-iOS/HarnessExport.swift"),
        encoding: .utf8
    )
    #expect(harness.contains("archive-manifest.json"))
    for name in ["runHTTPSDestination", "runMQTTDestination", "runCompanion"] {
        guard let range = harness.range(of: "static func \(name)") else {
            Issue.record("\(name) is missing")
            continue
        }
        let window = String(harness[range.lowerBound...].prefix(500))
        #expect(
            window.contains("onProgress:"),
            "\(name) has no type-total progress callback"
        )
    }
}

@Test func ux25ArchiveProgressCountsCompletedMonthsAndWritesManifest() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-backfill-months-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let processor = RecordingBackfillProcessor()
    let job = BackfillJob(
        checkpointURL: url,
        processor: processor,
        clock: FrozenClock(instant: Date(timeIntervalSince1970: 1))
    )
    try await job.create(
        try BackfillCheckpoint(
            jobID: "01J9F0K2QW8Z4YB7M3T5X7",
            createdAt: "2026-09-03T08:14:02Z",
            hostModel: "test-host",
            plan: BackfillPlan(
                windowStartDay: "2024-01-31",
                windowEndDay: "2024-02-01",
                metrics: [MetricID(rawValue: "heartRate")],
                destinations: ["local-file"]
            )
        )
    )
    let log = ProgressLog()
    let complete = try await job.run { line in
        await log.add(line)
    }
    let lines = await log.snapshot()
    #expect(lines == [
        "Archive month 0 of 2 · type 1 of 1",
        "Archive month 1 of 2 · type 1 of 1",
    ])
    let months = try ArchiveMonthProgress.completedCount(
        from: complete.plan.windowStartDay,
        through: complete.plan.windowEndDay,
        metrics: complete.plan.metrics,
        completed: complete.progress.completed
    )
    #expect(months.completed == 2)
    #expect(months.total == 2)

    let manifestURL = ArchiveCompletionManifest.url(adjacentToCheckpoint: url)
    let manifest = try JSONDecoder().decode(
        ArchiveCompletionManifest.self,
        from: Data(contentsOf: manifestURL)
    )
    #expect(manifest.windowStartDay == "2024-01-31")
    #expect(manifest.windowEndDay == "2024-02-01")
    #expect(manifest.types.count == 1)
    #expect(manifest.types[0].metric == "heartRate")
    #expect(manifest.types[0].recordCount == 20)
    #expect(manifest.types[0].windowStartDay == "2024-01-31")
    #expect(manifest.types[0].windowEndDay == "2024-02-01")
}

@Test func backfillUpgradesV1CheckpointThenResumes() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-backfill-v1-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }

    struct V1Range: Codable {
        var metric: MetricID
        var days: [String]
    }
    struct V1Progress: Codable {
        var completed: [V1Range]
        var cursor: BackfillCursor?
        var samplesRead: Int
        var batchesEnqueued: Int
        var pausedReason: String?
    }
    struct V1Checkpoint: Codable {
        var schemaVersion: Int
        var jobID: String
        var jobKind: String
        var createdAt: String
        var updatedAt: String
        var hostModel: String
        var plan: BackfillPlan
        var progress: V1Progress
        var integrity: BackfillIntegrity
    }

    let plan = BackfillPlan(
        windowStartDay: "2024-01-01",
        windowEndDay: "2024-01-02",
        metrics: [MetricID(rawValue: "heartRate")],
        destinations: ["local-file"]
    )
    var legacy = V1Checkpoint(
        schemaVersion: 1,
        jobID: "01J9F0K2QW8Z4YB7M3T5X8",
        jobKind: "backfill",
        createdAt: "2026-09-03T08:14:02Z",
        updatedAt: "2026-09-03T08:14:02Z",
        hostModel: "test-host",
        plan: plan,
        progress: V1Progress(
            completed: [
                V1Range(metric: MetricID(rawValue: "heartRate"), days: ["2024-01-02"])
            ],
            cursor: BackfillCursor(metricIndex: 0, day: "2024-01-01"),
            samplesRead: 10,
            batchesEnqueued: 1,
            pausedReason: "processor_error"
        ),
        integrity: BackfillIntegrity(value: "")
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    legacy.integrity.value = ContentSHA256.hex(try encoder.encode(legacy))
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(legacy)
    data.append(0x0A)
    try data.write(to: url)

    let processor = RecordingBackfillProcessor()
    let job = BackfillJob(
        checkpointURL: url,
        processor: processor,
        clock: FrozenClock(instant: Date(timeIntervalSince1970: 1))
    )
    let complete = try await job.run()
    #expect(complete.schemaVersion == BackfillCheckpoint.currentSchemaVersion)
    #expect(complete.progress.completed[0].days == ["2024-01-01", "2024-01-02"])
    #expect(await processor.recordedDays() == ["2024-01-01"])
}

private actor ProgressLog {
    private var lines: [String] = []
    func add(_ line: String) { lines.append(line) }
    func snapshot() -> [String] { lines }
}
