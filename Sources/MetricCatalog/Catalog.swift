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
        haRequiresAggregate: Bool
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
    ]

    public static func declaration(for id: MetricID) -> MetricDeclaration? {
        all.first { $0.id == id }
    }

    /// Metrics whose canonical aggregate is HealthKit's statistic (R-80 exception list).
    public static var hkStatisticsExceptions: [MetricID] {
        all.filter(\.usesHealthKitStatistics).map(\.id)
    }
}
