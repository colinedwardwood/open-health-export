// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public protocol TelemetryDimensionValue: RawRepresentable, CaseIterable, Sendable
where RawValue == String {
    static var other: Self { get }
}

public enum TelemetryTriggerClass: String, TelemetryDimensionValue {
    case user
    case systemObserver = "system_observer"
    case systemScheduled = "system_scheduled"
    case other
}

public enum TelemetryDestinationKind: String, TelemetryDimensionValue {
    case http
    case mqtt
    case file
    case other
}

public enum TelemetryOutcomeClass: String, TelemetryDimensionValue {
    case succeeded
    case partial
    case unconfirmed
    case failed
    case deferred
    case cancelled
    case other
}

public enum TelemetryPhase: String, TelemetryDimensionValue {
    case discover
    case query
    case transform
    case serialise
    case transmit
    case acknowledge
    case commit
    case other
}

public enum TelemetryDirection: String, TelemetryDimensionValue {
    case read
    case sent
    case acknowledged
    case other
}

public enum TelemetryFormat: String, TelemetryDimensionValue {
    case json
    case csv
    case ndjson
    case other
}

public enum TelemetrySignal: String, TelemetryDimensionValue {
    case trace
    case metric
    case other
}

public enum TelemetryDropReason: String, TelemetryDimensionValue {
    case unknownAttributeValue = "unknown_attribute_value"
    case ageLimit = "age_limit"
    case countLimit = "count_limit"
    case byteLimit = "byte_limit"
    case invalidPayload = "invalid_payload"
    case other
}

public struct TelemetryDroppedCounter: Sendable, Equatable {
    public private(set) var unknownAttributeValues = 0

    public init() {}

    public mutating func recordUnknownAttributeValue() {
        unknownAttributeValues += 1
    }

    public var metricPoint: TelemetryDroppedMetricPoint {
        TelemetryDroppedMetricPoint(
            metric: "ohe.telemetry.dropped",
            signal: .metric,
            reason: .unknownAttributeValue,
            count: unknownAttributeValues
        )
    }
}

public struct TelemetryDroppedMetricPoint: Sendable, Equatable {
    public var metric: String
    public var signal: TelemetrySignal
    public var reason: TelemetryDropReason
    public var count: Int

    public init(
        metric: String,
        signal: TelemetrySignal,
        reason: TelemetryDropReason,
        count: Int
    ) {
        self.metric = metric
        self.signal = signal
        self.reason = reason
        self.count = count
    }
}

public enum TelemetryAttributeGuard {
    public static func normalize<Value: TelemetryDimensionValue>(
        _ rawValue: String,
        as _: Value.Type,
        dropped: inout TelemetryDroppedCounter
    ) -> Value {
        guard let value = Value(rawValue: rawValue) else {
            dropped.recordUnknownAttributeValue()
            return Value.other
        }
        return value
    }
}

public struct TelemetryMetricDeclaration: Sendable, Equatable {
    public var name: String
    public var defaultDimensionCardinalities: [Int]
    public var healthTypeDimensionCardinality: Int?

    public init(
        name: String,
        defaultDimensionCardinalities: [Int],
        healthTypeDimensionCardinality: Int? = nil
    ) {
        self.name = name
        self.defaultDimensionCardinalities = defaultDimensionCardinalities
        self.healthTypeDimensionCardinality = healthTypeDimensionCardinality
    }

    public func seriesCount(healthTypeEnabled: Bool) -> Int {
        let base = defaultDimensionCardinalities.reduce(1, *)
        guard healthTypeEnabled, let healthTypeDimensionCardinality else { return base }
        return base * healthTypeDimensionCardinality
    }
}

public enum TelemetryCardinalityBudget {
    public static let defaultLimit = 500
    public static let healthTypeEnabledLimit = 2_500
    public static let destinationSlots = 8
    public static let errorClasses = 28
    public static let wakeDispositions = 6
    public static let healthTypeSlots = 64

    public static let declarations: [TelemetryMetricDeclaration] = [
        .init(
            name: "ohe.export.runs",
            defaultDimensionCardinalities: [
                TelemetryTriggerClass.allCases.count,
                TelemetryDestinationKind.allCases.count,
                TelemetryOutcomeClass.allCases.count,
            ]
        ),
        .init(
            name: "ohe.export.duration",
            defaultDimensionCardinalities: [
                TelemetryDestinationKind.allCases.count,
                TelemetryPhase.allCases.count,
            ]
        ),
        .init(
            name: "ohe.export.errors",
            defaultDimensionCardinalities: [
                errorClasses,
                TelemetryDestinationKind.allCases.count,
            ]
        ),
        .init(
            name: "ohe.export.samples",
            defaultDimensionCardinalities: [
                TelemetryDestinationKind.allCases.count,
                TelemetryDirection.allCases.count,
            ],
            healthTypeDimensionCardinality: healthTypeSlots
        ),
        .init(
            name: "ohe.export.payload.size",
            defaultDimensionCardinalities: [
                TelemetryDestinationKind.allCases.count,
                TelemetryFormat.allCases.count,
            ]
        ),
        .init(name: "ohe.export.retries", defaultDimensionCardinalities: [errorClasses]),
        .init(name: "ohe.destination.staleness", defaultDimensionCardinalities: [destinationSlots]),
        .init(
            name: "ohe.destination.last_success.timestamp",
            defaultDimensionCardinalities: [destinationSlots]
        ),
        .init(
            name: "ohe.background.wake",
            defaultDimensionCardinalities: [
                TelemetryTriggerClass.allCases.count,
                wakeDispositions,
            ]
        ),
        .init(
            name: "ohe.healthkit.query.duration",
            defaultDimensionCardinalities: [],
            healthTypeDimensionCardinality: healthTypeSlots
        ),
        .init(
            name: "ohe.telemetry.dropped",
            defaultDimensionCardinalities: [
                TelemetrySignal.allCases.count,
                TelemetryDropReason.allCases.count,
            ]
        ),
        .init(name: "ohe.journal.bytes", defaultDimensionCardinalities: []),
        .init(name: "ohe.journal.rows", defaultDimensionCardinalities: []),
    ]

    public static func totalSeries(healthTypeEnabled: Bool) -> Int {
        declarations.reduce(0) {
            $0 + $1.seriesCount(healthTypeEnabled: healthTypeEnabled)
        }
    }
}
