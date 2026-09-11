// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation
import MetricCatalog
import WireFormat

@main
struct CorpusGen {
    static func main() throws {
        let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
        var buffer = Data()
        buffer.append(try provenanceHeader(options: options))
        buffer.append(0x0A)
        for index in 0..<options.resolvedCount {
            let declaration = MetricCatalog.all[index % MetricCatalog.all.count]
            let sample = DemoCorpus.sample(at: index, seed: options.seed, declaration: declaration)
            let envelope = WireEnvelope(
                exporterId: "00000000-0000-4000-8000-000000000082",
                seq: index + 1,
                emittedAt: sample.observedAt,
                observedAt: sample.observedAt
            )
            buffer.append(
                Data(
                    try record(
                        index: index,
                        sample: sample,
                        envelope: envelope,
                        tier: options.tier,
                        seed: options.seed
                    ).utf8
                )
            )
            buffer.append(0x0A)
            if buffer.count >= 1_048_576 {
                try FileHandle.standardOutput.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty {
            try FileHandle.standardOutput.write(contentsOf: buffer)
        }
    }

    private static func provenanceHeader(options: Options) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "batchId": "82000000-0000-4000-8000-000000000000",
                "emittedAt": "2020-01-01T00:00:00Z",
                "exporterId": "00000000-0000-4000-8000-000000000082",
                "generatorVersion": 1,
                "kind": "batch.header",
                "mode": "samples",
                "producer": ["name": "ohe-corpusgen", "version": "1"],
                "reason": "manual",
                "recordCount": options.resolvedCount,
                "seed": options.seed,
                "seq": 0,
                "spec": "ohe.wire/1",
                "specVersion": "1.0",
                "synthetic": true,
                "tier": options.tier.rawValue,
                "types": Array(
                    Set(
                        MetricCatalog.all.map(\.wireId)
                            + DemoCorpus.categoryTypes.map(\.metricID)
                            + ["blood_pressure", "workout", "state_of_mind",
                               "electrocardiogram", "audiogram", "medication_dose"]
                    )
                ).sorted(),
            ],
            options: [.sortedKeys]
        )
    }

    static func record(
        index: Int,
        sample: SampleRecord,
        envelope: WireEnvelope,
        tier: SyntheticCorpusTier,
        seed: UInt64
    ) throws -> String {
        if tier == .t2, index > 0, index.isMultiple(of: 257) {
            let priorIndex = index - 1
            let declaration = MetricCatalog.all[
                priorIndex % MetricCatalog.all.count
            ]
            let prior = DemoCorpus.sample(
                at: priorIndex,
                seed: seed,
                declaration: declaration
            )
            return try NativeWire.encode(
                TombstoneRecord(key: prior.key, metric: prior.metric),
                envelope: envelope
            )
        }
        switch index % 100 {
        case 0:
            let category = DemoCorpus.categoryTypes[
                (index / 100) % DemoCorpus.categoryTypes.count
            ]
            let provenance = Self.provenance(
                sourceIndex: (index / 100 / DemoCorpus.categoryTypes.count)
                    % DemoCorpus.sources.count
            )
            let duration: TimeInterval = category.metricID == "sleep_analysis"
                ? 8 * 60 * 60
                : ((index / 100).isMultiple(of: 2) ? 0 : 15 * 60)
            let end = try shifted(sample.start, seconds: duration)
            return try NativeWire.encode(
                CategoryRecord(
                    key: RecordKey(uuid: fixtureUUID(family: 1, index: index)),
                    metric: MetricID(rawValue: category.metricID),
                    healthKitIdentifier: category.healthKitIdentifier,
                    start: sample.start,
                    end: end,
                    timeZoneOffsetMinutes: sample.timeZoneOffsetMinutes,
                    timeZoneSource: sample.timeZoneSource,
                    categoryValue: category.value,
                    categoryName: category.valueName,
                    durationSeconds: duration > 0 ? duration : nil,
                    observedAt: end,
                    source: provenance.source,
                    device: provenance.device,
                    wasUserEntered: provenance.wasUserEntered
                ),
                envelope: envelope
            )
        case 1:
            let provenance = Self.provenance(
                sourceIndex: (index / 100) % DemoCorpus.sources.count
            )
            let systolic = CorrelationComponent(
                key: RecordKey(uuid: fixtureUUID(family: 2, index: index)),
                metric: MetricID(rawValue: "blood_pressure_systolic"),
                healthKitIdentifier: "HKQuantityTypeIdentifierBloodPressureSystolic",
                value: 100 + Double(index % 40),
                unit: CanonicalUnit(symbol: "mmHg")
            )
            let diastolic = CorrelationComponent(
                key: RecordKey(uuid: fixtureUUID(family: 3, index: index)),
                metric: MetricID(rawValue: "blood_pressure_diastolic"),
                healthKitIdentifier: "HKQuantityTypeIdentifierBloodPressureDiastolic",
                value: 60 + Double(index % 25),
                unit: CanonicalUnit(symbol: "mmHg")
            )
            return try NativeWire.encode(
                CorrelationRecord(
                    key: RecordKey(uuid: fixtureUUID(family: 4, index: index)),
                    metric: MetricID(rawValue: "blood_pressure"),
                    healthKitIdentifier: "HKCorrelationTypeIdentifierBloodPressure",
                    correlationType: "bloodPressure",
                    start: sample.start,
                    end: sample.end,
                    timeZoneOffsetMinutes: sample.timeZoneOffsetMinutes,
                    timeZoneSource: sample.timeZoneSource,
                    components: [systolic, diastolic],
                    observedAt: sample.observedAt,
                    source: provenance.source,
                    device: provenance.device,
                    wasUserEntered: provenance.wasUserEntered
                ),
                envelope: envelope
            )
        case 2:
            let provenance = Self.provenance(
                sourceIndex: (index / 100) % DemoCorpus.sources.count
            )
            return try NativeWire.encode(
                WorkoutRecord(
                    key: RecordKey(uuid: fixtureUUID(family: 5, index: index)),
                    activityType: "running",
                    activityTypeRaw: 37,
                    start: sample.start,
                    end: try shifted(sample.start, seconds: 3_600),
                    timeZoneOffsetMinutes: sample.timeZoneOffsetMinutes,
                    timeZoneSource: sample.timeZoneSource,
                    durationSeconds: 3_300,
                    isIndoor: false,
                    totals: [
                        "active_energy": WorkoutTotal(
                            value: sample.value,
                            unit: CanonicalUnit(symbol: "kcal"),
                            statistic: .sum
                        ),
                    ],
                    hasRoute: index % 200 == 2,
                    seriesIncluded: index % 200 == 2 ? ["workoutRoute"] : [],
                    observedAt: sample.observedAt,
                    source: provenance.source,
                    device: provenance.device,
                    wasUserEntered: provenance.wasUserEntered
                ),
                envelope: envelope
            )
        case 3:
            let provenance = Self.provenance(
                sourceIndex: (index / 100) % DemoCorpus.sources.count
            )
            return try NativeWire.encode(
                StateOfMindRecord(
                    key: RecordKey(uuid: fixtureUUID(family: 6, index: index)),
                    start: sample.start,
                    end: sample.end,
                    timeZoneOffsetMinutes: sample.timeZoneOffsetMinutes,
                    timeZoneSource: sample.timeZoneSource,
                    kindOfEntry: index.isMultiple(of: 200) ? "dailyMood" : "momentaryEmotion",
                    valence: Double((index % 21) - 10) / 10,
                    valenceClassification: "pleasant",
                    labels: ["content", "happy"],
                    associations: ["community"],
                    observedAt: sample.observedAt,
                    source: provenance.source,
                    device: provenance.device,
                    wasUserEntered: provenance.wasUserEntered
                ),
                envelope: envelope
            )
        case 4:
            let parent = fixtureUUID(family: 7, index: index)
            return try NativeWire.encode(
                SeriesRecord(
                    parentUUID: parent,
                    parentStart: sample.start,
                    chunkIndex: 0,
                    chunkCount: 1,
                    startIndex: 0,
                    payload: .ecgVoltage(
                        voltages: [Double(index % 50), -Double(index % 17)],
                        samplingHz: 512
                    )
                ),
                envelope: envelope
            )
        case 5:
            let provenance = Self.provenance(
                sourceIndex: (index / 100) % DemoCorpus.sources.count
            )
            return try NativeWire.encode(
                AudiogramRecord(
                    key: RecordKey(uuid: fixtureUUID(family: 8, index: index)),
                    start: sample.start,
                    end: sample.end,
                    timeZoneOffsetMinutes: sample.timeZoneOffsetMinutes,
                    timeZoneSource: sample.timeZoneSource,
                    sensitivityPoints: [
                        AudiogramSensitivityPoint(
                            frequencyHz: 500,
                            leftEarDbHL: 10,
                            rightEarDbHL: 12
                        ),
                        AudiogramSensitivityPoint(
                            frequencyHz: 2000,
                            leftEarDbHL: 15
                        ),
                    ],
                    observedAt: sample.observedAt,
                    source: provenance.source,
                    device: provenance.device,
                    wasUserEntered: provenance.wasUserEntered
                ),
                envelope: envelope
            )
        case 6:
            let provenance = Self.provenance(
                sourceIndex: (index / 100) % DemoCorpus.sources.count
            )
            return try NativeWire.encode(
                MedicationDoseRecord(
                    key: RecordKey(uuid: fixtureUUID(family: 9, index: index)),
                    start: sample.start,
                    end: sample.end,
                    timeZoneOffsetMinutes: sample.timeZoneOffsetMinutes,
                    timeZoneSource: sample.timeZoneSource,
                    medicationName: "Synthetic lisinopril",
                    doseQuantity: 10,
                    doseUnit: "mg",
                    status: "taken",
                    observedAt: sample.observedAt,
                    source: provenance.source,
                    device: provenance.device,
                    wasUserEntered: provenance.wasUserEntered
                ),
                envelope: envelope
            )
        default:
            var quantity = sample
            if tier == .t2, index > 260, index.isMultiple(of: 263),
               (index - 260) % 100 >= 3 {
                let priorIndex = index - 260
                let declaration = MetricCatalog.all[
                    priorIndex % MetricCatalog.all.count
                ]
                quantity.key = DemoCorpus.sample(
                    at: priorIndex,
                    seed: seed,
                    declaration: declaration
                ).key
            }
            return try NativeWire.encode(quantity, envelope: envelope)
        }
    }

    static func shifted(_ timestamp: String, seconds: TimeInterval) throws -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: timestamp) else {
            throw OptionError.invalidValue
        }
        return formatter.string(from: date.addingTimeInterval(seconds))
    }

    static func fixtureUUID(family: Int, index: Int) -> String {
        String(
            format: "82%06x-0000-4000-8000-%012llx",
            family,
            UInt64(index)
        )
    }

    static func provenance(
        sourceIndex: Int
    ) -> (source: SampleSourceIdentity, device: SampleDevice, wasUserEntered: Bool) {
        let source = DemoCorpus.sources[sourceIndex]
        return (
            source,
            SampleDevice(
                name: source.name,
                manufacturer: "Synthetic",
                model: "fixture-\(sourceIndex + 1)",
                softwareVersion: "1.0"
            ),
            sourceIndex == DemoCorpus.sources.count - 1
        )
    }
}

private struct Options {
    var seed: UInt64 = 1
    var tier: SyntheticCorpusTier = .t0
    var count: Int?
    var resolvedCount: Int { count ?? tier.defaultCount }

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            guard index + 1 < arguments.count else { throw OptionError.missingValue }
            switch arguments[index] {
            case "--seed":
                guard let parsed = UInt64(arguments[index + 1]) else { throw OptionError.invalidValue }
                seed = parsed
            case "--count":
                guard let parsed = Int(arguments[index + 1]), parsed >= 0 else {
                    throw OptionError.invalidValue
                }
                count = parsed
            case "--tier":
                guard let parsed = SyntheticCorpusTier(
                    rawValue: arguments[index + 1].uppercased()
                ) else {
                    throw OptionError.invalidValue
                }
                tier = parsed
            default:
                throw OptionError.unknownOption
            }
            index += 2
        }
    }
}

private enum OptionError: Error {
    case missingValue
    case invalidValue
    case unknownOption
}
