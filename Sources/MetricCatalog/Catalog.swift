// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain

public struct MetricDeclaration: Sendable {
    public var id: MetricID
    public var wireId: String
    public var hkIdentifier: String
    public var canonicalUnit: CanonicalUnit
    public var wireUnit: String
    public var cumulative: Bool
    public var usesHealthKitStatistics: Bool
    public var sensitivity: SensitivityClass
    /// Home Assistant `unit_of_measurement`. Omitted on the wire when nil (BMI).
    public var haUnit: String?
    /// Omitted when nil — never guessed (heart rate has no device class).
    public var haDeviceClass: String?
    /// Omitted when nil (enum / timestamp / unmapped). Never `measurement` with energy/volume.
    public var haStateClass: String?
    public var haRequiresAggregate: Bool
    /// Wire family: `sample.quantity`, `sample.category`, `sample.stateOfMind`,
    /// `workout`, or `characteristic`.
    public var kind: String
    /// HK-30: static identity-adjacent types. Always confirmed individually.
    public var reidentifying: Bool
    /// Closed wire `characteristicId` when `kind` is `characteristic`.
    public var characteristicId: String?

    public init(
        id: MetricID,
        wireId: String,
        hkIdentifier: String,
        canonicalUnit: CanonicalUnit,
        wireUnit: String,
        cumulative: Bool,
        usesHealthKitStatistics: Bool,
        sensitivity: SensitivityClass,
        haUnit: String?,
        haDeviceClass: String?,
        haStateClass: String?,
        haRequiresAggregate: Bool,
        kind: String = "sample.quantity",
        reidentifying: Bool = false,
        characteristicId: String? = nil
    ) {
        self.id = id
        self.wireId = wireId
        self.hkIdentifier = hkIdentifier
        self.canonicalUnit = canonicalUnit
        self.wireUnit = wireUnit
        self.cumulative = cumulative
        self.usesHealthKitStatistics = usesHealthKitStatistics
        self.sensitivity = sensitivity
        self.haUnit = haUnit
        self.haDeviceClass = haDeviceClass
        self.haStateClass = haStateClass
        self.haRequiresAggregate = haRequiresAggregate
        self.kind = kind
        self.reidentifying = reidentifying
        self.characteristicId = characteristicId
    }
}

public enum MetricCatalog {
    public static let stepCount = MetricDeclaration(
        id: MetricID(rawValue: "stepCount"),
        wireId: "step_count",
        hkIdentifier: "HKQuantityTypeIdentifierStepCount",
        canonicalUnit: CanonicalUnit(symbol: "count"),
        wireUnit: "count",
        cumulative: true,
        usesHealthKitStatistics: true,
        sensitivity: .routine,
        haUnit: "steps",
        haDeviceClass: nil,
        haStateClass: "total_increasing",
        haRequiresAggregate: true
    )

    public static let heartRate = MetricDeclaration(
        id: MetricID(rawValue: "heartRate"),
        wireId: "heart_rate",
        hkIdentifier: "HKQuantityTypeIdentifierHeartRate",
        canonicalUnit: CanonicalUnit(symbol: "count/min"),
        wireUnit: "bpm",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .routine,
        haUnit: "bpm",
        haDeviceClass: nil,
        haStateClass: "measurement",
        haRequiresAggregate: false
    )

    public static let activeEnergy = MetricDeclaration(
        id: MetricID(rawValue: "activeEnergy"),
        wireId: "active_energy",
        hkIdentifier: "HKQuantityTypeIdentifierActiveEnergyBurned",
        canonicalUnit: CanonicalUnit(symbol: "kcal"),
        wireUnit: "kcal",
        cumulative: true,
        usesHealthKitStatistics: true,
        sensitivity: .routine,
        haUnit: "kcal",
        haDeviceClass: nil,
        haStateClass: "total_increasing",
        haRequiresAggregate: true
    )

    public static let walkingRunningDistance = MetricDeclaration(
        id: MetricID(rawValue: "walkingRunningDistance"),
        wireId: "walking_running_distance",
        hkIdentifier: "HKQuantityTypeIdentifierDistanceWalkingRunning",
        canonicalUnit: CanonicalUnit(symbol: "km"),
        wireUnit: "km",
        cumulative: true,
        usesHealthKitStatistics: true,
        sensitivity: .routine,
        haUnit: "km",
        haDeviceClass: "distance",
        haStateClass: "total_increasing",
        haRequiresAggregate: true
    )

    public static let bodyMass = MetricDeclaration(
        id: MetricID(rawValue: "bodyMass"),
        wireId: "body_mass",
        hkIdentifier: "HKQuantityTypeIdentifierBodyMass",
        canonicalUnit: CanonicalUnit(symbol: "kg"),
        wireUnit: "kg",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .sensitive,
        haUnit: "kg",
        haDeviceClass: "weight",
        haStateClass: "measurement",
        haRequiresAggregate: false
    )

    public static let oxygenSaturation = MetricDeclaration(
        id: MetricID(rawValue: "oxygenSaturation"),
        wireId: "oxygen_saturation",
        hkIdentifier: "HKQuantityTypeIdentifierOxygenSaturation",
        canonicalUnit: CanonicalUnit(symbol: "%"),
        wireUnit: "%",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .sensitive,
        haUnit: "%",
        haDeviceClass: nil,
        haStateClass: "measurement",
        haRequiresAggregate: false
    )

    public static let respiratoryRate = MetricDeclaration(
        id: MetricID(rawValue: "respiratoryRate"),
        wireId: "respiratory_rate",
        hkIdentifier: "HKQuantityTypeIdentifierRespiratoryRate",
        canonicalUnit: CanonicalUnit(symbol: "count/min"),
        wireUnit: "count/min",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .sensitive,
        haUnit: "breaths/min",
        haDeviceClass: nil,
        haStateClass: "measurement",
        haRequiresAggregate: false
    )

    public static let restingHeartRate = MetricDeclaration(
        id: MetricID(rawValue: "restingHeartRate"),
        wireId: "resting_heart_rate",
        hkIdentifier: "HKQuantityTypeIdentifierRestingHeartRate",
        canonicalUnit: CanonicalUnit(symbol: "count/min"),
        wireUnit: "bpm",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .routine,
        haUnit: "bpm",
        haDeviceClass: nil,
        haStateClass: "measurement",
        haRequiresAggregate: false
    )

    public static let vo2Max = MetricDeclaration(
        id: MetricID(rawValue: "vo2Max"),
        wireId: "vo2_max",
        hkIdentifier: "HKQuantityTypeIdentifierVO2Max",
        canonicalUnit: CanonicalUnit(symbol: "mL/kg/min"),
        wireUnit: "mL/kg/min",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .sensitive,
        haUnit: "mL/kg/min",
        haDeviceClass: nil,
        haStateClass: "measurement",
        haRequiresAggregate: false
    )

    public static let bloodGlucose = MetricDeclaration(
        id: MetricID(rawValue: "bloodGlucose"),
        wireId: "blood_glucose",
        hkIdentifier: "HKQuantityTypeIdentifierBloodGlucose",
        canonicalUnit: CanonicalUnit(symbol: "mg/dL"),
        wireUnit: "mg/dL",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .sensitive,
        haUnit: "mg/dL",
        haDeviceClass: "blood_glucose_concentration",
        haStateClass: "measurement",
        haRequiresAggregate: false
    )

    public static let cyclingDistance = MetricDeclaration(
        id: MetricID(rawValue: "cyclingDistance"),
        wireId: "cycling_distance",
        hkIdentifier: "HKQuantityTypeIdentifierDistanceCycling",
        canonicalUnit: CanonicalUnit(symbol: "km"),
        wireUnit: "km",
        cumulative: true,
        usesHealthKitStatistics: true,
        sensitivity: .routine,
        haUnit: "km",
        haDeviceClass: "distance",
        haStateClass: "total_increasing",
        haRequiresAggregate: true
    )

    public static let flightsClimbed = MetricDeclaration(
        id: MetricID(rawValue: "flightsClimbed"),
        wireId: "flights_climbed",
        hkIdentifier: "HKQuantityTypeIdentifierFlightsClimbed",
        canonicalUnit: CanonicalUnit(symbol: "count"),
        wireUnit: "count",
        cumulative: true,
        usesHealthKitStatistics: true,
        sensitivity: .routine,
        haUnit: "flights",
        haDeviceClass: nil,
        haStateClass: "total_increasing",
        haRequiresAggregate: true
    )

    public static let basalEnergy = MetricDeclaration(
        id: MetricID(rawValue: "basalEnergy"),
        wireId: "basal_energy",
        hkIdentifier: "HKQuantityTypeIdentifierBasalEnergyBurned",
        canonicalUnit: CanonicalUnit(symbol: "kcal"),
        wireUnit: "kcal",
        cumulative: true,
        usesHealthKitStatistics: true,
        sensitivity: .routine,
        haUnit: "kcal",
        haDeviceClass: nil,
        haStateClass: "total_increasing",
        haRequiresAggregate: true
    )

    public static let exerciseTime = MetricDeclaration(
        id: MetricID(rawValue: "exerciseTime"),
        wireId: "exercise_time",
        hkIdentifier: "HKQuantityTypeIdentifierAppleExerciseTime",
        canonicalUnit: CanonicalUnit(symbol: "min"),
        wireUnit: "min",
        cumulative: true,
        usesHealthKitStatistics: true,
        sensitivity: .routine,
        haUnit: "min",
        haDeviceClass: "duration",
        haStateClass: "total_increasing",
        haRequiresAggregate: true
    )

    public static let standTime = MetricDeclaration(
        id: MetricID(rawValue: "standTime"),
        wireId: "stand_time",
        hkIdentifier: "HKQuantityTypeIdentifierAppleStandTime",
        canonicalUnit: CanonicalUnit(symbol: "min"),
        wireUnit: "min",
        cumulative: true,
        usesHealthKitStatistics: true,
        sensitivity: .routine,
        haUnit: "min",
        haDeviceClass: "duration",
        haStateClass: "total_increasing",
        haRequiresAggregate: true
    )

    public static let walkingHeartRateAverage = MetricDeclaration(
        id: MetricID(rawValue: "walkingHeartRateAverage"),
        wireId: "walking_heart_rate_average",
        hkIdentifier: "HKQuantityTypeIdentifierWalkingHeartRateAverage",
        canonicalUnit: CanonicalUnit(symbol: "count/min"),
        wireUnit: "bpm",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .routine,
        haUnit: "bpm",
        haDeviceClass: nil,
        haStateClass: "measurement",
        haRequiresAggregate: false
    )

    public static let heartRateVariabilitySDNN = MetricDeclaration(
        id: MetricID(rawValue: "heartRateVariabilitySDNN"),
        wireId: "heart_rate_variability_sdnn",
        hkIdentifier: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
        canonicalUnit: CanonicalUnit(symbol: "ms"),
        wireUnit: "ms",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .sensitive,
        haUnit: "ms",
        haDeviceClass: "duration",
        haStateClass: "measurement",
        haRequiresAggregate: false
    )

    public static let bodyTemperature = MetricDeclaration(
        id: MetricID(rawValue: "bodyTemperature"),
        wireId: "body_temperature",
        hkIdentifier: "HKQuantityTypeIdentifierBodyTemperature",
        canonicalUnit: CanonicalUnit(symbol: "degC"),
        wireUnit: "degC",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .sensitive,
        haUnit: "°C",
        haDeviceClass: "temperature",
        haStateClass: "measurement",
        haRequiresAggregate: false
    )

    public static let basalBodyTemperature = MetricDeclaration(
        id: MetricID(rawValue: "basalBodyTemperature"),
        wireId: "basal_body_temperature",
        hkIdentifier: "HKQuantityTypeIdentifierBasalBodyTemperature",
        canonicalUnit: CanonicalUnit(symbol: "degC"),
        wireUnit: "degC",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .sensitive,
        haUnit: "°C",
        haDeviceClass: "temperature",
        haStateClass: "measurement",
        haRequiresAggregate: false
    )

    public static let height = MetricDeclaration(
        id: MetricID(rawValue: "height"),
        wireId: "height",
        hkIdentifier: "HKQuantityTypeIdentifierHeight",
        canonicalUnit: CanonicalUnit(symbol: "m"),
        wireUnit: "m",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .sensitive,
        haUnit: "cm",
        haDeviceClass: "distance",
        haStateClass: "measurement",
        haRequiresAggregate: false
    )

    public static let bodyFatPercentage = MetricDeclaration(
        id: MetricID(rawValue: "bodyFatPercentage"),
        wireId: "body_fat_percentage",
        hkIdentifier: "HKQuantityTypeIdentifierBodyFatPercentage",
        canonicalUnit: CanonicalUnit(symbol: "%"),
        wireUnit: "%",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .sensitive,
        haUnit: "%",
        haDeviceClass: nil,
        haStateClass: "measurement",
        haRequiresAggregate: false
    )

    public static let bodyMassIndex = MetricDeclaration(
        id: MetricID(rawValue: "bodyMassIndex"),
        wireId: "body_mass_index",
        hkIdentifier: "HKQuantityTypeIdentifierBodyMassIndex",
        canonicalUnit: CanonicalUnit(symbol: "count"),
        wireUnit: "count",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .sensitive,
        haUnit: nil,
        haDeviceClass: nil,
        haStateClass: "measurement",
        haRequiresAggregate: false
    )

    public static let leanBodyMass = MetricDeclaration(
        id: MetricID(rawValue: "leanBodyMass"),
        wireId: "lean_body_mass",
        hkIdentifier: "HKQuantityTypeIdentifierLeanBodyMass",
        canonicalUnit: CanonicalUnit(symbol: "kg"),
        wireUnit: "kg",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .sensitive,
        haUnit: "kg",
        haDeviceClass: "weight",
        haStateClass: "measurement",
        haRequiresAggregate: false
    )

    public static let dietaryWater = MetricDeclaration(
        id: MetricID(rawValue: "dietaryWater"),
        wireId: "dietary_water",
        hkIdentifier: "HKQuantityTypeIdentifierDietaryWater",
        canonicalUnit: CanonicalUnit(symbol: "mL"),
        wireUnit: "mL",
        cumulative: true,
        usesHealthKitStatistics: true,
        sensitivity: .routine,
        haUnit: "mL",
        haDeviceClass: "volume",
        haStateClass: "total_increasing",
        haRequiresAggregate: true
    )

    public static let bloodPressureSystolic = MetricDeclaration(
        id: MetricID(rawValue: "bloodPressureSystolic"),
        wireId: "blood_pressure_systolic",
        hkIdentifier: "HKQuantityTypeIdentifierBloodPressureSystolic",
        canonicalUnit: CanonicalUnit(symbol: "mmHg"),
        wireUnit: "mmHg",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .sensitive,
        haUnit: "mmHg",
        haDeviceClass: nil,
        haStateClass: "measurement",
        haRequiresAggregate: false
    )

    public static let bloodPressureDiastolic = MetricDeclaration(
        id: MetricID(rawValue: "bloodPressureDiastolic"),
        wireId: "blood_pressure_diastolic",
        hkIdentifier: "HKQuantityTypeIdentifierBloodPressureDiastolic",
        canonicalUnit: CanonicalUnit(symbol: "mmHg"),
        wireUnit: "mmHg",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .sensitive,
        haUnit: "mmHg",
        haDeviceClass: nil,
        haStateClass: "measurement",
        haRequiresAggregate: false
    )

    public static let swimmingDistance = MetricDeclaration(
        id: MetricID(rawValue: "swimmingDistance"),
        wireId: "swimming_distance",
        hkIdentifier: "HKQuantityTypeIdentifierDistanceSwimming",
        canonicalUnit: CanonicalUnit(symbol: "km"),
        wireUnit: "km",
        cumulative: true,
        usesHealthKitStatistics: true,
        sensitivity: .routine,
        haUnit: "km",
        haDeviceClass: "distance",
        haStateClass: "total_increasing",
        haRequiresAggregate: true
    )

    public static let wheelchairDistance = MetricDeclaration(
        id: MetricID(rawValue: "wheelchairDistance"),
        wireId: "wheelchair_distance",
        hkIdentifier: "HKQuantityTypeIdentifierDistanceWheelchair",
        canonicalUnit: CanonicalUnit(symbol: "km"),
        wireUnit: "km",
        cumulative: true,
        usesHealthKitStatistics: true,
        sensitivity: .routine,
        haUnit: "km",
        haDeviceClass: "distance",
        haStateClass: "total_increasing",
        haRequiresAggregate: true
    )

    public static let pushCount = MetricDeclaration(
        id: MetricID(rawValue: "pushCount"),
        wireId: "push_count",
        hkIdentifier: "HKQuantityTypeIdentifierPushCount",
        canonicalUnit: CanonicalUnit(symbol: "count"),
        wireUnit: "count",
        cumulative: true,
        usesHealthKitStatistics: true,
        sensitivity: .routine,
        haUnit: "pushes",
        haDeviceClass: nil,
        haStateClass: "total_increasing",
        haRequiresAggregate: true
    )

    public static let swimmingStrokeCount = MetricDeclaration(
        id: MetricID(rawValue: "swimmingStrokeCount"),
        wireId: "swimming_stroke_count",
        hkIdentifier: "HKQuantityTypeIdentifierSwimmingStrokeCount",
        canonicalUnit: CanonicalUnit(symbol: "count"),
        wireUnit: "count",
        cumulative: true,
        usesHealthKitStatistics: true,
        sensitivity: .routine,
        haUnit: "strokes",
        haDeviceClass: nil,
        haStateClass: "total_increasing",
        haRequiresAggregate: true
    )

    public static let walkingSpeed = MetricDeclaration(
        id: MetricID(rawValue: "walkingSpeed"),
        wireId: "walking_speed",
        hkIdentifier: "HKQuantityTypeIdentifierWalkingSpeed",
        canonicalUnit: CanonicalUnit(symbol: "m/s"),
        wireUnit: "m/s",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .routine,
        haUnit: "m/s",
        haDeviceClass: "speed",
        haStateClass: "measurement",
        haRequiresAggregate: false
    )

    public static let runningSpeed = MetricDeclaration(
        id: MetricID(rawValue: "runningSpeed"),
        wireId: "running_speed",
        hkIdentifier: "HKQuantityTypeIdentifierRunningSpeed",
        canonicalUnit: CanonicalUnit(symbol: "m/s"),
        wireUnit: "m/s",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .routine,
        haUnit: "m/s",
        haDeviceClass: "speed",
        haStateClass: "measurement",
        haRequiresAggregate: false
    )

    public static let cyclingSpeed = MetricDeclaration(
        id: MetricID(rawValue: "cyclingSpeed"),
        wireId: "cycling_speed",
        hkIdentifier: "HKQuantityTypeIdentifierCyclingSpeed",
        canonicalUnit: CanonicalUnit(symbol: "m/s"),
        wireUnit: "m/s",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .routine,
        haUnit: "m/s",
        haDeviceClass: "speed",
        haStateClass: "measurement",
        haRequiresAggregate: false
    )

    public static let stairAscentSpeed = MetricDeclaration(
        id: MetricID(rawValue: "stairAscentSpeed"),
        wireId: "stair_ascent_speed",
        hkIdentifier: "HKQuantityTypeIdentifierStairAscentSpeed",
        canonicalUnit: CanonicalUnit(symbol: "m/s"),
        wireUnit: "m/s",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .routine,
        haUnit: "m/s",
        haDeviceClass: "speed",
        haStateClass: "measurement",
        haRequiresAggregate: false
    )

    public static let timeInDaylight = MetricDeclaration(
        id: MetricID(rawValue: "timeInDaylight"),
        wireId: "time_in_daylight",
        hkIdentifier: "HKQuantityTypeIdentifierTimeInDaylight",
        canonicalUnit: CanonicalUnit(symbol: "min"),
        wireUnit: "min",
        cumulative: true,
        usesHealthKitStatistics: true,
        sensitivity: .routine,
        haUnit: "min",
        haDeviceClass: "duration",
        haStateClass: "total_increasing",
        haRequiresAggregate: true
    )

    public static let environmentalAudioExposure = MetricDeclaration(
        id: MetricID(rawValue: "environmentalAudioExposure"),
        wireId: "environmental_audio_exposure",
        hkIdentifier: "HKQuantityTypeIdentifierEnvironmentalAudioExposure",
        canonicalUnit: CanonicalUnit(symbol: "dBASPL"),
        wireUnit: "dBASPL",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .routine,
        haUnit: "dBA",
        haDeviceClass: "sound_pressure",
        haStateClass: "measurement",
        haRequiresAggregate: false
    )

    public static let appleMoveTime = MetricDeclaration(
        id: MetricID(rawValue: "appleMoveTime"),
        wireId: "apple_move_time",
        hkIdentifier: "HKQuantityTypeIdentifierAppleMoveTime",
        canonicalUnit: CanonicalUnit(symbol: "min"),
        wireUnit: "min",
        cumulative: true,
        usesHealthKitStatistics: true,
        sensitivity: .routine,
        haUnit: "min",
        haDeviceClass: "duration",
        haStateClass: "total_increasing",
        haRequiresAggregate: true
    )

    public static let physicalEffort = MetricDeclaration(
        id: MetricID(rawValue: "physicalEffort"),
        wireId: "physical_effort",
        hkIdentifier: "HKQuantityTypeIdentifierPhysicalEffort",
        canonicalUnit: CanonicalUnit(symbol: "kcal/kg/h"),
        wireUnit: "kcal/kg/h",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .routine,
        haUnit: "kcal/kg/h",
        haDeviceClass: nil,
        haStateClass: "measurement",
        haRequiresAggregate: false
    )

    /// Converted HealthKit quantity families that already have generic sample.quantity conversion.
    /// Sensitive insulin, alcohol, and body-size types stay out of Core Daily.
    public static let convertedQuantities: [MetricDeclaration] = {
        func gram(_ id: String, _ hk: String) -> MetricDeclaration {
            convertedQuantity(
                id,
                hk,
                symbol: "g",
                cumulative: true,
                sensitivity: .routine,
                haUnit: "g",
                haDeviceClass: nil,
                haStateClass: "total_increasing"
            )
        }
        func km(_ id: String, _ hk: String) -> MetricDeclaration {
            convertedQuantity(
                id,
                hk,
                symbol: "km",
                cumulative: true,
                sensitivity: .routine,
                haUnit: "km",
                haDeviceClass: "distance",
                haStateClass: "total_increasing"
            )
        }
        func speed(_ id: String, _ hk: String) -> MetricDeclaration {
            convertedQuantity(
                id,
                hk,
                symbol: "m/s",
                cumulative: false,
                sensitivity: .routine,
                haUnit: "m/s",
                haDeviceClass: "speed",
                haStateClass: "measurement"
            )
        }
        func watts(_ id: String, _ hk: String) -> MetricDeclaration {
            convertedQuantity(
                id,
                hk,
                symbol: "W",
                cumulative: false,
                sensitivity: .routine,
                haUnit: "W",
                haDeviceClass: "power",
                haStateClass: "measurement"
            )
        }
        func percent(_ id: String, _ hk: String, _ sensitivity: SensitivityClass) -> MetricDeclaration {
            convertedQuantity(
                id,
                hk,
                symbol: "%",
                cumulative: false,
                sensitivity: sensitivity,
                haUnit: "%",
                haDeviceClass: nil,
                haStateClass: "measurement"
            )
        }
        func count(
            _ id: String,
            _ hk: String,
            cumulative: Bool,
            sensitivity: SensitivityClass
        ) -> MetricDeclaration {
            convertedQuantity(
                id,
                hk,
                symbol: "count",
                cumulative: cumulative,
                sensitivity: sensitivity,
                haUnit: "count",
                haDeviceClass: nil,
                haStateClass: cumulative ? "total_increasing" : "measurement"
            )
        }
        return [
            count(
                "apple_sleeping_breathing_disturbances",
                "HKQuantityTypeIdentifierAppleSleepingBreathingDisturbances",
                cumulative: false,
                sensitivity: .sensitive
            ),
            convertedQuantity(
                "apple_sleeping_wrist_temperature",
                "HKQuantityTypeIdentifierAppleSleepingWristTemperature",
                symbol: "degC",
                cumulative: false,
                sensitivity: .sensitive,
                haUnit: "°C",
                haDeviceClass: "temperature",
                haStateClass: "measurement"
            ),
            percent(
                "apple_walking_steadiness",
                "HKQuantityTypeIdentifierAppleWalkingSteadiness",
                .sensitive
            ),
            percent(
                "atrial_fibrillation_burden",
                "HKQuantityTypeIdentifierAtrialFibrillationBurden",
                .sensitive
            ),
            percent(
                "blood_alcohol_content",
                "HKQuantityTypeIdentifierBloodAlcoholContent",
                .sensitive
            ),
            speed("cross_country_skiing_speed", "HKQuantityTypeIdentifierCrossCountrySkiingSpeed"),
            convertedQuantity(
                "cycling_cadence",
                "HKQuantityTypeIdentifierCyclingCadence",
                symbol: "count/min",
                cumulative: false,
                sensitivity: .routine,
                haUnit: "rpm",
                haDeviceClass: nil,
                haStateClass: "measurement"
            ),
            watts(
                "cycling_functional_threshold_power",
                "HKQuantityTypeIdentifierCyclingFunctionalThresholdPower"
            ),
            watts("cycling_power", "HKQuantityTypeIdentifierCyclingPower"),
            gram("dietary_biotin", "HKQuantityTypeIdentifierDietaryBiotin"),
            gram("dietary_caffeine", "HKQuantityTypeIdentifierDietaryCaffeine"),
            gram("dietary_calcium", "HKQuantityTypeIdentifierDietaryCalcium"),
            gram("dietary_carbohydrates", "HKQuantityTypeIdentifierDietaryCarbohydrates"),
            gram("dietary_chloride", "HKQuantityTypeIdentifierDietaryChloride"),
            gram("dietary_cholesterol", "HKQuantityTypeIdentifierDietaryCholesterol"),
            gram("dietary_chromium", "HKQuantityTypeIdentifierDietaryChromium"),
            gram("dietary_copper", "HKQuantityTypeIdentifierDietaryCopper"),
            convertedQuantity(
                "dietary_energy_consumed",
                "HKQuantityTypeIdentifierDietaryEnergyConsumed",
                symbol: "kcal",
                cumulative: true,
                sensitivity: .routine,
                haUnit: "kcal",
                haDeviceClass: nil,
                haStateClass: "total_increasing"
            ),
            gram("dietary_fat_monounsaturated", "HKQuantityTypeIdentifierDietaryFatMonounsaturated"),
            gram("dietary_fat_polyunsaturated", "HKQuantityTypeIdentifierDietaryFatPolyunsaturated"),
            gram("dietary_fat_saturated", "HKQuantityTypeIdentifierDietaryFatSaturated"),
            gram("dietary_fat_total", "HKQuantityTypeIdentifierDietaryFatTotal"),
            gram("dietary_fiber", "HKQuantityTypeIdentifierDietaryFiber"),
            gram("dietary_folate", "HKQuantityTypeIdentifierDietaryFolate"),
            gram("dietary_iodine", "HKQuantityTypeIdentifierDietaryIodine"),
            gram("dietary_iron", "HKQuantityTypeIdentifierDietaryIron"),
            gram("dietary_magnesium", "HKQuantityTypeIdentifierDietaryMagnesium"),
            gram("dietary_manganese", "HKQuantityTypeIdentifierDietaryManganese"),
            gram("dietary_molybdenum", "HKQuantityTypeIdentifierDietaryMolybdenum"),
            gram("dietary_niacin", "HKQuantityTypeIdentifierDietaryNiacin"),
            gram("dietary_pantothenic_acid", "HKQuantityTypeIdentifierDietaryPantothenicAcid"),
            gram("dietary_phosphorus", "HKQuantityTypeIdentifierDietaryPhosphorus"),
            gram("dietary_potassium", "HKQuantityTypeIdentifierDietaryPotassium"),
            gram("dietary_protein", "HKQuantityTypeIdentifierDietaryProtein"),
            gram("dietary_riboflavin", "HKQuantityTypeIdentifierDietaryRiboflavin"),
            gram("dietary_selenium", "HKQuantityTypeIdentifierDietarySelenium"),
            gram("dietary_sodium", "HKQuantityTypeIdentifierDietarySodium"),
            gram("dietary_sugar", "HKQuantityTypeIdentifierDietarySugar"),
            gram("dietary_thiamin", "HKQuantityTypeIdentifierDietaryThiamin"),
            gram("dietary_vitamin_a", "HKQuantityTypeIdentifierDietaryVitaminA"),
            gram("dietary_vitamin_b12", "HKQuantityTypeIdentifierDietaryVitaminB12"),
            gram("dietary_vitamin_b6", "HKQuantityTypeIdentifierDietaryVitaminB6"),
            gram("dietary_vitamin_c", "HKQuantityTypeIdentifierDietaryVitaminC"),
            gram("dietary_vitamin_d", "HKQuantityTypeIdentifierDietaryVitaminD"),
            gram("dietary_vitamin_e", "HKQuantityTypeIdentifierDietaryVitaminE"),
            gram("dietary_vitamin_k", "HKQuantityTypeIdentifierDietaryVitaminK"),
            gram("dietary_zinc", "HKQuantityTypeIdentifierDietaryZinc"),
            km("distance_cross_country_skiing", "HKQuantityTypeIdentifierDistanceCrossCountrySkiing"),
            km("distance_downhill_snow_sports", "HKQuantityTypeIdentifierDistanceDownhillSnowSports"),
            km("distance_paddle_sports", "HKQuantityTypeIdentifierDistancePaddleSports"),
            km("distance_rowing", "HKQuantityTypeIdentifierDistanceRowing"),
            km("distance_skating_sports", "HKQuantityTypeIdentifierDistanceSkatingSports"),
            convertedQuantity(
                "electrodermal_activity",
                "HKQuantityTypeIdentifierElectrodermalActivity",
                symbol: "mcS",
                cumulative: false,
                sensitivity: .sensitive,
                haUnit: "µS",
                haDeviceClass: nil,
                haStateClass: "measurement"
            ),
            convertedQuantity(
                "environmental_sound_reduction",
                "HKQuantityTypeIdentifierEnvironmentalSoundReduction",
                symbol: "dBASPL",
                cumulative: false,
                sensitivity: .routine,
                haUnit: "dBA",
                haDeviceClass: "sound_pressure",
                haStateClass: "measurement"
            ),
            convertedQuantity(
                "estimated_workout_effort_score",
                "HKQuantityTypeIdentifierEstimatedWorkoutEffortScore",
                symbol: "appleEffortScore",
                cumulative: false,
                sensitivity: .routine,
                haUnit: nil,
                haDeviceClass: nil,
                haStateClass: "measurement"
            ),
            convertedQuantity(
                "forced_expiratory_volume_1",
                "HKQuantityTypeIdentifierForcedExpiratoryVolume1",
                symbol: "L",
                cumulative: false,
                sensitivity: .sensitive,
                haUnit: "L",
                haDeviceClass: nil,
                haStateClass: "measurement"
            ),
            convertedQuantity(
                "forced_vital_capacity",
                "HKQuantityTypeIdentifierForcedVitalCapacity",
                symbol: "L",
                cumulative: false,
                sensitivity: .sensitive,
                haUnit: "L",
                haDeviceClass: nil,
                haStateClass: "measurement"
            ),
            convertedQuantity(
                "headphone_audio_exposure",
                "HKQuantityTypeIdentifierHeadphoneAudioExposure",
                symbol: "dBASPL",
                cumulative: false,
                sensitivity: .routine,
                haUnit: "dBA",
                haDeviceClass: "sound_pressure",
                haStateClass: "measurement"
            ),
            convertedQuantity(
                "heart_rate_recovery_one_minute",
                "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute",
                symbol: "count/min",
                cumulative: false,
                sensitivity: .routine,
                haUnit: "bpm",
                haDeviceClass: nil,
                haStateClass: "measurement"
            ),
            count(
                "inhaler_usage",
                "HKQuantityTypeIdentifierInhalerUsage",
                cumulative: true,
                sensitivity: .sensitive
            ),
            convertedQuantity(
                "insulin_delivery",
                "HKQuantityTypeIdentifierInsulinDelivery",
                symbol: "IU",
                cumulative: true,
                sensitivity: .sensitive,
                haUnit: "IU",
                haDeviceClass: nil,
                haStateClass: "total_increasing"
            ),
            count(
                "nike_fuel",
                "HKQuantityTypeIdentifierNikeFuel",
                cumulative: true,
                sensitivity: .routine
            ),
            count(
                "number_of_alcoholic_beverages",
                "HKQuantityTypeIdentifierNumberOfAlcoholicBeverages",
                cumulative: true,
                sensitivity: .sensitive
            ),
            count(
                "number_of_times_fallen",
                "HKQuantityTypeIdentifierNumberOfTimesFallen",
                cumulative: true,
                sensitivity: .sensitive
            ),
            speed("paddle_sports_speed", "HKQuantityTypeIdentifierPaddleSportsSpeed"),
            convertedQuantity(
                "peak_expiratory_flow_rate",
                "HKQuantityTypeIdentifierPeakExpiratoryFlowRate",
                symbol: "L/min",
                cumulative: false,
                sensitivity: .sensitive,
                haUnit: "L/min",
                haDeviceClass: nil,
                haStateClass: "measurement"
            ),
            percent(
                "peripheral_perfusion_index",
                "HKQuantityTypeIdentifierPeripheralPerfusionIndex",
                .sensitive
            ),
            speed("rowing_speed", "HKQuantityTypeIdentifierRowingSpeed"),
            convertedQuantity(
                "running_ground_contact_time",
                "HKQuantityTypeIdentifierRunningGroundContactTime",
                symbol: "ms",
                cumulative: false,
                sensitivity: .routine,
                haUnit: "ms",
                haDeviceClass: "duration",
                haStateClass: "measurement"
            ),
            watts("running_power", "HKQuantityTypeIdentifierRunningPower"),
            convertedQuantity(
                "running_stride_length",
                "HKQuantityTypeIdentifierRunningStrideLength",
                symbol: "m",
                cumulative: false,
                sensitivity: .routine,
                haUnit: "m",
                haDeviceClass: "distance",
                haStateClass: "measurement"
            ),
            convertedQuantity(
                "running_vertical_oscillation",
                "HKQuantityTypeIdentifierRunningVerticalOscillation",
                symbol: "m",
                cumulative: false,
                sensitivity: .routine,
                haUnit: "m",
                haDeviceClass: "distance",
                haStateClass: "measurement"
            ),
            convertedQuantity(
                "six_minute_walk_test_distance",
                "HKQuantityTypeIdentifierSixMinuteWalkTestDistance",
                symbol: "m",
                cumulative: false,
                sensitivity: .routine,
                haUnit: "m",
                haDeviceClass: "distance",
                haStateClass: "measurement"
            ),
            speed("stair_descent_speed", "HKQuantityTypeIdentifierStairDescentSpeed"),
            count(
                "uv_exposure",
                "HKQuantityTypeIdentifierUVExposure",
                cumulative: false,
                sensitivity: .routine
            ),
            convertedQuantity(
                "underwater_depth",
                "HKQuantityTypeIdentifierUnderwaterDepth",
                symbol: "m",
                cumulative: false,
                sensitivity: .routine,
                haUnit: "m",
                haDeviceClass: "distance",
                haStateClass: "measurement"
            ),
            convertedQuantity(
                "waist_circumference",
                "HKQuantityTypeIdentifierWaistCircumference",
                symbol: "m",
                cumulative: false,
                sensitivity: .sensitive,
                haUnit: "m",
                haDeviceClass: "distance",
                haStateClass: "measurement"
            ),
            percent(
                "walking_asymmetry_percentage",
                "HKQuantityTypeIdentifierWalkingAsymmetryPercentage",
                .routine
            ),
            percent(
                "walking_double_support_percentage",
                "HKQuantityTypeIdentifierWalkingDoubleSupportPercentage",
                .routine
            ),
            convertedQuantity(
                "walking_step_length",
                "HKQuantityTypeIdentifierWalkingStepLength",
                symbol: "m",
                cumulative: false,
                sensitivity: .routine,
                haUnit: "m",
                haDeviceClass: "distance",
                haStateClass: "measurement"
            ),
            convertedQuantity(
                "water_temperature",
                "HKQuantityTypeIdentifierWaterTemperature",
                symbol: "degC",
                cumulative: false,
                sensitivity: .routine,
                haUnit: "°C",
                haDeviceClass: "temperature",
                haStateClass: "measurement"
            ),
            convertedQuantity(
                "workout_effort_score",
                "HKQuantityTypeIdentifierWorkoutEffortScore",
                symbol: "appleEffortScore",
                cumulative: false,
                sensitivity: .routine,
                haUnit: nil,
                haDeviceClass: nil,
                haStateClass: "measurement"
            ),
        ]
    }()

    public static let all: [MetricDeclaration] = [
        stepCount,
        heartRate,
        activeEnergy,
        walkingRunningDistance,
        bodyMass,
        oxygenSaturation,
        respiratoryRate,
        restingHeartRate,
        vo2Max,
        bloodGlucose,
        cyclingDistance,
        flightsClimbed,
        basalEnergy,
        exerciseTime,
        standTime,
        walkingHeartRateAverage,
        heartRateVariabilitySDNN,
        bodyTemperature,
        basalBodyTemperature,
        height,
        bodyFatPercentage,
        bodyMassIndex,
        leanBodyMass,
        dietaryWater,
        bloodPressureSystolic,
        bloodPressureDiastolic,
        swimmingDistance,
        wheelchairDistance,
        pushCount,
        swimmingStrokeCount,
        walkingSpeed,
        runningSpeed,
        cyclingSpeed,
        stairAscentSpeed,
        timeInDaylight,
        environmentalAudioExposure,
        appleMoveTime,
        physicalEffort,
    ] + convertedQuantities

    public static let sleepAnalysis = MetricDeclaration(
        id: MetricID(rawValue: "sleep_analysis"),
        wireId: "sleep_analysis",
        hkIdentifier: "HKCategoryTypeIdentifierSleepAnalysis",
        canonicalUnit: CanonicalUnit(symbol: "s"),
        wireUnit: "s",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .routine,
        haUnit: "s",
        haDeviceClass: "duration",
        haStateClass: nil,
        haRequiresAggregate: false,
        kind: "sample.category"
    )

    public static let mindfulSession = MetricDeclaration(
        id: MetricID(rawValue: "mindful_session"),
        wireId: "mindful_session",
        hkIdentifier: "HKCategoryTypeIdentifierMindfulSession",
        canonicalUnit: CanonicalUnit(symbol: "min"),
        wireUnit: "min",
        cumulative: true,
        usesHealthKitStatistics: false,
        sensitivity: .routine,
        haUnit: "min",
        haDeviceClass: "duration",
        haStateClass: "total_increasing",
        haRequiresAggregate: true,
        kind: "sample.category"
    )

    public static let workout = MetricDeclaration(
        id: MetricID(rawValue: "workout"),
        wireId: "workout",
        hkIdentifier: "HKWorkoutTypeIdentifier",
        canonicalUnit: CanonicalUnit(symbol: "s"),
        wireUnit: "s",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .routine,
        haUnit: nil,
        haDeviceClass: nil,
        haStateClass: nil,
        haRequiresAggregate: false,
        kind: "workout"
    )

    /// UX-15: mental wellbeing is selectable only with individual confirmation.
    public static let stateOfMind = MetricDeclaration(
        id: MetricID(rawValue: "state_of_mind"),
        wireId: "state_of_mind",
        hkIdentifier: "HKDataTypeIdentifierStateOfMind",
        canonicalUnit: CanonicalUnit(symbol: "1"),
        wireUnit: "1",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .sensitive,
        haUnit: nil,
        haDeviceClass: nil,
        haStateClass: nil,
        haRequiresAggregate: false,
        kind: "sample.stateOfMind"
    )

    /// Converted HealthKit category families that are not sleep or mindful session.
    /// UX-15: cycle, pregnancy, sexual activity, and symptoms stay sensitive.
    public static let convertedCategories: [MetricDeclaration] = [
        convertedCategory("menstrual_flow", "HKCategoryTypeIdentifierMenstrualFlow", .sensitive),
        convertedCategory("intermenstrual_bleeding", "HKCategoryTypeIdentifierIntermenstrualBleeding", .sensitive),
        convertedCategory("infrequent_menstrual_cycles", "HKCategoryTypeIdentifierInfrequentMenstrualCycles", .sensitive),
        convertedCategory("irregular_menstrual_cycles", "HKCategoryTypeIdentifierIrregularMenstrualCycles", .sensitive),
        convertedCategory("persistent_intermenstrual_bleeding", "HKCategoryTypeIdentifierPersistentIntermenstrualBleeding", .sensitive),
        convertedCategory("prolonged_menstrual_periods", "HKCategoryTypeIdentifierProlongedMenstrualPeriods", .sensitive),
        convertedCategory("cervical_mucus_quality", "HKCategoryTypeIdentifierCervicalMucusQuality", .sensitive),
        convertedCategory("ovulation_test_result", "HKCategoryTypeIdentifierOvulationTestResult", .sensitive),
        convertedCategory("progesterone_test_result", "HKCategoryTypeIdentifierProgesteroneTestResult", .sensitive),
        convertedCategory("pregnancy", "HKCategoryTypeIdentifierPregnancy", .sensitive),
        convertedCategory("pregnancy_test_result", "HKCategoryTypeIdentifierPregnancyTestResult", .sensitive),
        convertedCategory("contraceptive", "HKCategoryTypeIdentifierContraceptive", .sensitive),
        convertedCategory("lactation", "HKCategoryTypeIdentifierLactation", .sensitive),
        convertedCategory("sexual_activity", "HKCategoryTypeIdentifierSexualActivity", .sensitive),
        convertedCategory("high_heart_rate_event", "HKCategoryTypeIdentifierHighHeartRateEvent", .routine),
        convertedCategory("low_heart_rate_event", "HKCategoryTypeIdentifierLowHeartRateEvent", .routine),
        convertedCategory("irregular_heart_rhythm_event", "HKCategoryTypeIdentifierIrregularHeartRhythmEvent", .routine),
        convertedCategory("audio_exposure_event", "HKCategoryTypeIdentifierHeadphoneAudioExposureEvent", .routine),
        convertedCategory("environmental_audio_exposure_event", "HKCategoryTypeIdentifierAudioExposureEvent", .routine),
        convertedCategory("handwashing_event", "HKCategoryTypeIdentifierHandwashingEvent", .routine),
        convertedCategory("toothbrushing_event", "HKCategoryTypeIdentifierToothbrushingEvent", .routine),
        convertedCategory("appetite_changes", "HKCategoryTypeIdentifierAppetiteChanges", .sensitive),
        convertedCategory("bladder_incontinence", "HKCategoryTypeIdentifierBladderIncontinence", .sensitive),
        convertedCategory("bloating", "HKCategoryTypeIdentifierBloating", .sensitive),
        convertedCategory("chills", "HKCategoryTypeIdentifierChills", .sensitive),
        convertedCategory("constipation", "HKCategoryTypeIdentifierConstipation", .sensitive),
        convertedCategory("coughing", "HKCategoryTypeIdentifierCoughing", .sensitive),
        convertedCategory("diarrhea", "HKCategoryTypeIdentifierDiarrhea", .sensitive),
        convertedCategory("dizziness", "HKCategoryTypeIdentifierDizziness", .sensitive),
        convertedCategory("dry_skin", "HKCategoryTypeIdentifierDrySkin", .sensitive),
        convertedCategory("fatigue", "HKCategoryTypeIdentifierFatigue", .sensitive),
        convertedCategory("fever", "HKCategoryTypeIdentifierFever", .sensitive),
        convertedCategory("abdominal_cramps", "HKCategoryTypeIdentifierAbdominalCramps", .sensitive),
        convertedCategory("acne", "HKCategoryTypeIdentifierAcne", .sensitive),
        convertedCategory("apple_stand_hour", "HKCategoryTypeIdentifierAppleStandHour", .routine),
        convertedCategory("apple_walking_steadiness_event", "HKCategoryTypeIdentifierAppleWalkingSteadinessEvent", .routine),
        convertedCategory("bleeding_after_pregnancy", "HKCategoryTypeIdentifierBleedingAfterPregnancy", .sensitive),
        convertedCategory("bleeding_during_pregnancy", "HKCategoryTypeIdentifierBleedingDuringPregnancy", .sensitive),
        convertedCategory("breast_pain", "HKCategoryTypeIdentifierBreastPain", .sensitive),
        convertedCategory("chest_tightness_or_pain", "HKCategoryTypeIdentifierChestTightnessOrPain", .sensitive),
        convertedCategory("fainting", "HKCategoryTypeIdentifierFainting", .sensitive),
        convertedCategory("generalized_body_ache", "HKCategoryTypeIdentifierGeneralizedBodyAche", .sensitive),
        convertedCategory("hair_loss", "HKCategoryTypeIdentifierHairLoss", .sensitive),
        convertedCategory("headache", "HKCategoryTypeIdentifierHeadache", .sensitive),
        convertedCategory("heartburn", "HKCategoryTypeIdentifierHeartburn", .sensitive),
        convertedCategory("hot_flashes", "HKCategoryTypeIdentifierHotFlashes", .sensitive),
        convertedCategory("hypertension_event", "HKCategoryTypeIdentifierHypertensionEvent", .sensitive),
        convertedCategory("loss_of_smell", "HKCategoryTypeIdentifierLossOfSmell", .sensitive),
        convertedCategory("loss_of_taste", "HKCategoryTypeIdentifierLossOfTaste", .sensitive),
        convertedCategory("low_cardio_fitness_event", "HKCategoryTypeIdentifierLowCardioFitnessEvent", .sensitive),
        convertedCategory("lower_back_pain", "HKCategoryTypeIdentifierLowerBackPain", .sensitive),
        convertedCategory("memory_lapse", "HKCategoryTypeIdentifierMemoryLapse", .sensitive),
        convertedCategory("mood_changes", "HKCategoryTypeIdentifierMoodChanges", .sensitive),
        convertedCategory("nausea", "HKCategoryTypeIdentifierNausea", .sensitive),
        convertedCategory("night_sweats", "HKCategoryTypeIdentifierNightSweats", .sensitive),
        convertedCategory("pelvic_pain", "HKCategoryTypeIdentifierPelvicPain", .sensitive),
        convertedCategory("rapid_pounding_or_fluttering_heartbeat", "HKCategoryTypeIdentifierRapidPoundingOrFlutteringHeartbeat", .sensitive),
        convertedCategory("runny_nose", "HKCategoryTypeIdentifierRunnyNose", .sensitive),
        convertedCategory("shortness_of_breath", "HKCategoryTypeIdentifierShortnessOfBreath", .sensitive),
        convertedCategory("sinus_congestion", "HKCategoryTypeIdentifierSinusCongestion", .sensitive),
        convertedCategory("skipped_heartbeat", "HKCategoryTypeIdentifierSkippedHeartbeat", .sensitive),
        convertedCategory("sleep_apnea_event", "HKCategoryTypeIdentifierSleepApneaEvent", .sensitive),
        convertedCategory("sleep_changes", "HKCategoryTypeIdentifierSleepChanges", .sensitive),
        convertedCategory("sore_throat", "HKCategoryTypeIdentifierSoreThroat", .sensitive),
        convertedCategory("vaginal_dryness", "HKCategoryTypeIdentifierVaginalDryness", .sensitive),
        convertedCategory("vomiting", "HKCategoryTypeIdentifierVomiting", .sensitive),
        convertedCategory("wheezing", "HKCategoryTypeIdentifierWheezing", .sensitive),
    ]

    /// Converted category, workout, and structured families that are selectable in-app.
    public static let structural: [MetricDeclaration] = [
        sleepAnalysis,
        mindfulSession,
        workout,
        stateOfMind,
    ] + convertedCategories

    public static let biologicalSex = characteristic(
        id: "biologicalSex",
        wireId: "biological_sex",
        hkIdentifier: "HKCharacteristicTypeIdentifierBiologicalSex"
    )
    public static let bloodType = characteristic(
        id: "bloodType",
        wireId: "blood_type",
        hkIdentifier: "HKCharacteristicTypeIdentifierBloodType"
    )
    public static let dateOfBirth = characteristic(
        id: "dateOfBirth",
        wireId: "date_of_birth",
        hkIdentifier: "HKCharacteristicTypeIdentifierDateOfBirth"
    )
    public static let fitzpatrickSkinType = characteristic(
        id: "fitzpatrickSkinType",
        wireId: "fitzpatrick_skin_type",
        hkIdentifier: "HKCharacteristicTypeIdentifierFitzpatrickSkinType"
    )
    public static let wheelchairUse = characteristic(
        id: "wheelchairUse",
        wireId: "wheelchair_use",
        hkIdentifier: "HKCharacteristicTypeIdentifierWheelchairUse"
    )
    public static let activityMoveMode = characteristic(
        id: "activityMoveMode",
        wireId: "activity_move_mode",
        hkIdentifier: "HKCharacteristicTypeIdentifierActivityMoveMode"
    )

    /// Off by default (HK-30). Never in Core Daily or the anchored delta pipeline.
    public static let characteristics: [MetricDeclaration] = [
        biologicalSex,
        bloodType,
        dateOfBirth,
        fitzpatrickSkinType,
        wheelchairUse,
        activityMoveMode,
    ]

    public static let selectable: [MetricDeclaration] = all + structural + characteristics

    private static let declarationByID: [MetricID: MetricDeclaration] = Dictionary(
        uniqueKeysWithValues: selectable.map { ($0.id, $0) }
    )

    public static func declaration(for id: MetricID) -> MetricDeclaration? {
        declarationByID[id]
    }

    public static func isCharacteristic(_ id: MetricID) -> Bool {
        declaration(for: id)?.kind == "characteristic"
    }

    private static func convertedQuantity(
        _ id: String,
        _ hkIdentifier: String,
        symbol: String,
        cumulative: Bool,
        sensitivity: SensitivityClass,
        haUnit: String?,
        haDeviceClass: String?,
        haStateClass: String?
    ) -> MetricDeclaration {
        MetricDeclaration(
            id: MetricID(rawValue: id),
            wireId: id,
            hkIdentifier: hkIdentifier,
            canonicalUnit: CanonicalUnit(symbol: symbol),
            wireUnit: symbol,
            cumulative: cumulative,
            usesHealthKitStatistics: cumulative,
            sensitivity: sensitivity,
            haUnit: haUnit,
            haDeviceClass: haDeviceClass,
            haStateClass: haStateClass,
            haRequiresAggregate: cumulative
        )
    }

    private static func convertedCategory(
        _ id: String,
        _ hkIdentifier: String,
        _ sensitivity: SensitivityClass
    ) -> MetricDeclaration {
        MetricDeclaration(
            id: MetricID(rawValue: id),
            wireId: id,
            hkIdentifier: hkIdentifier,
            canonicalUnit: CanonicalUnit(symbol: "1"),
            wireUnit: "1",
            cumulative: false,
            usesHealthKitStatistics: false,
            sensitivity: sensitivity,
            haUnit: nil,
            haDeviceClass: nil,
            haStateClass: nil,
            haRequiresAggregate: false,
            kind: "sample.category"
        )
    }

    private static func characteristic(
        id: String,
        wireId: String,
        hkIdentifier: String
    ) -> MetricDeclaration {
        MetricDeclaration(
            id: MetricID(rawValue: id),
            wireId: wireId,
            hkIdentifier: hkIdentifier,
            canonicalUnit: CanonicalUnit(symbol: "token"),
            wireUnit: "token",
            cumulative: false,
            usesHealthKitStatistics: false,
            sensitivity: .sensitive,
            haUnit: nil,
            haDeviceClass: nil,
            haStateClass: nil,
            haRequiresAggregate: false,
            kind: "characteristic",
            reidentifying: true,
            characteristicId: id
        )
    }

    /// First-run preset (R-61 / UX-13). Sensitive types stay visible but are never in this list.
    public static var coreDaily: [MetricDeclaration] {
        [
            stepCount,
            walkingRunningDistance,
            cyclingDistance,
            activeEnergy,
            basalEnergy,
            exerciseTime,
            standTime,
            flightsClimbed,
            heartRate,
            restingHeartRate,
            walkingHeartRateAverage,
            dietaryWater,
            swimmingDistance,
            wheelchairDistance,
            pushCount,
            swimmingStrokeCount,
            walkingSpeed,
            runningSpeed,
            cyclingSpeed,
            stairAscentSpeed,
            timeInDaylight,
            environmentalAudioExposure,
            appleMoveTime,
            physicalEffort,
            sleepAnalysis,
            mindfulSession,
            workout,
        ]
    }

    /// Metrics whose canonical aggregate is HealthKit's statistic (R-80 exception list).
    public static var hkStatisticsExceptions: [MetricID] {
        all.filter(\.usesHealthKitStatistics).map(\.id)
    }

    /// Identifiers HealthKit forbids sharing. Authorization must request an empty share set.
    public static let shareDisallowedHKIdentifiers: Set<String> = [
        "HKQuantityTypeIdentifierAppleExerciseTime",
        "HKQuantityTypeIdentifierAppleStandTime",
        "HKQuantityTypeIdentifierAppleMoveTime",
        "HKQuantityTypeIdentifierAppleWalkingSteadiness",
        "HKQuantityTypeIdentifierAppleSleepingWristTemperature",
        "HKQuantityTypeIdentifierAppleSleepingBreathingDisturbances",
        "HKDataTypeIdentifierElectrocardiogram",
    ]
}
