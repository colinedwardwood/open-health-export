import Foundation

/// G3/G4/R-115: upsert-by-UUID, tombstones delete, unknown fields ignored.
public struct ReferenceReceiver: Sendable, Equatable {
    public var quantities: [String: Double]
    public var tombstones: Set<String>
    public var ingested: Int

    public init(quantities: [String: Double] = [:], tombstones: Set<String> = [], ingested: Int = 0) {
        self.quantities = quantities
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
        switch kind {
        case "sample.quantity":
            guard let uuid = object["uuid"] as? String, isNumber(object["value"]) else {
                throw JSONSchemaError.missingRequired("uuid")
            }
            quantities[uuid] = doubleValue(object["value"])
            tombstones.remove(uuid)
        case "tombstone":
            guard let uuid = object["uuid"] as? String else {
                throw JSONSchemaError.missingRequired("uuid")
            }
            quantities.removeValue(forKey: uuid)
            tombstones.insert(uuid)
        default:
            break
        }
    }

    public func expectedState() -> [String: Any] {
        [
            "quantities": quantities.keys.sorted().reduce(into: [String: Double]()) { $0[$1] = quantities[$1] },
            "tombstones": tombstones.sorted(),
            "ingested": ingested,
        ]
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
