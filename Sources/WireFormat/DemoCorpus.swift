// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

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
        .init(metricID: "bloating", healthKitIdentifier: "HKCategoryTypeIdentifierBloating"),
        .init(metricID: "chills", healthKitIdentifier: "HKCategoryTypeIdentifierChills"),
        .init(metricID: "constipation", healthKitIdentifier: "HKCategoryTypeIdentifierConstipation"),
        .init(metricID: "coughing", healthKitIdentifier: "HKCategoryTypeIdentifierCoughing"),
        .init(metricID: "diarrhea", healthKitIdentifier: "HKCategoryTypeIdentifierDiarrhea"),
        .init(metricID: "dizziness", healthKitIdentifier: "HKCategoryTypeIdentifierDizziness"),
        .init(metricID: "dry_skin", healthKitIdentifier: "HKCategoryTypeIdentifierDrySkin"),
        .init(metricID: "fatigue", healthKitIdentifier: "HKCategoryTypeIdentifierFatigue"),
        .init(metricID: "fever", healthKitIdentifier: "HKCategoryTypeIdentifierFever"),
        .init(metricID: "abdominal_cramps", healthKitIdentifier: "HKCategoryTypeIdentifierAbdominalCramps"),
        .init(metricID: "acne", healthKitIdentifier: "HKCategoryTypeIdentifierAcne"),
        .init(metricID: "apple_stand_hour", healthKitIdentifier: "HKCategoryTypeIdentifierAppleStandHour"),
        .init(metricID: "apple_walking_steadiness_event", healthKitIdentifier: "HKCategoryTypeIdentifierAppleWalkingSteadinessEvent"),
        .init(metricID: "bleeding_after_pregnancy", healthKitIdentifier: "HKCategoryTypeIdentifierBleedingAfterPregnancy"),
        .init(metricID: "bleeding_during_pregnancy", healthKitIdentifier: "HKCategoryTypeIdentifierBleedingDuringPregnancy"),
        .init(metricID: "breast_pain", healthKitIdentifier: "HKCategoryTypeIdentifierBreastPain"),
        .init(metricID: "chest_tightness_or_pain", healthKitIdentifier: "HKCategoryTypeIdentifierChestTightnessOrPain"),
        .init(metricID: "fainting", healthKitIdentifier: "HKCategoryTypeIdentifierFainting"),
        .init(metricID: "generalized_body_ache", healthKitIdentifier: "HKCategoryTypeIdentifierGeneralizedBodyAche"),
        .init(metricID: "hair_loss", healthKitIdentifier: "HKCategoryTypeIdentifierHairLoss"),
        .init(metricID: "headache", healthKitIdentifier: "HKCategoryTypeIdentifierHeadache"),
        .init(metricID: "heartburn", healthKitIdentifier: "HKCategoryTypeIdentifierHeartburn"),
        .init(metricID: "hot_flashes", healthKitIdentifier: "HKCategoryTypeIdentifierHotFlashes"),
        .init(metricID: "hypertension_event", healthKitIdentifier: "HKCategoryTypeIdentifierHypertensionEvent"),
        .init(metricID: "loss_of_smell", healthKitIdentifier: "HKCategoryTypeIdentifierLossOfSmell"),
        .init(metricID: "loss_of_taste", healthKitIdentifier: "HKCategoryTypeIdentifierLossOfTaste"),
        .init(metricID: "low_cardio_fitness_event", healthKitIdentifier: "HKCategoryTypeIdentifierLowCardioFitnessEvent"),
        .init(metricID: "lower_back_pain", healthKitIdentifier: "HKCategoryTypeIdentifierLowerBackPain"),
        .init(metricID: "memory_lapse", healthKitIdentifier: "HKCategoryTypeIdentifierMemoryLapse"),
        .init(metricID: "mood_changes", healthKitIdentifier: "HKCategoryTypeIdentifierMoodChanges"),
        .init(metricID: "nausea", healthKitIdentifier: "HKCategoryTypeIdentifierNausea"),
        .init(metricID: "night_sweats", healthKitIdentifier: "HKCategoryTypeIdentifierNightSweats"),
        .init(metricID: "pelvic_pain", healthKitIdentifier: "HKCategoryTypeIdentifierPelvicPain"),
        .init(metricID: "rapid_pounding_or_fluttering_heartbeat", healthKitIdentifier: "HKCategoryTypeIdentifierRapidPoundingOrFlutteringHeartbeat"),
        .init(metricID: "runny_nose", healthKitIdentifier: "HKCategoryTypeIdentifierRunnyNose"),
        .init(metricID: "shortness_of_breath", healthKitIdentifier: "HKCategoryTypeIdentifierShortnessOfBreath"),
        .init(metricID: "sinus_congestion", healthKitIdentifier: "HKCategoryTypeIdentifierSinusCongestion"),
        .init(metricID: "skipped_heartbeat", healthKitIdentifier: "HKCategoryTypeIdentifierSkippedHeartbeat"),
        .init(metricID: "sleep_apnea_event", healthKitIdentifier: "HKCategoryTypeIdentifierSleepApneaEvent"),
        .init(metricID: "sleep_changes", healthKitIdentifier: "HKCategoryTypeIdentifierSleepChanges"),
        .init(metricID: "sore_throat", healthKitIdentifier: "HKCategoryTypeIdentifierSoreThroat"),
        .init(metricID: "vaginal_dryness", healthKitIdentifier: "HKCategoryTypeIdentifierVaginalDryness"),
        .init(metricID: "vomiting", healthKitIdentifier: "HKCategoryTypeIdentifierVomiting"),
        .init(metricID: "wheezing", healthKitIdentifier: "HKCategoryTypeIdentifierWheezing"),
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
        // Rotating per record rather than per catalogue pass keeps all six synthetic
        // identities present in a 200-record T0 corpus however large the catalogue grows.
        let sourceIndex = index % sources.count
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

    /// Plausible adult values per quantity metric (wire id), in the metric's canonical
    /// unit. The T0 to T2 corpus keeps its uniform values for byte-stable fixtures;
    /// the in-app sample dataset (#58) uses these so nothing reads as nonsense.
    public static let plausibleRanges: [String: ClosedRange<Double>] = [
        "step_count": 800...14_000,
        "heart_rate": 55...130,
        "active_energy": 20...900,
        "walking_running_distance": 0.5...12,
        "body_mass": 55...95,
        "oxygen_saturation": 95...100,
        "respiratory_rate": 12...20,
        "resting_heart_rate": 50...70,
        "vo2_max": 30...50,
        "blood_glucose": 70...140,
        "cycling_distance": 1...40,
        "flights_climbed": 1...30,
        "basal_energy": 1_300...1_900,
        "exercise_time": 5...90,
        "stand_time": 1...60,
        "walking_heart_rate_average": 85...115,
        "heart_rate_variability_sdnn": 25...80,
        "body_temperature": 36.1...37.2,
        "basal_body_temperature": 35.8...36.8,
        "height": 1.55...1.95,
        "body_fat_percentage": 12...32,
        "body_mass_index": 18.5...29,
        "lean_body_mass": 40...70,
        "dietary_water": 150...600,
        "blood_pressure_systolic": 105...135,
        "blood_pressure_diastolic": 65...85,
        "swimming_distance": 0.2...2,
        "wheelchair_distance": 0.5...6,
        "push_count": 200...3_000,
        "swimming_stroke_count": 100...1_500,
        "walking_speed": 1.0...1.6,
        "running_speed": 2.5...4.5,
        "cycling_speed": 4...9,
        "stair_ascent_speed": 0.3...0.8,
        "time_in_daylight": 5...120,
        "environmental_audio_exposure": 45...80,
        "apple_move_time": 5...60,
        "physical_effort": 2...8,
        "apple_sleeping_breathing_disturbances": 1...25,
        "apple_sleeping_wrist_temperature": 34.5...36.5,
        "apple_walking_steadiness": 70...100,
        "atrial_fibrillation_burden": 0.1...3,
        "blood_alcohol_content": 0.01...0.06,
        "cross_country_skiing_speed": 2...5,
        "cycling_cadence": 60...100,
        "cycling_functional_threshold_power": 150...300,
        "cycling_power": 100...300,
        "dietary_biotin": 0.00002...0.00004,
        "dietary_caffeine": 0.05...0.3,
        "dietary_calcium": 0.8...1.2,
        "dietary_carbohydrates": 150...300,
        "dietary_chloride": 1.5...3,
        "dietary_cholesterol": 0.15...0.35,
        "dietary_chromium": 0.00003...0.00012,
        "dietary_copper": 0.0008...0.0018,
        "dietary_energy_consumed": 1_600...2_600,
        "dietary_fat_monounsaturated": 15...35,
        "dietary_fat_polyunsaturated": 8...25,
        "dietary_fat_saturated": 10...30,
        "dietary_fat_total": 50...90,
        "dietary_fiber": 18...35,
        "dietary_folate": 0.0003...0.0006,
        "dietary_iodine": 0.0001...0.0002,
        "dietary_iron": 0.008...0.018,
        "dietary_magnesium": 0.25...0.45,
        "dietary_manganese": 0.0015...0.003,
        "dietary_molybdenum": 0.00004...0.0001,
        "dietary_niacin": 0.012...0.025,
        "dietary_pantothenic_acid": 0.004...0.007,
        "dietary_phosphorus": 0.7...1.4,
        "dietary_potassium": 2.5...4,
        "dietary_protein": 50...120,
        "dietary_riboflavin": 0.0012...0.002,
        "dietary_selenium": 0.00004...0.0001,
        "dietary_sodium": 1.5...3.2,
        "dietary_sugar": 30...90,
        "dietary_thiamin": 0.0011...0.002,
        "dietary_vitamin_a": 0.0007...0.0012,
        "dietary_vitamin_b12": 0.0000024...0.000006,
        "dietary_vitamin_b6": 0.0013...0.0025,
        "dietary_vitamin_c": 0.07...0.15,
        "dietary_vitamin_d": 0.00001...0.00002,
        "dietary_vitamin_e": 0.012...0.02,
        "dietary_vitamin_k": 0.00008...0.00015,
        "dietary_zinc": 0.008...0.014,
        "distance_cross_country_skiing": 2...15,
        "distance_downhill_snow_sports": 5...25,
        "distance_paddle_sports": 1...12,
        "distance_rowing": 2...10,
        "distance_skating_sports": 2...15,
        "electrodermal_activity": 0.5...5,
        "environmental_sound_reduction": 5...25,
        "estimated_workout_effort_score": 1...10,
        "forced_expiratory_volume_1": 2.5...4.5,
        "forced_vital_capacity": 3.2...5.5,
        "headphone_audio_exposure": 55...85,
        "heart_rate_recovery_one_minute": 15...50,
        "inhaler_usage": 1...4,
        "insulin_delivery": 2...12,
        "nike_fuel": 500...4_000,
        "number_of_alcoholic_beverages": 1...3,
        "number_of_times_fallen": 1...2,
        "paddle_sports_speed": 1...3,
        "peak_expiratory_flow_rate": 350...600,
        "peripheral_perfusion_index": 0.5...10,
        "rowing_speed": 2...5,
        "running_ground_contact_time": 220...320,
        "running_power": 180...320,
        "running_stride_length": 0.9...1.4,
        "running_vertical_oscillation": 0.07...0.11,
        "six_minute_walk_test_distance": 400...650,
        "stair_descent_speed": 0.4...0.9,
        "uv_exposure": 1...8,
        "underwater_depth": 1...10,
        "waist_circumference": 0.7...1.0,
        "walking_asymmetry_percentage": 1...10,
        "walking_double_support_percentage": 20...40,
        "walking_step_length": 0.6...0.8,
        "water_temperature": 15...28,
        "workout_effort_score": 1...10,
    ]

    /// How far back sample timestamps reach. Always inside the last 30 days.
    public static let sampleWindowDays = 29

    /// A sample with a plausible value for its metric and a timestamp within the last
    /// `sampleWindowDays` of `now`, never in the future.
    public static func recentSample(
        at index: Int,
        seed: UInt64,
        declaration: MetricDeclaration,
        now: Date
    ) -> SampleRecord {
        var record = sample(at: index, seed: seed, declaration: declaration)
        let random = splitMix64(UInt64(index) &+ seed &+ 0xD3_0001)
        let window = UInt64(sampleWindowDays * 24 * 60 * 60)
        let moment = now.addingTimeInterval(-TimeInterval(60 + random % window))
        let timestamp = moment.ISO8601Format()
        record.start = timestamp
        record.end = timestamp
        record.observedAt = timestamp
        if let range = plausibleRanges[declaration.wireId] {
            let fraction = Double((random >> 20) % 10_000) / 9_999
            let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
            let whole = range.lowerBound >= 20
                || (declaration.canonicalUnit.symbol == "count" && declaration.wireId != "body_mass_index")
            let rounded = whole ? raw.rounded() : Double(String(format: "%.3g", raw)) ?? raw
            record.value = min(max(rounded, range.lowerBound), range.upperBound)
        }
        return record
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
