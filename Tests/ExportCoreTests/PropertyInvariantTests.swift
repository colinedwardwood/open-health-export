import CoreDomain
import CorrectnessEngine
import Foundation
import MetricCatalog
import Testing
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
