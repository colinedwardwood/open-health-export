import CoreDomain
import CorrectnessEngine
import EnginePorts
import FileWriteKit
import Foundation
import MetricCatalog
import SinkLocalFile
import Testing
import TestSupport
import WireFormat

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
        var rng = PropertyRNG(seed: UInt64(seed))
        var model: [String: SampleRecord] = [:]
        var retired: Set<String> = []
        let metric = MetricCatalog.heartRate.id
        let store = MemoryStateStore()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohe-model-\(seed)-\(UUID().uuidString)")
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var receiver = ReferenceReceiver()
        var previousEpoch: UInt32 = 0
        var pages: [SamplePage] = []

        for step in 1 ... 24 {
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
            let epoch = cursor?.epoch ?? 0
            #expect(epoch >= previousEpoch, "P5 cursor regression seed \(seed)")
            previousEpoch = epoch
            #expect(try await store.transact { try $0.pendingBatches() }.isEmpty)
        }

        let delivered = try FileManager.default.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "ndjson" }
        for url in delivered.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try receiver.ingest(ndjson: String(contentsOf: url, encoding: .utf8))
        }
        #expect(
            Set(receiver.quantities.keys) == Set(model.keys),
            "P4 live set diverged for seed \(seed)"
        )
        for uuid in retired {
            #expect(receiver.quantities[uuid] == nil, "P7 tombstone not terminal seed \(seed)")
        }
    }
}
