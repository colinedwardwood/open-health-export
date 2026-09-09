import CoreDomain
import Foundation
import MetricCatalog

enum NativeCSV {
    static let quantityColumns = [
        "uuid", "metricId", "hkIdentifier", "semantics", "startUtc", "endUtc",
        "tzOffsetMinutes", "tzId", "tzSource", "value", "unit", "count",
        "sourceName", "sourceBundleId", "deviceName", "wasUserEntered", "quality",
        "observedAt", "exporterId", "batchSeq",
    ]

    static func quantityFiles(
        samples: [SampleRecord],
        envelope: WireEnvelope,
        ndjson: Data
    ) throws -> (quantity: Data, meta: Data, fileName: String) {
        let sorted = samples.sorted { lhs, rhs in
            (lhs.start, lhs.key.uuid.lowercased()) < (rhs.start, rhs.key.uuid.lowercased())
        }
        let windowStart = compactDay(sorted.first?.start ?? envelope.emittedAt)
        let windowEnd = compactDay(sorted.last?.end ?? envelope.emittedAt)
        let fileName = "ohe1-quantity-\(windowStart)-\(windowEnd).csv"
        var rows = [quantityColumns.joined(separator: ",")]
        for sample in sorted {
            let decl = MetricCatalog.declaration(for: sample.metric)
            rows.append(
                [
                    field(sample.key.uuid.lowercased()),
                    field(decl?.wireId ?? sample.metric.rawValue),
                    field(decl?.hkIdentifier ?? sample.metric.rawValue),
                    field(decl == nil ? "unmapped" : "curated"),
                    field(sample.start),
                    field(sample.end),
                    field(String(sample.timeZoneOffsetMinutes)),
                    field(""),
                    field(sample.timeZoneSource.rawValue),
                    field(csvNumber(sample.value)),
                    field(decl?.wireUnit ?? sample.unit.symbol),
                    field(""),
                    field(sample.source?.name ?? ""),
                    field(sample.source?.bundleIdentifier ?? ""),
                    field(sample.device?.name ?? ""),
                    field(sample.wasUserEntered.map { $0 ? "true" : "false" } ?? ""),
                    field(""),
                    field(sample.observedAt),
                    field(envelope.exporterId),
                    field(String(envelope.seq)),
                ].joined(separator: ",")
            )
        }
        let quantity = Data((rows.joined(separator: "\r\n") + "\r\n").utf8)
        let parsed = try NativeJSON.document(fromNDJSON: ndjson)
        let wrapper = try JSONSerialization.jsonObject(with: parsed.canonical) as? [String: Any] ?? [:]
        let meta = try CanonicalJSON.object([
            "csvDropsMetadata": .bool(true),
            "footer": try CanonicalJSON.parse(wrapper["footer"] ?? NSNull()),
            "header": try CanonicalJSON.parse(wrapper["header"] ?? NSNull()),
        ]).serialized() + "\n"
        return (quantity, Data(meta.utf8), fileName)
    }

    private static func compactDay(_ rfc3339: String) -> String {
        String(rfc3339.prefix(10)).replacingOccurrences(of: "-", with: "")
    }

    private static func field(_ value: String) -> String {
        if value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func csvNumber(_ value: Double) -> String {
        (try? CanonicalJSON.number(value).serialized()) ?? "0"
    }
}
