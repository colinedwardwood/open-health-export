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

    public static let all: [MetricDeclaration] = [stepCount, heartRate]

    public static func declaration(for id: MetricID) -> MetricDeclaration? {
        all.first { $0.id == id }
    }

    /// Metrics whose canonical aggregate is HealthKit's statistic (R-80 exception list).
    public static var hkStatisticsExceptions: [MetricID] {
        all.filter(\.usesHealthKitStatistics).map(\.id)
    }
}
