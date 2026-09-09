import Foundation

/// G3/G4/R-115: upsert-by-UUID, tombstones delete, unknown fields ignored.
public struct ReferenceReceiver: Sendable, Equatable {
    public var quantities: [String: Double]
    public var categories: [String: Int]
    public var structuralRecords: [String: String]
    public var tombstones: Set<String>
    public var ingested: Int

    public init(
        quantities: [String: Double] = [:],
        categories: [String: Int] = [:],
        structuralRecords: [String: String] = [:],
        tombstones: Set<String> = [],
        ingested: Int = 0
    ) {
        self.quantities = quantities
        self.categories = categories
        self.structuralRecords = structuralRecords
        self.tombstones = tombstones
        self.ingested = ingested
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
            categories.removeValue(forKey: uuid)
            tombstones.remove(uuid)
        case "tombstone":
            guard let uuid = object["uuid"] as? String else {
                throw JSONSchemaError.missingRequired("uuid")
            }
            quantities.removeValue(forKey: uuid)
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
