import CoreDomain
import CoreTemporal
import CorrectnessEngine
import DestinationTrust
import EnginePorts
import Foundation
import MetricCatalog
import SinkLocalFile
import StorageSQLite
import TestSupport
import Testing
import Watchdog
@testable import WireFormat

@Test func errorClassManifestIsInBijectionWithTheEnum() {
    let keys = ErrorClass.allCases.map { ErrorClassManifest.record(for: $0).userCopyKey }
    #expect(Set(keys).count == ErrorClass.allCases.count)
    #expect(ErrorClassManifest.records.count == ErrorClass.allCases.count)
    for errorClass in ErrorClass.allCases {
        #expect(ErrorClassManifest.records[errorClass] != nil)
    }
    #expect(!ErrorClassManifest.record(for: .deviceLocked).scheduleFailure)
    #expect(ErrorClassManifest.record(for: .budgetExhausted).scheduleFailure)
}

@Test func haeEncoderDropsUuidAndRefusesTombstones() throws {
    let sample = heartSample("00000000-0000-0000-0000-000000000001")
    let json = try HAEWire.encode(
        samples: [sample],
        tombstones: [],
        metric: MetricID(rawValue: "heartRate"),
        acknowledgingLoss: HAELossAccepted()
    )
    let text = String(decoding: json, as: UTF8.self)
    #expect(!text.contains("00000000-0000-0000-0000-000000000001"))
    #expect(text.contains("\"date\":\"2024-01-01 00:00:00 +0000\""))
    #expect(text.contains("\"units\":\"bpm\""))
    #expect(throws: HAEError.tombstonesNotRepresentable) {
        _ = try HAEWire.encode(
            samples: [sample],
            tombstones: [TombstoneRecord(key: sample.key, metric: sample.metric)],
            metric: sample.metric,
            acknowledgingLoss: HAELossAccepted()
        )
    }
    #expect(throws: HAEError.unknownMetric) {
        _ = try HAEWire.encode(
            samples: [],
            tombstones: [],
            metric: MetricID(rawValue: "notAMetric"),
            acknowledgingLoss: HAELossAccepted()
        )
    }
}

@Test func successRequiresAckedAtLeastRead() {
    let short = RunTally(read: 10, acked: 4, partialCause: "deferred_discretionary")
    let outcome = RunOutcome.derive(from: short)
    #expect(outcome.kind == .partial)
    #expect(outcome.partialCause == "deferred_discretionary")

    let ok = RunTally(read: 10, acked: 10)
    #expect(RunOutcome.derive(from: ok).kind == .success)
}

@Test func lockedDeviceIsNotFailed() {
    let tally = RunTally(terminalError: .deviceLocked)
    #expect(RunOutcome.derive(from: tally).kind == .blockedDeviceLocked)
}

@Test func webhookStatusOnlyIsSuccess() {
    let tally = RunTally(read: 3, acked: 3, ackEvidenceStatusOnly: true)
    let outcome = RunOutcome.derive(from: tally)
    #expect(outcome.kind == .success)
    #expect(outcome.ackEvidence == .statusOnly)
}

@Test func hkStatisticsExceptionListIsNonEmpty() {
    #expect(MetricCatalog.hkStatisticsExceptions.contains(MetricCatalog.stepCount.id))
}

@Test func homeAssistantMappingOmitsGuessedDeviceClassesAndForbidsSilentStatistics() throws {
    let measurementForbidden: Set<String> = [
        "date", "enum", "energy", "gas", "monetary", "timestamp", "volume", "water",
    ]
    for declaration in MetricCatalog.all {
        if let deviceClass = declaration.haDeviceClass, measurementForbidden.contains(deviceClass) {
            #expect(declaration.haStateClass != "measurement")
        }
        if declaration.haDeviceClass == "enum" {
            #expect(declaration.haStateClass == nil)
        }
    }
    #expect(MetricCatalog.stepCount.haUnit == "steps")
    #expect(MetricCatalog.stepCount.haDeviceClass == nil)
    #expect(MetricCatalog.stepCount.haStateClass == "total_increasing")
    #expect(MetricCatalog.stepCount.haRequiresAggregate)
    #expect(MetricCatalog.heartRate.haDeviceClass == nil)
    #expect(MetricCatalog.heartRate.haStateClass == "measurement")
    #expect(MetricCatalog.activeEnergy.haDeviceClass == "energy")
    #expect(MetricCatalog.activeEnergy.haStateClass == "total_increasing")
    #expect(MetricCatalog.oxygenSaturation.haDeviceClass == nil)
    #expect(MetricCatalog.bodyMass.sensitivity == .sensitive)
    let json = try HADiscovery.encodeDeviceConfig(
        exporterId: "6b1c2d3e",
        metrics: [MetricCatalog.stepCount.id, MetricCatalog.heartRate.id]
    )
    let text = String(decoding: json, as: UTF8.self)
    #expect(!text.contains("\"qty\""))
    #expect(!text.contains("\"uuid\""))
    #expect(!text.contains("\"device_class\""))
    #expect(text.contains("\"state_class\":\"total_increasing\""))
    #expect(text.contains("\"state_class\":\"measurement\""))
    #expect(text.contains("\"unit_of_measurement\":\"steps\""))
    #expect(HADiscovery.retainAllowed(
        topic: try HADiscovery.deviceConfigTopic(exporterId: "6b1c2d3e"),
        payload: json
    ))
    #expect(!HADiscovery.retainAllowed(topic: "ohe/health", payload: json))
    let state = try HAState.encode(
        HAStatePoint(
            value: 72,
            timeZoneIdentifier: "UTC",
            sampleCount: 4,
            state: "open",
            computation: "mean"
        )
    )
    let stateText = String(decoding: state, as: UTF8.self)
    #expect(stateText.contains("\"value\":72"))
    #expect(!stateText.contains("uuid"))
    #expect(!stateText.contains("qty"))
    let stateTopic = try HAState.topic(
        exporterId: "6b1c2d3e",
        wireId: "heart_rate",
        statistic: "mean",
        granularity: "PT1H"
    )
    #expect(!HADiscovery.retainAllowed(topic: stateTopic, payload: state))
}

@Test func dayBucketIsDeterministicUnderFrozenClock() {
    let date = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 00:00 UTC
    let context = TemporalContext(
        timeZoneIdentifier: "UTC",
        localeIdentifier: "en_US_POSIX",
        tzDatabaseVersion: "2024a"
    )
    let bucket = DayBucket.containing(date, context: context)
    #expect(bucket == DayBucket(year: 2024, month: 1, day: 1))
}

@Test func memoryStoreCannotAdvanceCursorWithoutCommitBatch() async throws {
    let store = MemoryStateStore()
    let page = SamplePage(
        samples: [],
        tombstones: [],
        metric: MetricID(rawValue: "heartRate"),
        anchorBlob: Data([1]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    try await store.transact { tx in
        try tx.commitBatch(
            PendingBatch(id: BatchID(rawValue: "b1"), payloadURL: "file://tmp"),
            advancing: CursorAdvance(page: page, epoch: 1)
        )
    }
    #expect(store.transaction.cursors[MetricID(rawValue: "heartRate")]?.epoch == 1)
    #expect(try store.transaction.pendingBatches().map(\.id.rawValue) == ["b1"])
}

@Test func sqliteJournalRoundTrip() async throws {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-test-\(UUID().uuidString).sqlite")
        .path
    let store = try SQLiteStateStore(path: path)
    try await store.transact { tx in
        try tx.appendJournal(RunEvent(runID: RunID(rawValue: "r1"), outcomeKind: "success", detail: ""))
    }
}

@Test func nativeWireIsStableForFixedRecord() throws {
    let sample = SampleRecord(
        key: RecordKey(uuid: "00000000-0000-0000-0000-000000000001"),
        metric: MetricID(rawValue: "heartRate"),
        start: "2024-01-01T00:00:00Z",
        end: "2024-01-01T00:00:00Z",
        timeZoneOffsetMinutes: 0,
        timeZoneSource: .unknown,
        value: 60,
        unit: CanonicalUnit(symbol: "count/min"),
        observedAt: "2024-01-01T00:00:00Z"
    )
    let envelope = testEnvelope()
    let line = try NativeWire.encode(sample, envelope: envelope)
    #expect(line.contains("\"uuid\":\"00000000-0000-0000-0000-000000000001\""))
    #expect(line.contains("\"kind\":\"sample.quantity\""))
    #expect(line.contains("\"metricId\":\"heart_rate\""))
    #expect(line.contains("\"spec\"") == false)
    let batch = try NativeWire.encode(
        samples: [sample],
        tombstones: [
            TombstoneRecord(
                key: RecordKey(uuid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"),
                metric: MetricID(rawValue: "heartRate")
            )
        ],
        metric: MetricID(rawValue: "heartRate"),
        batchID: BatchID(rawValue: "0192f3c1-0000-0000-0000-000000000001"),
        envelope: envelope
    )
    let text = String(decoding: batch, as: UTF8.self)
    let ndjson = text.split(whereSeparator: \.isNewline).map(String.init)
    #expect(ndjson.count == 4)
    #expect(ndjson[0].contains("\"kind\":\"batch.header\""))
    #expect(ndjson[0].contains("\"spec\":\"ohe.wire/1\""))
    #expect(ndjson[1].contains("\"kind\":\"sample.quantity\""))
    #expect(ndjson[2].contains("\"kind\":\"tombstone\""))
    #expect(ndjson[2].contains("\"bestEffort\":true"))
    #expect(ndjson[3].contains("\"kind\":\"batch.footer\""))
    #expect(ndjson[3].contains("\"contentDigest\":\"sha256:"))
    let body = ndjson[1] + "\n" + ndjson[2] + "\n"
    #expect(ndjson[3].contains(SHA256.hex(Data(body.utf8))))
}

@Test func sha256MatchesFIPSVectors() {
    #expect(SHA256.hex(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    #expect(SHA256.hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

@Test func anchorTokenEnvelopeRejectsGarbage() {
    #expect(throws: AnchorTokenError.corrupt) {
        _ = try AnchorToken.fromEnvelope(Data("nope".utf8))
    }
    let token = AnchorToken(format: 1, bytes: Data([1, 2, 3]))
    let restored = try? AnchorToken.fromEnvelope(token.envelope())
    #expect(restored?.bytes == Data([1, 2, 3]))
    #expect(restored?.format == 1)
}

@Test func watchdogEscalatesWhenLastSuccessIsOld() {
    let policy = StalenessPolicy(defaultInterval: 3600)
    let now = Date(timeIntervalSince1970: 10_000)
    let last = Date(timeIntervalSince1970: 100)
    #expect(policy.shouldEscalate(lastSuccess: last, now: now))
    #expect(!policy.shouldEscalate(lastSuccess: now, now: now))
}

@Test func pipelineExposesExceptionList() {
    #expect(!Pipeline().hkStatisticsExceptions.isEmpty)
}

func heartSample(_ uuid: String, start: String = "2024-01-01T00:00:00Z") -> SampleRecord {
    SampleRecord(
        key: RecordKey(uuid: uuid),
        metric: MetricID(rawValue: "heartRate"),
        start: start,
        end: start,
        timeZoneOffsetMinutes: 0,
        timeZoneSource: .unknown,
        value: 60,
        unit: CanonicalUnit(symbol: "count/min"),
        observedAt: "2024-01-01T00:00:00Z"
    )
}

func testEnvelope() -> WireEnvelope {
    WireEnvelope(
        exporterId: "00000000-0000-0000-0000-00000000000e",
        seq: 1,
        emittedAt: "2024-01-01T00:00:00Z",
        observedAt: "2024-01-01T00:00:00Z"
    )
}

@Test func writeAheadCursorPreventsRereadAfterCommit() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0xAA]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let source = FixtureSource(pages: [page])
    let store = MemoryStateStore()
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-scratch-\(UUID().uuidString)")
    let dest = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-dest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    let sink = LocalFileSink(directory: dest)
    let run = ExportRun(
        source: source,
        destination: .testing(sink),
        store: store,
        metric: metric,
        scratchDirectory: scratch,
        envelope: testEnvelope()
    )

    let first = try await run.run()
    #expect(first.kind == .success)
    #expect(store.transaction.cursors[metric]?.anchorBlob == Data([0xAA]))
    #expect(try store.transaction.pendingBatches().isEmpty)
    let census = try store.transaction.loadCensus(metric: metric, day: "2024-01-01")
    #expect(census?.sampleCount == 1)
    #expect(try store.transaction.dirtyDays(metric: metric) == ["2024-01-01"])

    let second = try await run.run()
    #expect(second.kind == .successNothingDue)
}

@Test func pendingDeliveryRunnerReplaysACommittedBatchAfterRestart() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("dddddddd-dddd-dddd-dddd-dddddddddddd")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0xDD]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-replay-\(UUID().uuidString)")
    let destination = root.appendingPathComponent("destination")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let payload = root.appendingPathComponent("batch.ndjson")
    try "one\n".write(to: payload, atomically: true, encoding: .utf8)
    let store = MemoryStateStore()
    try await store.transact {
        try $0.commitBatch(
            PendingBatch(
                id: BatchID(rawValue: "replay-batch"),
                payloadURL: payload.path,
                expectedRecords: 1
            ),
            advancing: CursorAdvance(page: page, epoch: 1)
        )
    }

    let runner = PendingDeliveryRunner(
        destination: .testing(LocalFileSink(directory: destination)),
        store: store
    )
    let receipts = try await runner.runOnce()
    #expect(receipts.map(\.accepted) == [1])
    #expect(try store.transaction.pendingBatches().isEmpty)
}

@Test func skipCommitLeavesCursorUnmovedSoPageIsReread() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0xBB]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let source = FixtureSource(pages: [page])
    let first = try await source.page(metric: metric, afterAnchor: nil)
    #expect(first.samples.count == 1)
    let again = try await source.page(metric: metric, afterAnchor: nil)
    #expect(again.samples.count == 1)
    let afterFakeCommit = try await source.page(metric: metric, afterAnchor: Data([0xBB]))
    #expect(afterFakeCommit.samples.isEmpty)
}

@Test func localFileSinkIsIdempotentForTheSameKey() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-sink-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let payload = dir.appendingPathComponent("src.ndjson")
    try "one\n".write(to: payload, atomically: true, encoding: .utf8)
    let sink = LocalFileSink(directory: dir)
    let key = BatchID(rawValue: "same-key")
    let a = try await sink.send(fileHandle: payload.path, idempotencyKey: key)
    let b = try await sink.send(fileHandle: payload.path, idempotencyKey: key)
    #expect(a.accepted == 1)
    #expect(b.accepted == 1)
    let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "ndjson" && $0.lastPathComponent != "src.ndjson" }
    #expect(files.count == 1)
}

@Test func sqlitePersistsCursorAndCensus() async throws {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-test-\(UUID().uuidString).sqlite")
        .path
    let store = try SQLiteStateStore(path: path)
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("cccccccc-cccc-cccc-cccc-cccccccccccc")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0xCC, 0xDD]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    try await store.transact { tx in
        try tx.commitBatch(
            PendingBatch(id: BatchID(rawValue: "b"), payloadURL: "/tmp/x", expectedRecords: 2),
            advancing: CursorAdvance(page: page, epoch: 3)
        )
        try tx.upsertCensus(CensusRow(metric: metric, day: "2024-01-01", sampleCount: 1, digest: "abc"))
        try tx.markDirty(metric: metric, day: "2024-01-01")
    }
    let snap = try await store.transact { try $0.loadCursor(metric: metric) }
    #expect(snap?.epoch == 3)
    #expect(snap?.anchorBlob == Data([0xCC, 0xDD]))
    let row = try await store.transact { try $0.loadCensus(metric: metric, day: "2024-01-01") }
    #expect(row?.sampleCount == 1)
    let dirty = try await store.transact { try $0.dirtyDays(metric: metric) }
    #expect(dirty == ["2024-01-01"])
    let pending = try await store.transact { try $0.pendingBatches() }
    #expect(pending == [
        PendingBatch(id: BatchID(rawValue: "b"), payloadURL: "/tmp/x", expectedRecords: 2)
    ])
    try await store.transact {
        try $0.recordDelivery(
            DeliveryReceipt(batchID: BatchID(rawValue: "b"), accepted: 1, statusOnly: false)
        )
    }
    #expect(try await store.transact { try $0.pendingBatches() }.count == 1)
    try await store.transact {
        try $0.recordDelivery(
            DeliveryReceipt(batchID: BatchID(rawValue: "b"), accepted: 2, statusOnly: false)
        )
    }
    #expect(try await store.transact { try $0.pendingBatches() }.isEmpty)
}
