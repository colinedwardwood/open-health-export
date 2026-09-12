// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CoreTemporal
import CorrectnessEngine
import DestinationTrust
import EnginePorts
import FileWriteKit
import Foundation
import MetricCatalog
import SinkLocalFile
import Testing
import TestSupport
@testable import WireFormat

private struct PropertyRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

private enum StatefulSinkError: Error {
    case injected
}

#if DEBUG
private final class TransitionCoverageRecorder: ExportFaultInjector, @unchecked Sendable {
    private let lock = NSLock()
    private var locations: Set<ExportFaultLocation> = []

    func hit(_ location: ExportFaultLocation) {
        lock.lock()
        locations.insert(location)
        lock.unlock()
    }

    func snapshot() -> Set<ExportFaultLocation> {
        lock.lock()
        defer { lock.unlock() }
        return locations
    }
}
#endif

private actor StatefulPropertySink: DestinationSink {
    private var failuresRemaining: Int
    private var receiver = ReferenceReceiver()

    init(failuresRemaining: Int) {
        self.failuresRemaining = failuresRemaining
    }

    func allowDelivery() {
        failuresRemaining = 0
    }

    func send(fileHandle: String, idempotencyKey: BatchID) async throws -> DeliveryReceipt {
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw StatefulSinkError.injected
        }
        let text = try String(contentsOfFile: fileHandle, encoding: .utf8)
        try receiver.ingest(ndjson: text)
        return DeliveryReceipt(
            batchID: idempotencyKey,
            accepted: text.split(separator: "\n").count,
            statusOnly: false
        )
    }

    func liveUUIDs() -> Set<String> {
        Set(receiver.quantities.keys)
    }
}

#if DEBUG
@Test func anchorCheckpointTransitionGraphIsFullyCovered() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-transition-coverage-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let destination = root.appendingPathComponent("destination")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let metric = MetricCatalog.heartRate.id
    let page = SamplePage(
        samples: [propertySample(uuid: propertyUUID(33), value: 72, minute: 1)],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0x33]),
        observedThrough: Date(timeIntervalSince1970: 1)
    )
    let recorder = TransitionCoverageRecorder()
    var run = ExportRun(
        source: FixtureSource(pages: [page]),
        destination: .testing(LocalFileSink(directory: destination)),
        store: MemoryStateStore(),
        metric: metric,
        scratchDirectory: root.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    )
    run.faults = recorder
    #expect(try await run.run().kind == .success)
    #expect(
        recorder.snapshot() == Set(ExportFaultLocation.allCases),
        "Every declared anchor/checkpoint transition must execute in the success path"
    )
}
#endif

private func propertyUUID(_ index: Int) -> String {
    String(format: "00000000-0000-4000-8000-%012x", index)
}

private func propertySample(uuid: String, value: Double, minute: Int) -> SampleRecord {
    let timestamp = String(format: "2026-01-01T00:%02d:00Z", minute % 60)
    return SampleRecord(
        key: RecordKey(uuid: uuid),
        metric: MetricCatalog.heartRate.id,
        start: timestamp,
        end: timestamp,
        timeZoneOffsetMinutes: 0,
        timeZoneSource: .unknown,
        value: value,
        unit: CanonicalUnit(symbol: "bpm"),
        observedAt: timestamp
    )
}

private func deltaAndFullExportsConverge(seed: Int, sequences: Int) throws -> Bool {
    var rng = PropertyRNG(seed: UInt64(seed))
    var model: [String: SampleRecord] = [:]
    var deltaReceiver = ReferenceReceiver()
    var retired: Set<String> = []

    for sequence in 1 ... sequences {
        let slot = Int(rng.next() % 24)
        let uuid = propertyUUID(slot)
        if retired.contains(uuid) { continue }
        let delete = rng.next() % 4 == 0 && model[uuid] != nil
        let samples: [SampleRecord]
        let tombstones: [TombstoneRecord]
        if delete {
            model.removeValue(forKey: uuid)
            retired.insert(uuid)
            samples = []
            tombstones = [
                TombstoneRecord(
                    key: RecordKey(uuid: uuid),
                    metric: MetricCatalog.heartRate.id
                ),
            ]
        } else {
            let sample = propertySample(
                uuid: uuid,
                value: Double(rng.next() % 10_000) / 10,
                minute: sequence
            )
            model[uuid] = sample
            samples = [sample]
            tombstones = []
        }
        var envelope = testEnvelope()
        envelope.seq = sequence
        let delta = try NativeWire.encode(
            samples: samples,
            tombstones: tombstones,
            metric: MetricCatalog.heartRate.id,
            batchID: BatchID(rawValue: propertyUUID(seed * 100 + sequence)),
            envelope: envelope
        )
        try deltaReceiver.ingest(ndjson: String(decoding: delta, as: UTF8.self))
    }

    let full = try NativeWire.encode(
        samples: Array(model.values),
        tombstones: [],
        metric: MetricCatalog.heartRate.id,
        batchID: BatchID(rawValue: propertyUUID(seed)),
        envelope: testEnvelope()
    )
    var fullReceiver = ReferenceReceiver()
    try fullReceiver.ingest(ndjson: String(decoding: full, as: UTF8.self))
    return deltaReceiver.quantities == fullReceiver.quantities
}

@Test func p6DeltaAndFullExportsConvergeForSeededMutationStreams() throws {
    for seed in 1 ... 50 {
        guard try !deltaAndFullExportsConverge(seed: seed, sequences: 80) else {
            continue
        }
        var shrunk = 80
        for sequences in 1 ... 80 {
            if try !deltaAndFullExportsConverge(seed: seed, sequences: sequences) {
                shrunk = sequences
                break
            }
        }
        Issue.record("P6 seed \(seed), shrunk command prefix \(shrunk)")
    }
}

@Test func p10CumulativeAndMeanFoldsConserveGeneratedValues() {
    for seed in 1 ... 500 {
        var rng = PropertyRNG(seed: UInt64(seed))
        let count = Int(rng.next() % 40) + 1
        let values = (0 ..< count).map { index in
            propertySample(
                uuid: propertyUUID(seed * 100 + index),
                value: Double(rng.next() % 100_000) / 100,
                minute: index
            )
        }
        func conserves(_ candidate: [SampleRecord]) -> Bool {
            let cumulative = candidate.map {
                SampleRecord(
                    key: $0.key,
                    metric: MetricCatalog.stepCount.id,
                    start: $0.start,
                    end: $0.end,
                    timeZoneOffsetMinutes: $0.timeZoneOffsetMinutes,
                    timeZoneSource: $0.timeZoneSource,
                    value: $0.value,
                    unit: CanonicalUnit(symbol: "count"),
                    observedAt: $0.observedAt
                )
            }
            let expected = cumulative.map(\.value).reduce(0, +)
            let sum = AggregateFold.foldDay(
                metric: MetricCatalog.stepCount.id,
                day: "2026-01-01",
                samples: cumulative
            )
            let mean = AggregateFold.foldDay(
                metric: MetricCatalog.heartRate.id,
                day: "2026-01-01",
                samples: candidate
            )
            return abs((sum.value ?? 0) - expected) < 0.000_001
                && sum.sampleCount == candidate.count
                && abs((mean.value ?? 0) * Double(candidate.count) - expected) < 0.000_001
                && mean.sampleCount == candidate.count
        }
        if !conserves(values) {
            var shrinking = values
            while shrinking.count > 1 {
                let candidate = Array(shrinking.dropLast())
                guard !conserves(candidate) else { break }
                shrinking = candidate
            }
            Issue.record("P10 seed \(seed), shrunk sample count \(shrinking.count)")
        }
    }
}

@Test func statefulCommandModelConvergesWithEngineForSeededSequences() async throws {
    for seed in 1 ... 20 {
        let trace = try await statefulExportTrace(seed: seed)
        #expect(trace.live == Set(trace.model.keys), "P4 live set diverged for seed \(seed)")
        var previous: UInt32 = 0
        for epoch in trace.epochs {
            #expect(epoch >= previous, "P5 cursor regression seed \(seed)")
            previous = epoch
        }
        for uuid in trace.retired {
            #expect(!trace.live.contains(uuid), "P7 tombstone not terminal seed \(seed)")
        }
    }
}

private struct StatefulExportTrace {
    var model: [String: SampleRecord]
    var retired: Set<String>
    var epochs: [UInt32]
    var live: Set<String>
}

private func cursorIsMonotonic(_ epochs: [UInt32]) -> Bool {
    zip(epochs, epochs.dropFirst()).allSatisfy { pair in
        pair.0 <= pair.1
    }
}

private func firstFailingStatefulPrefix(
    seed: Int,
    maximumSteps: Int,
    property: (StatefulExportTrace) -> Bool
) async throws -> (trace: StatefulExportTrace, steps: Int)? {
    let full = try await statefulExportTrace(seed: seed, steps: maximumSteps)
    guard !property(full) else { return nil }
    for steps in 1 ... maximumSteps {
        let candidate = try await statefulExportTrace(seed: seed, steps: steps)
        if !property(candidate) {
            return (candidate, steps)
        }
    }
    return (full, maximumSteps)
}

private func statefulExportTrace(seed: Int, steps: Int = 24) async throws -> StatefulExportTrace {
    var rng = PropertyRNG(seed: UInt64(seed))
    var model: [String: SampleRecord] = [:]
    var retired: Set<String> = []
    var epochs: [UInt32] = []
    let metric = MetricCatalog.heartRate.id
    let store = MemoryStateStore()
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-model-\(seed)-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let destination = root.appendingPathComponent("destination")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    var pages: [SamplePage] = []

    for step in 1 ... steps {
        let slot = Int(rng.next() % 12)
        let uuid = propertyUUID(slot)
        if retired.contains(uuid) { continue }
        let delete = rng.next() % 5 == 0 && model[uuid] != nil
        let samples: [SampleRecord]
        let tombstones: [TombstoneRecord]
        if delete {
            model.removeValue(forKey: uuid)
            retired.insert(uuid)
            samples = []
            tombstones = [
                TombstoneRecord(key: RecordKey(uuid: uuid), metric: metric),
            ]
        } else {
            let sample = propertySample(
                uuid: uuid,
                value: Double(rng.next() % 10_000) / 10,
                minute: step
            )
            model[uuid] = sample
            samples = [sample]
            tombstones = []
        }
        pages.append(
            SamplePage(
                samples: samples,
                tombstones: tombstones,
                metric: metric,
                anchorBlob: Data([UInt8(step)]),
                observedThrough: Date(timeIntervalSince1970: TimeInterval(step))
            )
        )
        var envelope = testEnvelope()
        envelope.seq = step
        let run = ExportRun(
            source: FixtureSource(pages: pages),
            destination: .testing(LocalFileSink(directory: destination)),
            store: store,
            metric: metric,
            scratchDirectory: root.appendingPathComponent("scratch-\(step)"),
            envelope: envelope
        )
        let outcome = try await run.run()
        #expect(outcome.kind == .success, "seed \(seed) step \(step)")
        let cursor = try await store.transact { try $0.loadCursor(metric: metric) }
        epochs.append(cursor?.epoch ?? 0)
        #expect(try await store.transact { try $0.pendingBatches() }.isEmpty)
    }

    var receiver = ReferenceReceiver()
    let delivered = try FileManager.default.contentsOfDirectory(
        at: destination,
        includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "ndjson" }
    for url in delivered.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        try receiver.ingest(ndjson: String(contentsOf: url, encoding: .utf8))
    }
    return StatefulExportTrace(
        model: model,
        retired: retired,
        epochs: epochs,
        live: Set(receiver.quantities.keys)
    )
}

@Test func highRiskStatefulCommandsPreserveQueueCursorAndDestinationInvariants() async throws {
    let metric = MetricCatalog.heartRate.id
    let uuid = propertyUUID(999)
    let sample = propertySample(uuid: uuid, value: 72, minute: 1)
    let page = SamplePage(
        samples: [sample],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([1]),
        observedThrough: Date(timeIntervalSince1970: 1)
    )
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-stateful-high-risk-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = MemoryStateStore()
    let sink = StatefulPropertySink(failuresRemaining: 1)
    let destination = VerifiedDestination.testing(sink)
    let run = ExportRun(
        source: FixtureSource(pages: [page]),
        destination: destination,
        store: store,
        metric: metric,
        scratchDirectory: root,
        envelope: testEnvelope()
    )

    // destinationFail ⨟ resume: the committed cursor and batch survive the failed send.
    var failed = false
    do {
        _ = try await run.run()
    } catch {
        failed = true
    }
    #expect(failed)
    let committedCursor = try await store.transact { try $0.loadCursor(metric: metric) }
    #expect(committedCursor?.epoch == 1)
    #expect(try await store.transact { try $0.pendingBatches() }.count == 1)
    await sink.allowDelivery()
    _ = try await PendingDeliveryRunner(
        destination: destination,
        store: store
    ).runOnce()
    #expect(try await store.transact { try $0.pendingBatches() }.isEmpty)
    #expect(await sink.liveUUIDs() == [uuid])

    // revokeAuth ⨟ grantAuth: per-type state is purged and replay remains idempotent.
    try await store.purgeType(
        metric: metric,
        reason: TypeDisableReason.authorizationRevoked,
        destination: "property",
        atEpoch: 2
    )
    #expect(try await store.transact { try $0.loadCursor(metric: metric) } == nil)
    #expect(try await store.transact { try $0.loadTypeStatus(metric: metric) }?.disabled == true)
    try await store.reenableType(metric: metric, reason: "property_grant")
    #expect(try await store.transact { try $0.loadTypeStatus(metric: metric) }?.disabled == false)
    _ = try await run.run()
    #expect(await sink.liveUUIDs() == [uuid])

    // fillQueue: eviction is oldest-first and every loss is represented by one gap.
    for index in 1 ... 2 {
        try await store.transact { tx in
            try tx.enqueuePending(
                PendingBatch(
                    id: BatchID(rawValue: "queue-\(index)"),
                    payloadURL: root.appendingPathComponent("queue-\(index)").path,
                    expectedRecords: 1,
                    byteCount: 8,
                    metric: metric,
                    createdAtEpoch: TimeInterval(index)
                )
            )
        }
    }
    let evicted = try await store.transact {
        try QueueAdmission.makeRoom(
            for: 3,
            on: $0,
            policy: QueuePolicy(cap: 10, lowWatermark: 4)
        )
    }
    #expect(evicted.map(\.id.rawValue) == ["queue-1", "queue-2"])
    #expect(try await store.transact { try $0.loadGaps() }.count == 2)

    // corruptCheckpoint: the engine fails explicitly and never resets to a zero anchor.
    store.transaction.cursors[metric] = CursorSnapshot(
        metric: metric,
        epoch: 9,
        anchorBlob: Data("not-a-checkpoint".utf8)
    )
    var corruptionRejected = false
    do {
        _ = try await run.run()
    } catch {
        corruptionRejected = true
    }
    #expect(corruptionRejected)
    #expect(store.transaction.cursors[metric]?.epoch == 9)
    #expect(store.transaction.cursors[metric]?.anchorBlob == Data("not-a-checkpoint".utf8))
}

@Test func p4LiveSetMatchesTheReferenceModelAfterSeededSequences() async throws {
    for seed in 1 ... 8 {
        if let failure = try await firstFailingStatefulPrefix(
            seed: seed,
            maximumSteps: 12,
            property: { $0.live == Set($0.model.keys) }
        ) {
            Issue.record("P4 seed \(seed), shrunk command prefix \(failure.steps)")
        }
    }
}

@Test func p5PersistedCursorNeverRegresses() async throws {
    for seed in 1 ... 8 {
        if let failure = try await firstFailingStatefulPrefix(
            seed: seed,
            maximumSteps: 12,
            property: { cursorIsMonotonic($0.epochs) }
        ) {
            Issue.record("P5 seed \(seed), shrunk command prefix \(failure.steps)")
        }
    }
}

@Test func p7TombstonesAreTerminalInTheLiveSet() async throws {
    for seed in 1 ... 8 {
        if let failure = try await firstFailingStatefulPrefix(
            seed: seed,
            maximumSteps: 12,
            property: { $0.retired.isDisjoint(with: $0.live) }
        ) {
            Issue.record("P7 seed \(seed), shrunk command prefix \(failure.steps)")
        }
    }
    #expect(throws: HAEError.tombstonesNotRepresentable) {
        _ = try HAEWire.encode(
            samples: [],
            tombstones: [
                TombstoneRecord(
                    key: RecordKey(uuid: propertyUUID(7)),
                    metric: MetricCatalog.heartRate.id
                ),
            ],
            metric: MetricCatalog.heartRate.id,
            acknowledgingLoss: HAELossAccepted()
        )
    }
}

@Test func p12BoundedResourceGateStreamsEveryT1AndT2RecordUnderTheRSSCeiling() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let workflow = try String(
        contentsOf: root.appendingPathComponent(".github/workflows/nightly-volume.yml"),
        encoding: .utf8
    )
    let checker = try String(
        contentsOf: root.appendingPathComponent("Tools/exportruncheck/ExportRunCheck.swift"),
        encoding: .utf8
    )
    #expect(workflow.contains("corpusgen --tier T1 --seed 1 |"))
    #expect(workflow.contains("corpusgen --tier T2 --seed 1 |"))
    #expect(!workflow.contains("corpusgen --tier T1 --seed 1 --count"))
    #expect(workflow.contains(".build/release/exportruncheck"))
    #expect(workflow.contains("exportruncheck --page-size 10000"))
    #expect(checker.contains("private let memoryLimitMiB = 100"))
    #expect(checker.contains("NativeWire.volumeStructuralKinds"))
    #expect(NativeWire.volumeStructuralKinds.contains("tombstone"))
    #expect(NativeWire.volumeStructuralKinds.contains("sample.ecg"))
    #expect(NativeWire.volumeStructuralKinds.isSuperset(of: [
        "series.ecgVoltage",
        "series.heartbeat",
        "series.workoutRoute",
        "series.workoutMetric",
    ]))
    #expect(checker.contains("submittedRecords == exportableRecords"))
    #expect(checker.contains("peakKiB <= limitKiB"))
}

@Test func p13CorruptCheckpointDoesNotSilentlyResetTheCursor() async throws {
    let metric = MetricCatalog.heartRate.id
    let sample = propertySample(uuid: propertyUUID(13), value: 72, minute: 1)
    let page = SamplePage(
        samples: [sample],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([1]),
        observedThrough: Date(timeIntervalSince1970: 1)
    )
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-p14-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = MemoryStateStore()
    let run = ExportRun(
        source: FixtureSource(pages: [page]),
        destination: .testing(LocalFileSink(directory: root)),
        store: store,
        metric: metric,
        scratchDirectory: root.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    )
    store.transaction.cursors[metric] = CursorSnapshot(
        metric: metric,
        epoch: 9,
        anchorBlob: Data("not-a-checkpoint".utf8)
    )
    var rejected = false
    do {
        _ = try await run.run()
    } catch {
        rejected = true
    }
    #expect(rejected)
    #expect(store.transaction.cursors[metric]?.epoch == 9)
    #expect(store.transaction.cursors[metric]?.anchorBlob == Data("not-a-checkpoint".utf8))
}

@Test func p1LosslessNDJSONAndJSONRoundTripWithShrinkOnMismatch() throws {
    for seed in 1 ... 80 {
        var rng = PropertyRNG(seed: UInt64(seed))
        let count = Int(rng.next() % 8) + 1
        var samples: [SampleRecord] = []
        for index in 0 ..< count {
            samples.append(
                propertySample(
                    uuid: propertyUUID(seed * 50 + index),
                    value: Double(rng.next() % 100_000) / 100,
                    minute: index
                )
            )
        }
        var envelope = testEnvelope()
        envelope.seq = seed
        let batchID = BatchID(rawValue: propertyUUID(seed))
        func encode(_ subset: [SampleRecord]) throws -> Data {
            try NativeWire.encode(
                samples: subset,
                tombstones: [],
                metric: MetricCatalog.heartRate.id,
                batchID: batchID,
                envelope: envelope
            )
        }
        let original = try encode(samples)
        let decoded = try NativeSidecars.quantitySamples(fromNDJSON: original)
        let again = try encode(decoded)
        if original != again {
            var shrinking = samples
            while shrinking.count > 1 {
                var candidate = shrinking
                candidate.removeLast()
                let smaller = try encode(candidate)
                let smallerAgain = try encode(try NativeSidecars.quantitySamples(fromNDJSON: smaller))
                if smaller != smallerAgain {
                    shrinking = candidate
                } else {
                    break
                }
            }
            #expect(Bool(false), "P1 NDJSON round-trip failed for seed \(seed) at size \(shrinking.count)")
        }
        #expect(decoded.map(\.key.uuid) == samples.map(\.key.uuid))
        #expect(decoded.map(\.value) == samples.map(\.value))
        let json = try NativeJSON.document(fromNDJSON: original)
        let jsonObject = try JSONSerialization.jsonObject(with: json.canonical) as? [String: Any]
        let records = jsonObject?["records"] as? [Any]
        #expect(records?.count == samples.count, "P1 JSON record count seed \(seed)")
        let uuids = records?.compactMap { ($0 as? [String: Any])?["uuid"] as? String }
        #expect(uuids == samples.map(\.key.uuid))
        let csv = try NativeCSV.quantityFiles(
            samples: samples,
            envelope: envelope,
            ndjson: original
        )
        #expect(String(decoding: csv.meta, as: UTF8.self).contains("csvDropsMetadata"))
    }
}

@Test func p2ReExportOfTheSameScopeIsByteIdenticalAndDestinationIdempotent() async throws {
    for seed in 1 ... 40 {
        var rng = PropertyRNG(seed: UInt64(seed))
        let samples = [
            propertySample(
                uuid: propertyUUID(seed),
                value: Double(rng.next() % 200) + 40,
                minute: 3
            ),
        ]
        let first = try NativeWire.encode(
            samples: samples,
            tombstones: [],
            metric: MetricCatalog.heartRate.id,
            batchID: BatchID(rawValue: propertyUUID(seed)),
            envelope: testEnvelope()
        )
        let second = try NativeWire.encode(
            samples: samples,
            tombstones: [],
            metric: MetricCatalog.heartRate.id,
            batchID: BatchID(rawValue: propertyUUID(seed)),
            envelope: testEnvelope()
        )
        #expect(first == second, "P2 re-export drifted for seed \(seed)")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohe-p2-\(seed)-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload = directory.appendingPathComponent("source.ndjson")
        try first.write(to: payload)
        let sink = LocalFileSink(directory: directory)
        let key = BatchID(rawValue: propertyUUID(seed))
        _ = try await sink.send(fileHandle: payload.path, idempotencyKey: key)
        _ = try await sink.send(fileHandle: payload.path, idempotencyKey: key)
        let delivered = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "ndjson" && $0.lastPathComponent != "source.ndjson" }
        #expect(delivered.count == 1, "P2 duplicate destination object for seed \(seed)")
        #expect(try Data(contentsOf: delivered[0]) == first)
    }
}

@Test func p8DeterminismIgnoresHostileLocaleAndRepeats() throws {
    let english = TemporalContext(
        timeZoneIdentifier: "Asia/Kathmandu",
        localeIdentifier: "en_US_POSIX",
        tzDatabaseVersion: "fixture-2024"
    )
    let arabic = TemporalContext(
        timeZoneIdentifier: "Asia/Kathmandu",
        localeIdentifier: "ar_EG",
        tzDatabaseVersion: "fixture-2024"
    )
    #expect(
        BucketKey.boundsP1D(day: "2024-06-01", context: english)
            == BucketKey.boundsP1D(day: "2024-06-01", context: arabic)
    )
    for seed in 1 ... 40 {
        var rng = PropertyRNG(seed: UInt64(seed))
        let samples = [
            propertySample(
                uuid: propertyUUID(seed),
                value: Double(rng.next() % 200) + 40,
                minute: 4
            ),
        ]
        let batchID = BatchID(rawValue: propertyUUID(seed))
        let first = try NativeWire.encode(
            samples: samples,
            tombstones: [],
            metric: MetricCatalog.heartRate.id,
            batchID: batchID,
            envelope: testEnvelope()
        )
        for _ in 0 ..< 8 {
            #expect(
                try NativeWire.encode(
                    samples: samples,
                    tombstones: [],
                    metric: MetricCatalog.heartRate.id,
                    batchID: batchID,
                    envelope: testEnvelope()
                ) == first,
                "P8 drifted for seed \(seed)"
            )
        }
    }
}

@Test func p9AggregationIsIndependentOfSampleOrder() {
    for seed in 1 ... 80 {
        var rng = PropertyRNG(seed: UInt64(seed))
        let count = Int(rng.next() % 12) + 2
        var samples: [SampleRecord] = []
        for index in 0 ..< count {
            let base = propertySample(
                uuid: propertyUUID(seed * 100 + index),
                value: Double(rng.next() % 100_000) / 100,
                minute: index
            )
            samples.append(
                SampleRecord(
                    key: base.key,
                    metric: MetricCatalog.stepCount.id,
                    start: base.start,
                    end: base.end,
                    timeZoneOffsetMinutes: base.timeZoneOffsetMinutes,
                    timeZoneSource: base.timeZoneSource,
                    value: base.value,
                    unit: CanonicalUnit(symbol: "count"),
                    observedAt: base.observedAt
                )
            )
        }
        var reversed = Array(samples.reversed())
        reversed.swapAt(0, reversed.count - 1)
        let forward = AggregateFold.foldDay(
            metric: MetricCatalog.stepCount.id,
            day: "2026-01-01",
            samples: samples
        )
        let backward = AggregateFold.foldDay(
            metric: MetricCatalog.stepCount.id,
            day: "2026-01-01",
            samples: reversed
        )
        if forward != backward {
            var shrinking = samples
            while shrinking.count > 2 {
                let candidate = Array(shrinking.dropLast())
                let candidateForward = AggregateFold.foldDay(
                    metric: MetricCatalog.stepCount.id,
                    day: "2026-01-01",
                    samples: candidate
                )
                let candidateBackward = AggregateFold.foldDay(
                    metric: MetricCatalog.stepCount.id,
                    day: "2026-01-01",
                    samples: Array(candidate.reversed())
                )
                guard candidateForward != candidateBackward else { break }
                shrinking = candidate
            }
            Issue.record("P9 seed \(seed), shrunk sample count \(shrinking.count)")
        }
    }
}

@Test func aggregateBucketKeyIsStableUnderRecomputation() {
    let context = TemporalContext(
        timeZoneIdentifier: "UTC",
        localeIdentifier: "en_US_POSIX",
        tzDatabaseVersion: "2024a"
    )
    let metric = MetricCatalog.heartRate.id
    for seed in 1 ... 30 {
        var rng = PropertyRNG(seed: UInt64(seed))
        let extra = propertySample(
            uuid: propertyUUID(seed + 50),
            value: Double(rng.next() % 40) + 50,
            minute: 12
        )
        let samples = [
            propertySample(uuid: propertyUUID(seed), value: 70, minute: 1),
            extra,
        ]
        let first = AggregateDrain.planDay(
            metric: metric,
            day: "2026-01-01",
            samples: Array(samples.prefix(1)),
            context: context,
            emitSeq: 1,
            computedAt: "2026-01-02T00:00:00Z",
            observedAt: "2026-01-02T00:00:00Z",
            now: Date(timeIntervalSince1970: 1_767_225_600)
        )
        let second = AggregateDrain.planDay(
            metric: metric,
            day: "2026-01-01",
            samples: samples,
            context: context,
            emitSeq: 2,
            computedAt: "2026-01-03T00:00:00Z",
            observedAt: "2026-01-03T00:00:00Z",
            now: Date(timeIntervalSince1970: 1_767_312_000),
            priorEmitSeq: 1
        )
        #expect(first?.record.bucketKey == second?.record.bucketKey, "bucket key drift seed \(seed)")
    }
}

@Test func p14AtomicWriteLeavesPriorCompleteBytesOrAbsentNeverTorn() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-p15-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("cursor.bin")
    let prior = Data("complete-prior-state".utf8)
    let next = Data("complete-next-state-that-is-longer".utf8)
    try FileWriteKit.writeAtomically(prior, to: destination)
    FileWriteKit.$fault.withValue(.abortBeforeRename) {
        #expect(throws: FileWriteError.injectedFault) {
            try FileWriteKit.writeAtomically(next, to: destination)
        }
    }
    #expect(try Data(contentsOf: destination) == prior)
    FileWriteKit.$fault.withValue(.abortAfterTruncatingTemp(to: 4)) {
        #expect(throws: FileWriteError.injectedFault) {
            try FileWriteKit.writeAtomically(next, to: destination)
        }
    }
    #expect(try Data(contentsOf: destination) == prior)
    try FileWriteKit.writeAtomically(next, to: destination)
    #expect(try Data(contentsOf: destination) == next)
}

@Test func p15InstantInvarianceUnderZoneChange() throws {
    let sample = propertySample(
        uuid: propertyUUID(15),
        value: 72,
        minute: 15
    )
    let batchID = BatchID(rawValue: propertyUUID(1515))
    let before = try NativeWire.encode(
        samples: [sample],
        tombstones: [],
        metric: MetricCatalog.heartRate.id,
        batchID: batchID,
        envelope: testEnvelope()
    )
    for zone in ["Pacific/Auckland", "America/Los_Angeles", "Asia/Kathmandu"] {
        let context = TemporalContext(
            timeZoneIdentifier: zone,
            localeIdentifier: "en_US_POSIX",
            tzDatabaseVersion: "fixture-2024"
        )
        _ = DayBucket.containing(
            Date(timeIntervalSince1970: 1_767_225_600),
            context: context
        )
        let after = try NativeWire.encode(
            samples: [sample],
            tombstones: [],
            metric: MetricCatalog.heartRate.id,
            batchID: batchID,
            envelope: testEnvelope()
        )
        #expect(after == before, "P15 UTC instant drifted in \(zone)")
    }
}

@Test func qa19EveryCorrectnessPropertyHasANamedTest() throws {
    let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    var names: [Int: [String]] = [:]
    let enumerator = FileManager.default.enumerator(at: tests, includingPropertiesForKeys: nil)
    let pattern = try NSRegularExpression(
        pattern: #"@Test func p(1[0-6]|[1-9])([A-Z][A-Za-z0-9]*)"#
    )
    for case let file as URL in enumerator! where file.pathExtension == "swift" {
        let text = try String(contentsOf: file, encoding: .utf8)
        let ns = text as NSString
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            names[Int(ns.substring(with: match.range(at: 1)))!, default: []]
                .append(ns.substring(with: match.range(at: 2)))
        }
    }
    let semanticWitnesses: [Int: [String]] = [
        1: ["Lossless"],
        2: ["ReExport"],
        3: ["WithoutLoss"],
        4: ["NoDuplication"],
        5: ["Cursor"],
        6: ["DeltaAndFull"],
        7: ["Tombstones"],
        8: ["Determinism", "R84"],
        9: ["Aggregation"],
        10: ["Conserve"],
        11: ["Redaction", "Notification", "OTLP"],
        12: ["BoundedResource"],
        13: ["Migrates", "CorruptCheckpoint"],
        14: ["AtomicWrite", "ProcessExitDuringAnchorPersist"],
        15: ["InstantInvariance"],
        16: ["NetworkDials", "R32"],
    ]
    for property in 1 ... 16 {
        let witnesses = names[property] ?? []
        for semantic in semanticWitnesses[property] ?? [] {
            #expect(
                witnesses.contains { $0.contains(semantic) },
                "P\(property) lacks semantic witness \(semantic); found \(witnesses)"
            )
        }
    }
}

private struct QA19CounterexampleManifest: Decodable {
    var version: Int
    var cases: [QA19Counterexample]
}

private struct QA19Counterexample: Decodable {
    var id: String
    var property: Int
    var seed: UInt64
    var regressionTest: String
    var commands: [String]
    var sampleIndices: [Int]
    var faultSchedule: [String]
    var expected: String
}

private func qa19TestSource(at tests: URL) throws -> String {
    var source = ""
    let enumerator = FileManager.default.enumerator(at: tests, includingPropertiesForKeys: nil)
    for case let file as URL in enumerator! where file.pathExtension == "swift" {
        source += try String(contentsOf: file, encoding: .utf8)
    }
    return source
}

@Test func qa19CommittedCounterexamplesRemainExecutableFixedSeedRegressions() async throws {
    let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let repository = tests.deletingLastPathComponent().deletingLastPathComponent()
    let manifestURL = repository.appendingPathComponent(
        "spec/v1.0.0/fixtures/qa19-counterexamples.json"
    )
    let manifest = try JSONDecoder().decode(
        QA19CounterexampleManifest.self,
        from: Data(contentsOf: manifestURL)
    )
    #expect(manifest.version == 1)
    #expect(!manifest.cases.isEmpty)
    #expect(Set(manifest.cases.map(\.id)).count == manifest.cases.count)

    let testSource = try qa19TestSource(at: tests)
    for counterexample in manifest.cases {
        #expect(counterexample.id.hasPrefix("FIX-"), "\(counterexample.id) lacks a FIX-* ID")
        #expect((1 ... 16).contains(counterexample.property), "\(counterexample.id) has invalid P-number")
        #expect(!counterexample.commands.isEmpty, "\(counterexample.id) lacks a shrunk command sequence")
        #expect(!counterexample.sampleIndices.isEmpty, "\(counterexample.id) lacks sample indices")
        #expect(!counterexample.expected.isEmpty, "\(counterexample.id) lacks an expected invariant")
        #expect(
            testSource.contains("func \(counterexample.regressionTest)("),
            "\(counterexample.id) regression \(counterexample.regressionTest) is missing"
        )
#if DEBUG
        switch counterexample.id {
        case "FIX-QA19-001":
            let schedule = counterexample.faultSchedule.compactMap(ExportFaultLocation.init(rawValue:))
            #expect(
                schedule.count == counterexample.faultSchedule.count,
                "\(counterexample.id) contains an unknown fault seam"
            )
            try await replayP4KillResumeCounterexample(
                seed: counterexample.seed,
                faultSchedule: schedule
            )
        default:
            Issue.record("\(counterexample.id) has no executable counterexample replay")
        }
#endif
    }
}
