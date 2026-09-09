import Foundation

public struct StateOfMindRecord: Sendable, Codable, Equatable {
    public var key: RecordKey
    public var metric: MetricID
    public var start: String
    public var end: String
    public var timeZoneOffsetMinutes: Int
    public var timeZoneSource: TimeZoneSource
    public var kindOfEntry: String
    public var valence: Double
    public var valenceClassification: String
    public var labels: [String]
    public var associations: [String]
    public var observedAt: String
    public var source: SampleSourceIdentity?
    public var device: SampleDevice?
    public var wasUserEntered: Bool?

    public init(
        key: RecordKey,
        metric: MetricID = MetricID(rawValue: "state_of_mind"),
        start: String,
        end: String,
        timeZoneOffsetMinutes: Int,
        timeZoneSource: TimeZoneSource,
        kindOfEntry: String,
        valence: Double,
        valenceClassification: String,
        labels: [String],
        associations: [String],
        observedAt: String,
        source: SampleSourceIdentity? = nil,
        device: SampleDevice? = nil,
        wasUserEntered: Bool? = nil
    ) {
        self.key = key
        self.metric = metric
        self.start = start
        self.end = end
        self.timeZoneOffsetMinutes = timeZoneOffsetMinutes
        self.timeZoneSource = timeZoneSource
        self.kindOfEntry = kindOfEntry
        self.valence = valence
        self.valenceClassification = valenceClassification
        self.labels = labels.sorted()
        self.associations = associations.sorted()
        self.observedAt = observedAt
        self.source = source
        self.device = device
        self.wasUserEntered = wasUserEntered
    }
}

public struct ECGRecord: Sendable, Codable, Equatable {
    public var key: RecordKey
    public var metric: MetricID
    public var start: String
    public var end: String
    public var timeZoneOffsetMinutes: Int
    public var timeZoneSource: TimeZoneSource
    public var classification: String
    public var averageHeartRate: Double?
    public var samplingHz: Double
    public var voltageCount: Int
    public var symptomsStatus: String?
    public var observedAt: String
    public var source: SampleSourceIdentity?
    public var device: SampleDevice?
    public var wasUserEntered: Bool?

    public init(
        key: RecordKey,
        metric: MetricID = MetricID(rawValue: "electrocardiogram"),
        start: String,
        end: String,
        timeZoneOffsetMinutes: Int,
        timeZoneSource: TimeZoneSource,
        classification: String,
        averageHeartRate: Double? = nil,
        samplingHz: Double,
        voltageCount: Int,
        symptomsStatus: String? = nil,
        observedAt: String,
        source: SampleSourceIdentity? = nil,
        device: SampleDevice? = nil,
        wasUserEntered: Bool? = nil
    ) {
        self.key = key
        self.metric = metric
        self.start = start
        self.end = end
        self.timeZoneOffsetMinutes = timeZoneOffsetMinutes
        self.timeZoneSource = timeZoneSource
        self.classification = classification
        self.averageHeartRate = averageHeartRate
        self.samplingHz = samplingHz
        self.voltageCount = voltageCount
        self.symptomsStatus = symptomsStatus
        self.observedAt = observedAt
        self.source = source
        self.device = device
        self.wasUserEntered = wasUserEntered
    }
}

public struct AudiogramSensitivityPoint: Sendable, Codable, Equatable {
    public var frequencyHz: Double
    public var leftEarDbHL: Double?
    public var rightEarDbHL: Double?
    public var leftEarMasked: Bool?
    public var rightEarMasked: Bool?

    public init(
        frequencyHz: Double,
        leftEarDbHL: Double? = nil,
        rightEarDbHL: Double? = nil,
        leftEarMasked: Bool? = nil,
        rightEarMasked: Bool? = nil
    ) {
        self.frequencyHz = frequencyHz
        self.leftEarDbHL = leftEarDbHL
        self.rightEarDbHL = rightEarDbHL
        self.leftEarMasked = leftEarMasked
        self.rightEarMasked = rightEarMasked
    }
}

public struct AudiogramRecord: Sendable, Codable, Equatable {
    public var key: RecordKey
    public var metric: MetricID
    public var start: String
    public var end: String
    public var timeZoneOffsetMinutes: Int
    public var timeZoneSource: TimeZoneSource
    public var sensitivityPoints: [AudiogramSensitivityPoint]
    public var observedAt: String
    public var source: SampleSourceIdentity?
    public var device: SampleDevice?
    public var wasUserEntered: Bool?

    public init(
        key: RecordKey,
        metric: MetricID = MetricID(rawValue: "audiogram"),
        start: String,
        end: String,
        timeZoneOffsetMinutes: Int,
        timeZoneSource: TimeZoneSource,
        sensitivityPoints: [AudiogramSensitivityPoint],
        observedAt: String,
        source: SampleSourceIdentity? = nil,
        device: SampleDevice? = nil,
        wasUserEntered: Bool? = nil
    ) {
        self.key = key
        self.metric = metric
        self.start = start
        self.end = end
        self.timeZoneOffsetMinutes = timeZoneOffsetMinutes
        self.timeZoneSource = timeZoneSource
        self.sensitivityPoints = sensitivityPoints.sorted { $0.frequencyHz < $1.frequencyHz }
        self.observedAt = observedAt
        self.source = source
        self.device = device
        self.wasUserEntered = wasUserEntered
    }
}

public struct MedicationDoseRecord: Sendable, Codable, Equatable {
    public var key: RecordKey
    public var metric: MetricID
    public var start: String
    public var end: String
    public var timeZoneOffsetMinutes: Int
    public var timeZoneSource: TimeZoneSource
    public var medicationName: String
    public var doseQuantity: Double?
    public var doseUnit: String?
    public var status: String
    public var scheduledAt: String?
    public var observedAt: String
    public var source: SampleSourceIdentity?
    public var device: SampleDevice?
    public var wasUserEntered: Bool?

    public init(
        key: RecordKey,
        metric: MetricID = MetricID(rawValue: "medication_dose"),
        start: String,
        end: String,
        timeZoneOffsetMinutes: Int,
        timeZoneSource: TimeZoneSource,
        medicationName: String,
        doseQuantity: Double? = nil,
        doseUnit: String? = nil,
        status: String,
        scheduledAt: String? = nil,
        observedAt: String,
        source: SampleSourceIdentity? = nil,
        device: SampleDevice? = nil,
        wasUserEntered: Bool? = nil
    ) {
        self.key = key
        self.metric = metric
        self.start = start
        self.end = end
        self.timeZoneOffsetMinutes = timeZoneOffsetMinutes
        self.timeZoneSource = timeZoneSource
        self.medicationName = medicationName
        self.doseQuantity = doseQuantity
        self.doseUnit = doseUnit
        self.status = status
        self.scheduledAt = scheduledAt
        self.observedAt = observedAt
        self.source = source
        self.device = device
        self.wasUserEntered = wasUserEntered
    }
}

public struct WorkoutRoutePoint: Sendable, Codable, Equatable {
    public var timestamp: String
    public var latitude: Double
    public var longitude: Double
    public var altitudeM: Double?
    public var horizontalAccuracyM: Double?
    public var verticalAccuracyM: Double?
    public var speedMps: Double?
    public var speedAccuracyMps: Double?
    public var courseDeg: Double?
    public var courseAccuracyDeg: Double?

    public init(
        timestamp: String,
        latitude: Double,
        longitude: Double,
        altitudeM: Double? = nil,
        horizontalAccuracyM: Double? = nil,
        verticalAccuracyM: Double? = nil,
        speedMps: Double? = nil,
        speedAccuracyMps: Double? = nil,
        courseDeg: Double? = nil,
        courseAccuracyDeg: Double? = nil
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitudeM = altitudeM
        self.horizontalAccuracyM = horizontalAccuracyM
        self.verticalAccuracyM = verticalAccuracyM
        self.speedMps = speedMps
        self.speedAccuracyMps = speedAccuracyMps
        self.courseDeg = courseDeg
        self.courseAccuracyDeg = courseAccuracyDeg
    }
}

public struct SeriesMetricPoint: Sendable, Codable, Equatable {
    public var timestamp: String
    public var value: Double

    public init(timestamp: String, value: Double) {
        self.timestamp = timestamp
        self.value = value
    }
}

public enum SeriesPayload: Sendable, Equatable {
    case ecgVoltage(voltages: [Double], samplingHz: Double)
    case heartbeat(intervalsMs: [Double], precededByGap: [Bool])
    case workoutRoute(points: [WorkoutRoutePoint])
    case workoutMetric(metricId: String, unit: String, points: [SeriesMetricPoint])

    public var wireKind: String {
        switch self {
        case .ecgVoltage: "series.ecgVoltage"
        case .heartbeat: "series.heartbeat"
        case .workoutRoute: "series.workoutRoute"
        case .workoutMetric: "series.workoutMetric"
        }
    }
}

public struct SeriesRecord: Sendable, Equatable {
    public var parentUUID: String
    public var parentStart: String
    public var chunkIndex: Int
    public var chunkCount: Int?
    public var startIndex: Int
    public var payload: SeriesPayload

    public var uuid: String {
        UUIDV5.seriesChunk(
            parentUUID: parentUUID,
            kind: payload.wireKind,
            chunkIndex: chunkIndex
        )
    }

    public init(
        parentUUID: String,
        parentStart: String,
        chunkIndex: Int,
        chunkCount: Int? = nil,
        startIndex: Int,
        payload: SeriesPayload
    ) {
        self.parentUUID = parentUUID
        self.parentStart = parentStart
        self.chunkIndex = chunkIndex
        self.chunkCount = chunkCount
        self.startIndex = startIndex
        self.payload = payload
    }
}
