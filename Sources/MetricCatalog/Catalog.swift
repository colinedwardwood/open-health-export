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
        haDeviceClass: "energy",
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
        canonicalUnit: CanonicalUnit(symbol: "mmol/L"),
        wireUnit: "mmol/L",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .sensitive,
        haUnit: "mmol/L",
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
    ]

    public static func declaration(for id: MetricID) -> MetricDeclaration? {
        all.first { $0.id == id }
    }

    /// Metrics whose canonical aggregate is HealthKit's statistic (R-80 exception list).
    public static var hkStatisticsExceptions: [MetricID] {
        all.filter(\.usesHealthKitStatistics).map(\.id)
    }
}
