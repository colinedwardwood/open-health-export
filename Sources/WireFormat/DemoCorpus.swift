// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation
import MetricCatalog

/// Seeded synthetic samples shared by `corpusgen` (R-82) and demo mode (R-114).
public enum SyntheticCorpusTier: String, Sendable, Codable, CaseIterable {
    case t0 = "T0"
    case t1 = "T1"
    case t2 = "T2"

    public var defaultCount: Int {
        switch self {
        case .t0: 200
        case .t1: 10_000_000
        case .t2: 50_000_000
        }
    }

    public var dateSpanYears: Int {
        self == .t2 ? 15 : 6
    }

    public var concentratedMetricRecordCount: Int {
        self == .t2 ? 20_000_000 : 0
    }
}

public struct SyntheticCategoryType: Sendable, Equatable {
    public var metricID: String
    public var healthKitIdentifier: String
    public var value: Int
    public var valueName: String

    public init(
        metricID: String,
        healthKitIdentifier: String,
        value: Int = 0,
        valueName: String = "present"
    ) {
        self.metricID = metricID
        self.healthKitIdentifier = healthKitIdentifier
        self.value = value
        self.valueName = valueName
    }
}

public enum DemoCorpus {
    public static let categoryTypes: [SyntheticCategoryType] = [
        .init(metricID: "sleep_analysis", healthKitIdentifier: "HKCategoryTypeIdentifierSleepAnalysis", value: 3, valueName: "asleepDeep"),
        .init(metricID: "mindful_session", healthKitIdentifier: "HKCategoryTypeIdentifierMindfulSession"),
        .init(metricID: "menstrual_flow", healthKitIdentifier: "HKCategoryTypeIdentifierMenstrualFlow"),
        .init(metricID: "intermenstrual_bleeding", healthKitIdentifier: "HKCategoryTypeIdentifierIntermenstrualBleeding"),
        .init(metricID: "infrequent_menstrual_cycles", healthKitIdentifier: "HKCategoryTypeIdentifierInfrequentMenstrualCycles"),
        .init(metricID: "irregular_menstrual_cycles", healthKitIdentifier: "HKCategoryTypeIdentifierIrregularMenstrualCycles"),
        .init(metricID: "persistent_intermenstrual_bleeding", healthKitIdentifier: "HKCategoryTypeIdentifierPersistentIntermenstrualBleeding"),
        .init(metricID: "prolonged_menstrual_periods", healthKitIdentifier: "HKCategoryTypeIdentifierProlongedMenstrualPeriods"),
        .init(metricID: "cervical_mucus_quality", healthKitIdentifier: "HKCategoryTypeIdentifierCervicalMucusQuality"),
        .init(metricID: "ovulation_test_result", healthKitIdentifier: "HKCategoryTypeIdentifierOvulationTestResult"),
        .init(metricID: "progesterone_test_result", healthKitIdentifier: "HKCategoryTypeIdentifierProgesteroneTestResult"),
        .init(metricID: "pregnancy", healthKitIdentifier: "HKCategoryTypeIdentifierPregnancy"),
        .init(metricID: "pregnancy_test_result", healthKitIdentifier: "HKCategoryTypeIdentifierPregnancyTestResult"),
        .init(metricID: "contraceptive", healthKitIdentifier: "HKCategoryTypeIdentifierContraceptive"),
        .init(metricID: "lactation", healthKitIdentifier: "HKCategoryTypeIdentifierLactation"),
        .init(metricID: "sexual_activity", healthKitIdentifier: "HKCategoryTypeIdentifierSexualActivity"),
        .init(metricID: "high_heart_rate_event", healthKitIdentifier: "HKCategoryTypeIdentifierHighHeartRateEvent"),
        .init(metricID: "low_heart_rate_event", healthKitIdentifier: "HKCategoryTypeIdentifierLowHeartRateEvent"),
        .init(metricID: "irregular_heart_rhythm_event", healthKitIdentifier: "HKCategoryTypeIdentifierIrregularHeartRhythmEvent"),
        .init(metricID: "audio_exposure_event", healthKitIdentifier: "HKCategoryTypeIdentifierHeadphoneAudioExposureEvent"),
        .init(metricID: "environmental_audio_exposure_event", healthKitIdentifier: "HKCategoryTypeIdentifierAudioExposureEvent"),
        .init(metricID: "handwashing_event", healthKitIdentifier: "HKCategoryTypeIdentifierHandwashingEvent"),
        .init(metricID: "toothbrushing_event", healthKitIdentifier: "HKCategoryTypeIdentifierToothbrushingEvent"),
        .init(metricID: "appetite_changes", healthKitIdentifier: "HKCategoryTypeIdentifierAppetiteChanges"),
        .init(metricID: "bladder_incontinence", healthKitIdentifier: "HKCategoryTypeIdentifierBladderIncontinence"),
        .init(metricID: "bloating", healthKitIdentifier: "HKCategoryTypeIdentifierAbdominalCramps"),
        .init(metricID: "chills", healthKitIdentifier: "HKCategoryTypeIdentifierChills"),
        .init(metricID: "constipation", healthKitIdentifier: "HKCategoryTypeIdentifierConstipation"),
        .init(metricID: "coughing", healthKitIdentifier: "HKCategoryTypeIdentifierCoughing"),
        .init(metricID: "diarrhea", healthKitIdentifier: "HKCategoryTypeIdentifierDiarrhea"),
        .init(metricID: "dizziness", healthKitIdentifier: "HKCategoryTypeIdentifierDizziness"),
        .init(metricID: "dry_skin", healthKitIdentifier: "HKCategoryTypeIdentifierDrySkin"),
        .init(metricID: "fatigue", healthKitIdentifier: "HKCategoryTypeIdentifierFatigue"),
        .init(metricID: "fever", healthKitIdentifier: "HKCategoryTypeIdentifierFever"),
    ]

    public static let sources: [SampleSourceIdentity] = [
        SampleSourceIdentity(
            name: "Synthetic Apple Watch",
            bundleIdentifier: "com.apple.health.synthetic.watch",
            productType: "Watch6,18"
        ),
        SampleSourceIdentity(
            name: "Synthetic iPhone",
            bundleIdentifier: "com.apple.health.synthetic.phone",
            productType: "iPhone17,1"
        ),
        SampleSourceIdentity(
            name: "Synthetic CGM",
            bundleIdentifier: "org.openhealthexporter.synthetic.cgm"
        ),
        SampleSourceIdentity(
            name: "Synthetic Scale",
            bundleIdentifier: "org.openhealthexporter.synthetic.scale"
        ),
        SampleSourceIdentity(
            name: "Synthetic Workout App",
            bundleIdentifier: "org.openhealthexporter.synthetic.workout"
        ),
        SampleSourceIdentity(
            name: "Synthetic Manual Entry",
            bundleIdentifier: "com.apple.Health",
            productType: "manual"
        ),
    ]

    public static func sample(
        at index: Int,
        seed: UInt64,
        declaration: MetricDeclaration,
        tier: SyntheticCorpusTier = .t0
    ) -> SampleRecord {
        let random = splitMix64(UInt64(index) &+ seed)
        let firstYear = tier == .t2 ? 2010 : 2020
        let year = firstYear + (index / (12 * 28)) % tier.dateSpanYears
        let month = 1 + (index / 28) % 12
        let day = 1 + index % 28
        let hour = Int((random >> 8) % 24)
        let minute = Int((random >> 16) % 60)
        let timestamp = String(
            format: "%04d-%02d-%02dT%02d:%02d:00Z",
            year, month, day, hour, minute
        )
        let uuid = String(
            format: "%08x-0000-4000-8000-%012llx",
            index & 0xFFFF_FFFF,
            random & 0xFFFF_FFFF_FFFF
        )
        let value = Double(random % 100_000) / 100
        let sourceIndex = (index / max(MetricCatalog.all.count, 1)) % sources.count
        let source = sources[sourceIndex]
        return SampleRecord(
            key: RecordKey(uuid: uuid),
            metric: declaration.id,
            start: timestamp,
            end: timestamp,
            timeZoneOffsetMinutes: 0,
            timeZoneSource: .unknown,
            value: value,
            unit: declaration.canonicalUnit,
            observedAt: timestamp,
            source: source,
            device: SampleDevice(
                name: source.name,
                manufacturer: "Synthetic",
                model: "fixture-\(sourceIndex + 1)",
                softwareVersion: "1.0"
            ),
            wasUserEntered: sourceIndex == sources.count - 1
        )
    }

    public static func declaration(
        at index: Int,
        tier: SyntheticCorpusTier
    ) -> MetricDeclaration {
        if isConcentratedMetricRecord(at: index, tier: tier) {
            return MetricCatalog.heartRate
        }
        return MetricCatalog.all[index % MetricCatalog.all.count]
    }

    public static func isConcentratedMetricRecord(
        at index: Int,
        tier: SyntheticCorpusTier
    ) -> Bool {
        index < tier.concentratedMetricRecordCount
    }

    public static func splitMix64(_ input: UInt64) -> UInt64 {
        var value = input &+ 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    public static func encodeRecord(
        index: Int,
        sample: SampleRecord,
        envelope: WireEnvelope,
        tier: SyntheticCorpusTier,
        seed: UInt64
    ) throws -> String {
        if isConcentratedMetricRecord(at: index, tier: tier) {
            return try NativeWire.encode(sample, envelope: envelope)
        }
        if tier == .t2, index > 0, index.isMultiple(of: 257) {
            let priorIndex = index - 1
            let declaration = MetricCatalog.all[
                priorIndex % MetricCatalog.all.count
            ]
            let prior = Self.sample(
                at: priorIndex,
                seed: seed,
                declaration: declaration,
                tier: tier
            )
            return try NativeWire.encode(
                TombstoneRecord(key: prior.key, metric: prior.metric),
                envelope: envelope
            )
        }
        switch index % 100 {
        case 0:
            let category = categoryTypes[
                (index / 100) % categoryTypes.count
            ]
            let provenance = Self.provenance(
                sourceIndex: (index / 100 / categoryTypes.count)
                    % sources.count
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
                sourceIndex: (index / 100) % sources.count
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
                sourceIndex: (index / 100) % sources.count
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
                    seriesIncluded: index % 200 == 2 ? ["workoutRoute", "workoutMetric"] : [],
                    observedAt: sample.observedAt,
                    source: provenance.source,
                    device: provenance.device,
                    wasUserEntered: provenance.wasUserEntered
                ),
                envelope: envelope
            )
        case 3:
            let provenance = Self.provenance(
                sourceIndex: (index / 100) % sources.count
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
            let parentIndex = (index / 200) * 200 + 4
            let parentUUID = fixtureUUID(family: 7, index: parentIndex)
            if index % 200 == 4 {
                let provenance = Self.provenance(
                    sourceIndex: (index / 100) % sources.count
                )
                return try NativeWire.encode(
                    ECGRecord(
                        key: RecordKey(uuid: parentUUID),
                        start: sample.start,
                        end: sample.end,
                        timeZoneOffsetMinutes: sample.timeZoneOffsetMinutes,
                        timeZoneSource: sample.timeZoneSource,
                        classification: "sinusRhythm",
                        averageHeartRate: 60 + Double(index % 40),
                        samplingHz: 512,
                        voltageCount: 2,
                        symptomsStatus: "notSet",
                        observedAt: sample.observedAt,
                        source: provenance.source,
                        device: provenance.device,
                        wasUserEntered: provenance.wasUserEntered
                    ),
                    envelope: envelope
                )
            }
            let parent = Self.sample(
                at: parentIndex,
                seed: seed,
                declaration: declaration(at: parentIndex, tier: tier),
                tier: tier
            )
            return try NativeWire.encode(
                SeriesRecord(
                    parentUUID: parentUUID,
                    parentStart: parent.start,
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
                sourceIndex: (index / 100) % sources.count
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
                sourceIndex: (index / 100) % sources.count
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
        case 7:
            let parentIndex = (index / 100) * 100 + 2
            let parent = Self.sample(
                at: parentIndex,
                seed: seed,
                declaration: declaration(at: parentIndex, tier: tier),
                tier: tier
            )
            return try NativeWire.encode(
                SeriesRecord(
                    parentUUID: fixtureUUID(family: 5, index: parentIndex),
                    parentStart: parent.start,
                    chunkIndex: 0,
                    chunkCount: 1,
                    startIndex: 0,
                    payload: .workoutRoute(
                        points: [
                            WorkoutRoutePoint(
                                timestamp: parent.start,
                                latitude: 51.5073512,
                                longitude: -0.1277585
                            ),
                        ]
                    )
                ),
                envelope: envelope
            )
        case 8:
            let parentIndex = (index / 200) * 200 + 4
            let parent = Self.sample(
                at: parentIndex,
                seed: seed,
                declaration: declaration(at: parentIndex, tier: tier),
                tier: tier
            )
            return try NativeWire.encode(
                SeriesRecord(
                    parentUUID: fixtureUUID(family: 7, index: parentIndex),
                    parentStart: parent.start,
                    chunkIndex: 0,
                    chunkCount: 1,
                    startIndex: 0,
                    payload: .heartbeat(
                        intervalsMs: [800, 790, 810],
                        precededByGap: [false, false, true]
                    )
                ),
                envelope: envelope
            )
        case 9:
            let parentIndex = (index / 100) * 100 + 2
            let parent = Self.sample(
                at: parentIndex,
                seed: seed,
                declaration: declaration(at: parentIndex, tier: tier),
                tier: tier
            )
            return try NativeWire.encode(
                SeriesRecord(
                    parentUUID: fixtureUUID(family: 5, index: parentIndex),
                    parentStart: parent.start,
                    chunkIndex: 0,
                    chunkCount: 1,
                    startIndex: 0,
                    payload: .workoutMetric(
                        metricId: "heart_rate",
                        unit: "count/min",
                        points: [
                            SeriesMetricPoint(timestamp: parent.start, value: 128)
                        ]
                    )
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
                quantity.key = Self.sample(
                    at: priorIndex,
                    seed: seed,
                    declaration: declaration,
                    tier: tier
                ).key
            }
            return try NativeWire.encode(quantity, envelope: envelope)
        }
    }

    static func shifted(_ timestamp: String, seconds: TimeInterval) throws -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: timestamp) else {
            throw DemoCorpusError.invalidTimestamp
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
        let source = sources[sourceIndex]
        return (
            source,
            SampleDevice(
                name: source.name,
                manufacturer: "Synthetic",
                model: "fixture-\(sourceIndex + 1)",
                softwareVersion: "1.0"
            ),
            sourceIndex == sources.count - 1
        )
    }
}

enum DemoCorpusError: Error {
    case invalidTimestamp
}
