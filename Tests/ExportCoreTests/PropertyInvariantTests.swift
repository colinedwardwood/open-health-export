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

@Test func p6DeltaAndFullExportsConvergeForSeededMutationStreams() throws {
    for seed in 1 ... 50 {
        var rng = PropertyRNG(seed: UInt64(seed))
        var model: [String: SampleRecord] = [:]
        var deltaReceiver = ReferenceReceiver()
        var retired: Set<String> = []

        for sequence in 1 ... 80 {
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
        #expect(
            deltaReceiver.quantities == fullReceiver.quantities,
            "P6 failed for seed \(seed)"
        )
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
        let cumulative = values.map {
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
        #expect(abs((sum.value ?? 0) - expected) < 0.000_001)
        #expect(sum.sampleCount == count)

        let mean = AggregateFold.foldDay(
            metric: MetricCatalog.heartRate.id,
            day: "2026-01-01",
            samples: values
        )
        #expect(abs((mean.value ?? 0) * Double(count) - expected) < 0.000_001)
        #expect(mean.sampleCount == count)
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
        let trace = try await statefulExportTrace(seed: seed, steps: 12)
        #expect(trace.live == Set(trace.model.keys), "P4 seed \(seed)")
    }
}

@Test func p5PersistedCursorNeverRegresses() async throws {
    for seed in 1 ... 8 {
        let trace = try await statefulExportTrace(seed: seed, steps: 12)
        var previous: UInt32 = 0
        for epoch in trace.epochs {
            #expect(epoch >= previous, "P5 seed \(seed)")
            previous = epoch
        }
    }
}

@Test func p7TombstonesAreTerminalInTheLiveSet() async throws {
    for seed in 1 ... 8 {
        let trace = try await statefulExportTrace(seed: seed, steps: 12)
        for uuid in trace.retired {
            #expect(!trace.live.contains(uuid), "P7 seed \(seed)")
        }
    }
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
        .appendingPathComponent("ohe-p13-\(UUID().uuidString)")
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

@Test func p2ReExportOfTheSameScopeIsByteIdentical() throws {
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
        #expect(forward == backward, "P9 order dependence seed \(seed)")
    }
}

@Test func p11BucketKeyIsStableUnderRecomputation() {
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
        #expect(first?.record.bucketKey == second?.record.bucketKey, "P11 key drift seed \(seed)")
    }
}

@Test func p15AtomicWriteLeavesPriorCompleteBytesOrAbsentNeverTorn() throws {
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

@Test func qa19EveryCorrectnessPropertyHasANamedTest() throws {
    let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    var found = Set<Int>()
    let enumerator = FileManager.default.enumerator(at: tests, includingPropertiesForKeys: nil)
    let pattern = try NSRegularExpression(pattern: #"@Test func p(1[0-6]|[1-9])[A-Z]"#)
    for case let file as URL in enumerator! where file.pathExtension == "swift" {
        let text = try String(contentsOf: file, encoding: .utf8)
        let ns = text as NSString
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            found.insert(Int(ns.substring(with: match.range(at: 1)))!)
        }
    }
    #expect(found == Set(1 ... 16), "missing \(Set(1 ... 16).subtracting(found).sorted())")
}
