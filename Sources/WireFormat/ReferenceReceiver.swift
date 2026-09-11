// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// G3/G4/R-115: upsert-by-UUID, tombstones delete, unknown fields ignored.
public struct ReferenceReceiver: Sendable, Equatable {
    public var quantities: [String: Double]
    public var categories: [String: Int]
    public var structuralRecords: [String: String]
    public var tombstones: Set<String>
    public var ingested: Int
    /// uuid → wire metricId for live quantities. Not part of G4 expectedState.
    public var quantityMetrics: [String: String]

    public init(
        quantities: [String: Double] = [:],
        categories: [String: Int] = [:],
        structuralRecords: [String: String] = [:],
        tombstones: Set<String> = [],
        ingested: Int = 0,
        quantityMetrics: [String: String] = [:]
    ) {
        self.quantities = quantities
        self.categories = categories
        self.structuralRecords = structuralRecords
        self.tombstones = tombstones
        self.ingested = ingested
        self.quantityMetrics = quantityMetrics
    }

    public mutating func ingest(ndjson: String) throws {
        for line in ndjson.split(whereSeparator: \.isNewline) where !line.isEmpty {
            try ingest(line: Data(line.utf8))
        }
    }

    public mutating func ingest(line: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
              let kind = object["kind"] as? String
        else {
            throw JSONSchemaError.missingKind
        }
        ingested += 1
        if let uuid = object["uuid"] as? String,
           tombstones.contains(uuid),
           kind != "tombstone" {
            return
        }
        switch kind {
        case "sample.quantity":
            guard let uuid = object["uuid"] as? String, isNumber(object["value"]) else {
                throw JSONSchemaError.missingRequired("uuid")
            }
            quantities[uuid] = doubleValue(object["value"])
            quantityMetrics[uuid] = object["metricId"] as? String ?? "unknown"
            categories.removeValue(forKey: uuid)
            tombstones.remove(uuid)
        case "sample.category":
            guard let uuid = object["uuid"] as? String,
                  let value = object["categoryValue"] as? NSNumber
            else {
                throw JSONSchemaError.missingRequired("uuid")
            }
            categories[uuid] = value.intValue
            quantities.removeValue(forKey: uuid)
            quantityMetrics.removeValue(forKey: uuid)
            tombstones.remove(uuid)
        case "sample.correlation", "workout",
             "sample.stateOfMind", "sample.ecg", "sample.audiogram", "medicationDose",
             "series.ecgVoltage", "series.heartbeat", "series.workoutRoute",
             "series.workoutMetric":
            guard let uuid = object["uuid"] as? String else {
                throw JSONSchemaError.missingRequired("uuid")
            }
            structuralRecords[uuid] = kind
            quantities.removeValue(forKey: uuid)
            quantityMetrics.removeValue(forKey: uuid)
            categories.removeValue(forKey: uuid)
            tombstones.remove(uuid)
        case "tombstone":
            guard let uuid = object["uuid"] as? String else {
                throw JSONSchemaError.missingRequired("uuid")
            }
            quantities.removeValue(forKey: uuid)
            quantityMetrics.removeValue(forKey: uuid)
            categories.removeValue(forKey: uuid)
            structuralRecords.removeValue(forKey: uuid)
            tombstones.insert(uuid)
        default:
            break
        }
    }

    public func expectedState() -> [String: Any] {
        var state: [String: Any] = [
            "quantities": quantities.keys.sorted().reduce(into: [String: Double]()) { $0[$1] = quantities[$1] },
            "tombstones": tombstones.sorted(),
            "ingested": ingested,
        ]
        if !categories.isEmpty {
            state["categories"] = categories.keys.sorted().reduce(into: [String: Int]()) {
                $0[$1] = categories[$1]
            }
        }
        if !structuralRecords.isEmpty {
            state["structuralRecords"] = structuralRecords.keys.sorted().reduce(
                into: [String: String]()
            ) {
                $0[$1] = structuralRecords[$1]
            }
        }
        return state
    }

    /// Prometheus text for Grafana. Live last-values are the records the operator posted.
    public func prometheusExposition() -> String {
        var last: [String: Double] = [:]
        var counts: [String: Int] = [:]
        for uuid in quantities.keys.sorted() {
            let metric = prometheusLabel(quantityMetrics[uuid] ?? "unknown")
            counts[metric, default: 0] += 1
            last[metric] = quantities[uuid] ?? 0
        }
        var lines = [
            "# HELP ohe_receiver_ingested_lines NDJSON lines accepted, including unknown kinds.",
            "# TYPE ohe_receiver_ingested_lines counter",
            "ohe_receiver_ingested_lines \(ingested)",
            "# HELP ohe_receiver_live_quantities Quantity records currently held.",
            "# TYPE ohe_receiver_live_quantities gauge",
            "ohe_receiver_live_quantities \(quantities.count)",
            "# HELP ohe_receiver_tombstones Tombstone uuids currently held.",
            "# TYPE ohe_receiver_tombstones gauge",
            "ohe_receiver_tombstones \(tombstones.count)",
            "# HELP ohe_receiver_live_quantity_count Live quantity records per wire metric id.",
            "# TYPE ohe_receiver_live_quantity_count gauge",
        ]
        for metric in counts.keys.sorted() {
            lines.append(
                "ohe_receiver_live_quantity_count{metric_id=\"\(metric)\"} \(counts[metric]!)"
            )
        }
        lines.append("# HELP ohe_receiver_live_quantity_last Last live value per wire metric id.")
        lines.append("# TYPE ohe_receiver_live_quantity_last gauge")
        for metric in counts.keys.sorted() {
            lines.append(
                "ohe_receiver_live_quantity_last{metric_id=\"\(metric)\"} \(formatPrometheus(last[metric] ?? 0))"
            )
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func prometheusLabel(_ raw: String) -> String {
        let filtered = raw.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == ":" {
                return Character(scalar)
            }
            return "_"
        }
        let label = String(filtered)
        return label.isEmpty ? "unknown" : label
    }

    private func formatPrometheus(_ value: Double) -> String {
        if value.rounded() == value, value >= Double(Int.min), value <= Double(Int.max) {
            return String(Int(value))
        }
        return String(value)
    }

    private func isNumber(_ any: Any?) -> Bool {
        any is Int || any is Int64 || any is Double || any is NSNumber
    }

    private func doubleValue(_ any: Any?) -> Double {
        if let value = any as? Double { return value }
        if let value = any as? Int { return Double(value) }
        if let value = any as? NSNumber { return value.doubleValue }
        return 0
    }
}
