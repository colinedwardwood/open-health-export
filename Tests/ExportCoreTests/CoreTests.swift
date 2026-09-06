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
    #expect(!StalenessPolicy().shouldEscalate(lastSuccess: nil, now: now))
}

@Test func freshnessTargetRequiresFourteenDaysAndOneHundredObservations() {
    let start = Date(timeIntervalSince1970: 0)
    let tooShort = (0..<100).map { index in
        FreshnessObservation(
            observedAt: start.addingTimeInterval(Double(index) * 60),
            latency: Double(index + 1)
        )
    }
    #expect(FreshnessTarget.localP95(observations: tooShort) == nil)

    let qualifying = (0..<100).map { index in
        FreshnessObservation(
            observedAt: start.addingTimeInterval(
                Double(index) * FreshnessTarget.minimumSpan / 99
            ),
            latency: Double(index + 1)
        )
    }
    #expect(FreshnessTarget.localP95(observations: qualifying) == 95)
    #expect(FreshnessTarget.alarmThreshold(p95: 95) == FreshnessTarget.alarmFloor)
    #expect(
        FreshnessTarget.alarmThreshold(p95: 100 * 60 * 60)
            == FreshnessTarget.alarmCap
    )
}

@Test func retryPolicyUsesFullJitterAndOpensAfterFiveFailures() {
    let now = Date(timeIntervalSince1970: 1_000)
    var snapshot = BreakerSnapshot()
    for failure in 1...5 {
        snapshot = RetryPolicy.record(
            .failed(.transientNetwork),
            snapshot: snapshot,
            now: now,
            jitter: 0.5
        )
        #expect(snapshot.consecutiveFailures == failure)
    }
    #expect(snapshot.state == .open)
    // n=5: uniform(0, min(6h, 15*2^5)); injected midpoint is 240 seconds.
    #expect(snapshot.nextEarliestAttempt == now.addingTimeInterval(240))
    #expect(!RetryPolicy.mayAttempt(snapshot: snapshot, now: now, foreground: false))
    #expect(RetryPolicy.mayAttempt(snapshot: snapshot, now: now, foreground: true))
    #expect(RetryPolicy.beginProbe(snapshot: snapshot, now: now, foreground: true).state == .halfOpen)
}

@Test func retryPolicyHandlesUnknownAckImmediateBlocksAndRetryAfter() {
    let now = Date(timeIntervalSince1970: 2_000)
    var unknown = BreakerSnapshot()
    for _ in 0..<3 {
        unknown = RetryPolicy.record(.unknownAck, snapshot: unknown, now: now, jitter: 0)
    }
    #expect(unknown.state == .open)
    #expect(unknown.consecutiveUnknownAcks == 3)

    let auth = RetryPolicy.record(
        .failed(.auth),
        snapshot: BreakerSnapshot(),
        now: now,
        jitter: 0
    )
    #expect(auth.state == .blockedNeedsUser)
    #expect(!RetryPolicy.mayAttempt(snapshot: auth, now: now.addingTimeInterval(1_000_000), foreground: true))

    let pin = RetryPolicy.record(
        .failed(.pinChangeHalt),
        snapshot: BreakerSnapshot(),
        now: now,
        jitter: 0
    )
    #expect(pin.state == .halted)

    let server = RetryPolicy.record(
        .failed(.transientServer, retryAfter: 100_000),
        snapshot: BreakerSnapshot(),
        now: now,
        jitter: 0
    )
    #expect(server.nextEarliestAttempt == now.addingTimeInterval(RetryPolicy.maximumRetryAfter))
}

@Test func retryPolicyPersistentBreakerProbesAtMostEverySixHours() {
    let opened = Date(timeIntervalSince1970: 3_000)
    let snapshot = BreakerSnapshot(
        state: .open,
        consecutiveFailures: 5,
        openedAt: opened,
        nextEarliestAttempt: opened
    )
    let weekLater = opened.addingTimeInterval(RetryPolicy.persistentAfter)
    let aged = RetryPolicy.age(snapshot: snapshot, now: weekLater)
    #expect(aged.state == .failingPersistently)
    #expect(aged.nextEarliestAttempt == weekLater.addingTimeInterval(RetryPolicy.maximumDelay))
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
    #expect(try store.transaction.loadCursor(metric: metric)?.anchorBlob == Data([0xAA]))
    #expect(store.transaction.cursors[metric]?.anchorBlob.prefix(4) == Data("OHEC".utf8))
    #expect(try store.transaction.pendingBatches().isEmpty)
    #expect(store.transaction.ledger.count == 2)
    let phases = store.transaction.ledger.map(\.outcomeKind)
    #expect(phases[0].split(separator: ":").last == "attempt")
    #expect(phases[1].split(separator: ":").last == "acknowledged")
    #expect(phases[0].split(separator: ":").first == phases[1].split(separator: ":").first)
    let census = try store.transaction.loadCensus(metric: metric, day: "2024-01-01")
    #expect(census?.sampleCount == 1)
    #expect(try store.transaction.dirtyDays(metric: metric) == ["2024-01-01"])
    let indexed = try store.transaction.loadEmittedIndex(
        uuid: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    )
    #expect(indexed?.day == "2024-01-01")
    #expect(indexed?.batchID == NativeWire.batchID(metric: metric, anchorBlob: Data([0xAA])))

    let second = try await run.run()
    #expect(second.kind == .successNothingDue)
    #expect(store.transaction.ledger.count == 2)
}

#if DEBUG
private enum InjectedExportFault: Error {
    case stop
}

private struct OneExportFault: ExportFaultInjector {
    var location: ExportFaultLocation

    func hit(_ location: ExportFaultLocation) throws {
        if location == self.location {
            throw InjectedExportFault.stop
        }
    }
}

@Test func everyR83FaultLocationIsReachableAndPreservesWriteAheadOrdering() async throws {
    let beforeCommit: Set<ExportFaultLocation> = [.afterRead, .afterTransform, .duringAnchorPersist]
    for location in ExportFaultLocation.allCases {
        let metric = MetricID(rawValue: "heartRate")
        let page = SamplePage(
            samples: [heartSample("f0000000-0000-0000-0000-000000000001")],
            tombstones: [],
            metric: metric,
            anchorBlob: Data([0xF0]),
            observedThrough: Date(timeIntervalSince1970: 0)
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohe-fi-\(location.rawValue)-\(UUID().uuidString)")
        let destinationURL = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: true
        )
        let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
        var run = ExportRun(
            source: FixtureSource(pages: [page]),
            destination: .testing(LocalFileSink(directory: destinationURL)),
            store: store,
            metric: metric,
            scratchDirectory: root.appendingPathComponent("scratch"),
            envelope: testEnvelope()
        )
        run.faults = OneExportFault(location: location)

        await #expect(throws: InjectedExportFault.stop) {
            _ = try await run.run()
        }
        let cursor = try await store.transact { try $0.loadCursor(metric: metric) }
        let pending = try await store.transact { try $0.pendingBatches() }
        if beforeCommit.contains(location) {
            #expect(cursor == nil, "cursor advanced at \(location.rawValue)")
            #expect(pending.isEmpty, "batch survived rollback at \(location.rawValue)")
            #expect(
                try await store.transact {
                    try $0.loadEmittedIndex(uuid: "f0000000-0000-0000-0000-000000000001")
                } == nil,
                "emitted_index survived rollback at \(location.rawValue)"
            )
        } else {
            #expect(cursor?.anchorBlob == Data([0xF0]))
            #expect(pending.count == 1, "batch was not replayable at \(location.rawValue)")
            #expect(
                try await store.transact {
                    try $0.loadEmittedIndex(uuid: "f0000000-0000-0000-0000-000000000001")
                } != nil,
                "emitted_index missing after commit at \(location.rawValue)"
            )
        }

        if location == .afterDestinationWriteBeforeAck || location == .afterAckBeforeRelease {
            let replay = PendingDeliveryRunner(
                destination: .testing(LocalFileSink(directory: destinationURL)),
                store: store
            )
            _ = try await replay.runOnce()
            #expect(try await store.transact { try $0.pendingBatches() }.isEmpty)
            let delivered = try FileManager.default.contentsOfDirectory(
                at: destinationURL,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "ndjson" }
            #expect(delivered.count == 1, "idempotent replay duplicated \(location.rawValue)")
        }
    }
}
#endif

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
    let secondPayload = root.appendingPathComponent("batch-2.ndjson")
    try "two\n".write(to: secondPayload, atomically: true, encoding: .utf8)
    let store = MemoryStateStore()
    try await store.transact {
        try $0.commitBatch(
            PendingBatch(
                id: BatchID(rawValue: "z-oldest"),
                payloadURL: payload.path,
                expectedRecords: 1
            ),
            advancing: CursorAdvance(page: page, epoch: 1)
        )
        try $0.commitBatch(
            PendingBatch(
                id: BatchID(rawValue: "a-newest"),
                payloadURL: secondPayload.path,
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
    #expect(try store.transaction.pendingBatches().map(\.id.rawValue) == ["a-newest"])
    #expect(store.transaction.ledger.count == 2)
    _ = try await runner.runOnce()
    #expect(try store.transaction.pendingBatches().isEmpty)
    #expect(store.transaction.ledger.count == 4)
}

@Test func failedPendingDeliveryStillRecordsItsOutcomeAndStaysQueued() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0xEE]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-replay-fail-\(UUID().uuidString)")
    let destination = root.appendingPathComponent("destination")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let store = MemoryStateStore()
    try await store.transact {
        try $0.commitBatch(
            PendingBatch(
                id: BatchID(rawValue: "failed-replay"),
                payloadURL: root.appendingPathComponent("missing.ndjson").path,
                expectedRecords: 1
            ),
            advancing: CursorAdvance(page: page, epoch: 1)
        )
    }
    let runner = PendingDeliveryRunner(
        destination: .testing(LocalFileSink(directory: destination)),
        store: store
    )
    await #expect(throws: Error.self) {
        _ = try await runner.runOnce()
    }
    #expect(try store.transaction.pendingBatches().count == 1)
    #expect(store.transaction.ledger.count == 2)
    #expect(store.transaction.ledger[0].outcomeKind.hasSuffix(":attempt"))
    #expect(store.transaction.ledger[1].outcomeKind.hasSuffix(":failed"))
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

@Test func localFileSinkRejectsDifferentBytesForTheSameKey() async throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-sink-conflict-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let payload = dir.appendingPathComponent("src.ndjson")
    try "one\n".write(to: payload, atomically: true, encoding: .utf8)
    let sink = LocalFileSink(directory: dir)
    let key = BatchID(rawValue: "same-key")
    _ = try await sink.send(fileHandle: payload.path, idempotencyKey: key)
    try "different\n".write(to: payload, atomically: true, encoding: .utf8)
    await #expect(throws: LocalFileSinkError.idempotencyConflict) {
        _ = try await sink.send(fileHandle: payload.path, idempotencyKey: key)
    }
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

@Test func checkpointEnvelopeRoundTripsAndRejectsForwardVersions() throws {
    let envelope = CheckpointEnvelope(
        tzDatabaseVersion: "2024a",
        epoch: 9,
        adapterAnchor: Data([0xAB, 0xCD])
    )
    let restored = try CheckpointEnvelope.decoded(envelope.encoded())
    #expect(restored.tzDatabaseVersion == "2024a")
    #expect(restored.epoch == 9)
    #expect(restored.adapterAnchor == Data([0xAB, 0xCD]))
    #expect(throws: CheckpointError.corrupt) {
        _ = try CheckpointEnvelope.decoded(Data("nope".utf8))
    }
    var forward = envelope.encoded()
    forward[4] = UInt8(CheckpointEnvelope.currentFormat + 1)
    #expect(throws: CheckpointError.unsupportedFormat) {
        _ = try CheckpointEnvelope.decoded(forward)
    }
}

@Test func corruptCheckpointFailsClosedWithoutResettingTheCursor() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let store = MemoryStateStore()
    store.transaction.cursors[metric] = CursorSnapshot(
        metric: metric,
        epoch: 1,
        anchorBlob: Data("torn".utf8)
    )
    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-corrupt-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    let run = ExportRun(
        source: FixtureSource(pages: []),
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    )
    await #expect(throws: CheckpointError.corrupt) {
        _ = try await run.run()
    }
    #expect(store.transaction.cursors[metric]?.anchorBlob == Data("torn".utf8))
    #expect(store.transaction.journal.last?.outcomeKind == "failed")
    #expect(store.transaction.journal.last?.detail == "anchor_undecodable")
}

@Test func queueAdmissionEvictsOldestBatchesAndRecordsGaps() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([1]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let store = MemoryStateStore()
    let policy = QueuePolicy(cap: 10, lowWatermark: 6)
    try await store.transact {
        try $0.commitBatch(
            PendingBatch(
                id: BatchID(rawValue: "old"),
                payloadURL: "/tmp/old",
                expectedRecords: 1,
                byteCount: 8
            ),
            advancing: CursorAdvance(page: page, epoch: 1)
        )
    }
    let incoming = PendingBatch(
        id: BatchID(rawValue: "new"),
        payloadURL: "/tmp/new",
        expectedRecords: 1,
        byteCount: 8
    )
    let victims = try await store.transact { tx in
        let evicted = try QueueAdmission.makeRoom(for: incoming.byteCount, on: tx, policy: policy)
        try tx.commitBatch(incoming, advancing: CursorAdvance(page: page, epoch: 2))
        return evicted
    }
    #expect(victims.map(\.id.rawValue) == ["old"])
    #expect(try store.transaction.pendingBatches().map(\.id.rawValue) == ["new"])
    #expect(store.transaction.gaps.map(\.rangeDescription) == ["queue_eviction:8"])
    await #expect(throws: QueueAdmissionError.blocked) {
        try await store.transact { tx in
            _ = try QueueAdmission.makeRoom(
                for: 100,
                on: tx,
                policy: policy
            )
        }
    }
}

@Test func sqlitePersistsEmittedIndexOnCommit() async throws {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-index-\(UUID().uuidString).sqlite")
        .path
    let store = try SQLiteStateStore(path: path)
    let metric = MetricID(rawValue: "heartRate")
    let first = EmittedIndexRow(
        uuid: "11111111-1111-1111-1111-111111111111",
        metric: metric,
        day: "2024-01-01",
        digest: "aa",
        batchID: BatchID(rawValue: "b1")
    )
    let updated = EmittedIndexRow(
        uuid: first.uuid,
        metric: metric,
        day: "2024-01-02",
        digest: "bb",
        batchID: BatchID(rawValue: "b2")
    )
    try await store.transact { try $0.upsertEmittedIndex(first) }
    #expect(try await store.transact { try $0.loadEmittedIndex(uuid: first.uuid) } == first)
    try await store.transact { try $0.upsertEmittedIndex(updated) }
    #expect(try await store.transact { try $0.loadEmittedIndex(uuid: first.uuid) } == updated)
}
