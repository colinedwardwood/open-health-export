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

    public init(
        id: MetricID,
        wireId: String,
        hkIdentifier: String,
        canonicalUnit: CanonicalUnit,
        wireUnit: String,
        cumulative: Bool,
        usesHealthKitStatistics: Bool,
        sensitivity: SensitivityClass
    ) {
        self.id = id
        self.wireId = wireId
        self.hkIdentifier = hkIdentifier
        self.canonicalUnit = canonicalUnit
        self.wireUnit = wireUnit
        self.cumulative = cumulative
        self.usesHealthKitStatistics = usesHealthKitStatistics
        self.sensitivity = sensitivity
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
        sensitivity: .routine
    )

    public static let heartRate = MetricDeclaration(
        id: MetricID(rawValue: "heartRate"),
        wireId: "heart_rate",
        hkIdentifier: "HKQuantityTypeIdentifierHeartRate",
        canonicalUnit: CanonicalUnit(symbol: "count/min"),
        wireUnit: "bpm",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .routine
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
