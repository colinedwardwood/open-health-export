// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import MetricCatalog

public enum HAStatisticsError: Error, Equatable {
    case malformed
}

public struct HAStatisticsCase: Sendable, Equatable {
    public var wireID: String
    public var entityID: String
    public var statistic: String
    public var granularity: String
    public var unit: String?
    public var deviceClass: String?
    public var stateClass: String?

    public init(
        wireID: String,
        entityID: String,
        statistic: String,
        granularity: String,
        unit: String?,
        deviceClass: String?,
        stateClass: String?
    ) {
        self.wireID = wireID
        self.entityID = entityID
        self.statistic = statistic
        self.granularity = granularity
        self.unit = unit
        self.deviceClass = deviceClass
        self.stateClass = stateClass
    }
}

public struct HAStatisticsRow: Sendable, Equatable {
    public var start: String
    public var end: String
    public var mean: Double?
    public var sum: Double?

    public init(start: String, end: String, mean: Double?, sum: Double?) {
        self.start = start
        self.end = end
        self.mean = mean
        self.sum = sum
    }
}

/// Attributes a REST/MQTT entity would publish. Rungs 1–3 inspect this; rung 4 inspects the recorder.
public struct HAEntitySnapshot: Sendable, Equatable {
    public var exists: Bool
    public var state: String
    public var unit: String?
    public var deviceClass: String?
    public var stateClass: String?

    public init(
        exists: Bool,
        state: String,
        unit: String?,
        deviceClass: String?,
        stateClass: String?
    ) {
        self.exists = exists
        self.state = state
        self.unit = unit
        self.deviceClass = deviceClass
        self.stateClass = stateClass
    }
}

public enum HAStatisticsContract {
    public static let measurementForbiddenDeviceClasses: Set<String> = [
        "date", "enum", "timestamp",
    ]
    public static let invalidMeasurementEntityID = "sensor.ohe_invalid_enum_measurement"

    /// Attributes posted on `/api/states/<entity_id>`. Nil catalogue fields are omitted, not empty.
    public static func restAttributes(for item: HAStatisticsCase) -> [String: Any] {
        var attributes: [String: Any] = [:]
        if let unit = item.unit {
            attributes["unit_of_measurement"] = unit
        }
        if let deviceClass = item.deviceClass {
            attributes["device_class"] = deviceClass
        }
        if let stateClass = item.stateClass {
            attributes["state_class"] = stateClass
        }
        return attributes
    }

    /// One case per catalogue metric, matching MQTT discovery unique_id / statistic / granularity.
    public static func cases(
        exporterID: String = "device-1234",
        declarations: [MetricDeclaration] = MetricCatalog.all
    ) -> [HAStatisticsCase] {
        let short = String(exporterID.replacingOccurrences(of: "-", with: "").prefix(8))
        return declarations.map { declaration in
            let statistic = declaration.cumulative ? "sum" : "mean"
            let granularity = declaration.cumulative ? "P1D" : "PT1H"
            return HAStatisticsCase(
                wireID: declaration.wireId,
                entityID: "sensor.ohe_\(short)_\(declaration.wireId)_\(statistic)_\(granularity)"
                    .lowercased(),
                statistic: statistic,
                granularity: granularity,
                unit: declaration.haUnit,
                deviceClass: declaration.haDeviceClass,
                stateClass: declaration.haStateClass
            )
        }
    }

    public static func entityMatches(_ snapshot: HAEntitySnapshot, expected: HAStatisticsCase) -> Bool {
        snapshot.exists
            && snapshot.unit == expected.unit
            && snapshot.deviceClass == expected.deviceClass
            && snapshot.stateClass == expected.stateClass
    }

    public static func stateParses(_ snapshot: HAEntitySnapshot, expected: Double, precision: Double = 0.000_001) -> Bool {
        guard let value = Double(snapshot.state) else { return false }
        return abs(value - expected) <= precision
    }

    public static func snapshot(
        from attributes: [String: Any],
        state: String,
        exists: Bool = true
    ) -> HAEntitySnapshot {
        HAEntitySnapshot(
            exists: exists,
            state: state,
            unit: attributes["unit_of_measurement"] as? String,
            deviceClass: attributes["device_class"] as? String,
            stateClass: attributes["state_class"] as? String
        )
    }

    /// HA long-term statistics exist only when `state_class` is present and the combination is valid.
    public static func statisticsWouldRecord(stateClass: String?, deviceClass: String?) -> Bool {
        guard let stateClass else { return false }
        if deviceClass == "enum" { return false }
        if stateClass == "measurement", let deviceClass, measurementForbiddenDeviceClasses.contains(deviceClass) {
            return false
        }
        return stateClass == "measurement" || stateClass == "total_increasing"
    }
}

/// In-process stand-in for `recorder/statistics_during_period` after a forced statistics cycle.
public enum HARecorder {
    public static func statisticsDuringPeriod(
        entityID: String,
        states: [Double],
        stateClass: String?,
        deviceClass: String?,
        start: String = "2026-01-01T00:00:00+00:00",
        end: String = "2026-01-01T01:00:00+00:00"
    ) -> [HAStatisticsRow] {
        guard HAStatisticsContract.statisticsWouldRecord(stateClass: stateClass, deviceClass: deviceClass),
              states.count >= 2
        else {
            return []
        }
        if stateClass == "total_increasing" {
            return [HAStatisticsRow(start: start, end: end, mean: nil, sum: states.reduce(0, +))]
        }
        let mean = states.reduce(0, +) / Double(states.count)
        return [HAStatisticsRow(start: start, end: end, mean: mean, sum: nil)]
    }

    public static func parseWebSocketResult(_ data: Data, entityID: String) throws -> [HAStatisticsRow] {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let result = root["result"] as? [String: Any],
            let rows = result[entityID] as? [Any]
        else {
            return []
        }
        return try rows.map { raw in
            guard let object = raw as? [String: Any],
                  let start = object["start"] as? String,
                  let end = object["end"] as? String
            else {
                throw HAStatisticsError.malformed
            }
            return HAStatisticsRow(
                start: start,
                end: end,
                mean: doubleValue(object["mean"]),
                sum: doubleValue(object["sum"])
            )
        }
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        if any is NSNull { return nil }
        if let value = any as? Double { return value }
        if let value = any as? Int { return Double(value) }
        if let value = any as? NSNumber { return value.doubleValue }
        return nil
    }
}
