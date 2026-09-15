// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import EnginePorts
import Foundation
import MetricCatalog
import WireFormat

/// Release-shipped synthetic source. No HealthKit, no fault seams (QA-38).
public struct DemoSampleSource: SampleSource, Sendable {
    public var seed: UInt64
    public var samplesPerMetric: Int

    public init(seed: UInt64 = 1, samplesPerMetric: Int = 4) {
        self.seed = seed
        self.samplesPerMetric = samplesPerMetric
    }

    public func page(metric: MetricID, afterAnchor: Data?) async throws -> SamplePage {
        if afterAnchor != nil {
            return emptyPage(metric: metric, anchor: afterAnchor ?? Data())
        }
        guard let declaration = MetricCatalog.declaration(for: metric) else {
            return emptyPage(metric: metric, anchor: Data("demo-unknown".utf8))
        }
        let metricIndex = MetricCatalog.selectable.firstIndex { $0.id == metric } ?? 0
        let baseIndex = metricIndex * 1_000
        let base: (Int) -> SampleRecord = { offset in
            DemoCorpus.sample(
                at: baseIndex + offset,
                seed: seed,
                declaration: declaration
            )
        }

        let samples = declaration.kind == "sample.quantity"
            ? (0..<samplesPerMetric).map(base)
            : []
        let categories = declaration.kind == "sample.category"
            ? (0..<samplesPerMetric).map { categoryRecord(declaration, sample: base($0)) }
            : []
        let workouts = declaration.kind == "workout"
            ? [workoutRecord(sample: base(0))]
            : []
        let minds = declaration.kind == "sample.stateOfMind"
            ? [stateOfMindRecord(sample: base(0))]
            : []
        let correlations = metric == MetricCatalog.bloodPressureSystolic.id
            ? [bloodPressureRecord(sample: base(100), baseIndex: baseIndex)]
            : []
        let electrocardiograms = metric == MetricCatalog.heartRate.id
            ? [ecgRecord(sample: base(101))]
            : []
        let audiograms = metric == MetricCatalog.heartRate.id
            ? [audiogramRecord(sample: base(102))]
            : []
        let medicationDoses = metric == MetricCatalog.heartRate.id
            ? [medicationDoseRecord(sample: base(103))]
            : []
        var series: [SeriesRecord] = []
        if let workout = workouts.first {
            series.append(contentsOf: workoutSeries(for: workout))
        }
        if let ecg = electrocardiograms.first {
            series.append(contentsOf: ecgSeries(for: ecg))
        }
        let tombstones = metric == MetricCatalog.heartRate.id
            ? [TombstoneRecord(key: base(104).key, metric: metric)]
            : []

        return SamplePage(
            samples: samples,
            categories: categories,
            correlations: correlations,
            workouts: workouts,
            minds: minds,
            electrocardiograms: electrocardiograms,
            audiograms: audiograms,
            medicationDoses: medicationDoses,
            series: series,
            tombstones: tombstones,
            metric: metric,
            anchorBlob: Data("demo-eof:\(metric.rawValue)".utf8),
            observedThrough: Self.observedThrough
        )
    }

    private static let observedThrough = Date(timeIntervalSince1970: 1_767_225_600)

    private func emptyPage(metric: MetricID, anchor: Data) -> SamplePage {
        SamplePage(
            samples: [],
            tombstones: [],
            metric: metric,
            anchorBlob: anchor,
            observedThrough: Self.observedThrough
        )
    }

    private func categoryRecord(
        _ declaration: MetricDeclaration,
        sample: SampleRecord
    ) -> CategoryRecord {
        let category = DemoCorpus.categoryTypes.first { $0.metricID == declaration.id.rawValue }
        let duration: TimeInterval = declaration.id == MetricCatalog.sleepAnalysis.id
            ? 8 * 60 * 60
            : 0
        let end = shifted(sample.start, seconds: duration)
        return CategoryRecord(
            key: sample.key,
            metric: declaration.id,
            healthKitIdentifier: category?.healthKitIdentifier ?? declaration.hkIdentifier,
            start: sample.start,
            end: end,
            timeZoneOffsetMinutes: sample.timeZoneOffsetMinutes,
            timeZoneSource: sample.timeZoneSource,
            categoryValue: category?.value ?? 0,
            categoryName: category?.valueName ?? "present",
            durationSeconds: duration > 0 ? duration : nil,
            observedAt: end,
            source: sample.source,
            device: sample.device,
            wasUserEntered: sample.wasUserEntered
        )
    }

    private func bloodPressureRecord(
        sample: SampleRecord,
        baseIndex: Int
    ) -> CorrelationRecord {
        CorrelationRecord(
            key: sample.key,
            metric: MetricID(rawValue: "blood_pressure"),
            healthKitIdentifier: "HKCorrelationTypeIdentifierBloodPressure",
            correlationType: "bloodPressure",
            start: sample.start,
            end: sample.end,
            timeZoneOffsetMinutes: sample.timeZoneOffsetMinutes,
            timeZoneSource: sample.timeZoneSource,
            components: [
                CorrelationComponent(
                    key: DemoCorpus.sample(
                        at: baseIndex + 105,
                        seed: seed,
                        declaration: MetricCatalog.bloodPressureSystolic
                    ).key,
                    metric: MetricCatalog.bloodPressureSystolic.id,
                    healthKitIdentifier: MetricCatalog.bloodPressureSystolic.hkIdentifier,
                    value: 120,
                    unit: MetricCatalog.bloodPressureSystolic.canonicalUnit
                ),
                CorrelationComponent(
                    key: DemoCorpus.sample(
                        at: baseIndex + 106,
                        seed: seed,
                        declaration: MetricCatalog.bloodPressureDiastolic
                    ).key,
                    metric: MetricCatalog.bloodPressureDiastolic.id,
                    healthKitIdentifier: MetricCatalog.bloodPressureDiastolic.hkIdentifier,
                    value: 80,
                    unit: MetricCatalog.bloodPressureDiastolic.canonicalUnit
                ),
            ],
            observedAt: sample.observedAt,
            source: sample.source,
            device: sample.device,
            wasUserEntered: sample.wasUserEntered
        )
    }

    private func workoutRecord(sample: SampleRecord) -> WorkoutRecord {
        WorkoutRecord(
            key: sample.key,
            activityType: "running",
            activityTypeRaw: 37,
            start: sample.start,
            end: shifted(sample.start, seconds: 3_600),
            timeZoneOffsetMinutes: sample.timeZoneOffsetMinutes,
            timeZoneSource: sample.timeZoneSource,
            durationSeconds: 3_300,
            isIndoor: false,
            totals: [
                "active_energy": WorkoutTotal(
                    value: 420,
                    unit: CanonicalUnit(symbol: "kcal"),
                    statistic: .sum
                ),
            ],
            hasRoute: true,
            seriesIncluded: ["workoutRoute", "workoutMetric"],
            observedAt: shifted(sample.start, seconds: 3_600),
            source: sample.source,
            device: sample.device,
            wasUserEntered: sample.wasUserEntered
        )
    }

    private func workoutSeries(for workout: WorkoutRecord) -> [SeriesRecord] {
        [
            SeriesRecord(
                parentUUID: workout.key.uuid,
                parentStart: workout.start,
                chunkIndex: 0,
                chunkCount: 1,
                startIndex: 0,
                payload: .workoutRoute(points: [
                    WorkoutRoutePoint(
                        timestamp: workout.start,
                        latitude: 51.5073512,
                        longitude: -0.1277585
                    ),
                ])
            ),
            SeriesRecord(
                parentUUID: workout.key.uuid,
                parentStart: workout.start,
                chunkIndex: 0,
                chunkCount: 1,
                startIndex: 0,
                payload: .workoutMetric(
                    metricId: MetricCatalog.heartRate.wireId,
                    unit: MetricCatalog.heartRate.wireUnit,
                    points: [SeriesMetricPoint(timestamp: workout.start, value: 128)]
                )
            ),
        ]
    }

    private func stateOfMindRecord(sample: SampleRecord) -> StateOfMindRecord {
        StateOfMindRecord(
            key: sample.key,
            start: sample.start,
            end: sample.end,
            timeZoneOffsetMinutes: sample.timeZoneOffsetMinutes,
            timeZoneSource: sample.timeZoneSource,
            kindOfEntry: "dailyMood",
            valence: 0.7,
            valenceClassification: "pleasant",
            labels: ["content", "happy"],
            associations: ["community"],
            observedAt: sample.observedAt,
            source: sample.source,
            device: sample.device,
            wasUserEntered: sample.wasUserEntered
        )
    }

    private func ecgRecord(sample: SampleRecord) -> ECGRecord {
        ECGRecord(
            key: sample.key,
            start: sample.start,
            end: sample.end,
            timeZoneOffsetMinutes: sample.timeZoneOffsetMinutes,
            timeZoneSource: sample.timeZoneSource,
            classification: "sinusRhythm",
            averageHeartRate: 64,
            samplingHz: 512,
            voltageCount: 2,
            symptomsStatus: "notSet",
            observedAt: sample.observedAt,
            source: sample.source,
            device: sample.device,
            wasUserEntered: sample.wasUserEntered
        )
    }

    private func ecgSeries(for ecg: ECGRecord) -> [SeriesRecord] {
        [
            SeriesRecord(
                parentUUID: ecg.key.uuid,
                parentStart: ecg.start,
                chunkIndex: 0,
                chunkCount: 1,
                startIndex: 0,
                payload: .ecgVoltage(voltages: [0.12, -0.04], samplingHz: 512)
            ),
            SeriesRecord(
                parentUUID: ecg.key.uuid,
                parentStart: ecg.start,
                chunkIndex: 0,
                chunkCount: 1,
                startIndex: 0,
                payload: .heartbeat(
                    intervalsMs: [800, 790, 810],
                    precededByGap: [false, false, true]
                )
            ),
        ]
    }

    private func audiogramRecord(sample: SampleRecord) -> AudiogramRecord {
        AudiogramRecord(
            key: sample.key,
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
                AudiogramSensitivityPoint(frequencyHz: 2_000, leftEarDbHL: 15),
            ],
            observedAt: sample.observedAt,
            source: sample.source,
            device: sample.device,
            wasUserEntered: sample.wasUserEntered
        )
    }

    private func medicationDoseRecord(sample: SampleRecord) -> MedicationDoseRecord {
        MedicationDoseRecord(
            key: sample.key,
            start: sample.start,
            end: sample.end,
            timeZoneOffsetMinutes: sample.timeZoneOffsetMinutes,
            timeZoneSource: sample.timeZoneSource,
            medicationName: "Synthetic lisinopril",
            doseQuantity: 10,
            doseUnit: "mg",
            status: "taken",
            observedAt: sample.observedAt,
            source: sample.source,
            device: sample.device,
            wasUserEntered: sample.wasUserEntered
        )
    }

    private func shifted(_ timestamp: String, seconds: TimeInterval) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: timestamp) else { return timestamp }
        return formatter.string(from: date.addingTimeInterval(seconds))
    }
}

/// Release-shipped characteristic snapshots for demo mode. Values use the same
/// closed tokens as `HealthKitCharacteristicSource`, without reading HealthKit.
public struct DemoCharacteristicSource: CharacteristicSource, Sendable {
    public init() {}

    public func read(metric: MetricID, observedAt: String) async throws -> CharacteristicRecord? {
        guard let declaration = MetricCatalog.declaration(for: metric),
              let characteristicID = declaration.characteristicId,
              let value = Self.values[metric]
        else {
            return nil
        }
        return CharacteristicRecord(
            characteristicId: characteristicID,
            value: value,
            observedAt: observedAt
        )
    }

    private static let values: [MetricID: String] = [
        MetricCatalog.biologicalSex.id: "female",
        MetricCatalog.bloodType.id: "oPositive",
        MetricCatalog.dateOfBirth.id: "1990-01-01",
        MetricCatalog.fitzpatrickSkinType.id: "III",
        MetricCatalog.wheelchairUse.id: "no",
        MetricCatalog.activityMoveMode.id: "activeEnergy",
    ]
}

public enum DemoExportError: Error, Equatable, LocalizedError {
    case confirmationRequired
    case confirmationMismatch

    public var errorDescription: String? {
        switch self {
        case .confirmationRequired:
            "Type the destination name to send demo data."
        case .confirmationMismatch:
            "The typed destination name did not match."
        }
    }
}

public enum DemoExportGate {
    public static func confirmSending(to destinationName: String, typed: String) throws {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DemoExportError.confirmationRequired }
        guard trimmed == destinationName else { throw DemoExportError.confirmationMismatch }
    }
}
