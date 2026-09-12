// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation
import MetricCatalog

enum NativeCSV {
    static let spreadsheetDataRowLimit = 1_048_576
    static let quantityColumns = [
        "uuid", "metricId", "hkIdentifier", "semantics", "startUtc", "endUtc",
        "tzOffsetMinutes", "tzId", "tzSource", "value", "unit", "count",
        "sourceName", "sourceBundleId", "deviceName", "wasUserEntered", "quality",
        "observedAt", "exporterId", "batchSeq",
    ]

    static func quantityFiles(
        samples: [SampleRecord],
        envelope: WireEnvelope,
        ndjson: Data,
        rowLimit: Int = spreadsheetDataRowLimit
    ) throws -> (quantity: Data, meta: Data, fileName: String, extra: [(Data, String)]) {
        let chunks = try quantityChunks(
            samples: samples,
            envelope: envelope,
            rowLimit: rowLimit
        )
        let text = String(decoding: ndjson, as: UTF8.self)
        let lines = text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline).map(String.init)
        var headerLine = ""
        var footerLine = ""
        for line in lines {
            if line.contains("\"kind\":\"batch.header\"") { headerLine = line }
            if line.contains("\"kind\":\"batch.footer\"") { footerLine = line }
        }
        let meta = "{\"csvDropsMetadata\":true,\"footer\":\(footerLine),\"header\":\(headerLine)}\n"
        let extra = Array(chunks.dropFirst())
        return (chunks[0].quantity, Data(meta.utf8), chunks[0].fileName, extra)
    }

    static func quantityChunks(
        samples: [SampleRecord],
        envelope: WireEnvelope,
        rowLimit: Int = spreadsheetDataRowLimit
    ) throws -> [(quantity: Data, fileName: String)] {
        let limit = max(1, rowLimit)
        let sorted = samples.sorted { lhs, rhs in
            (lhs.start, lhs.key.uuid.lowercased()) < (rhs.start, rhs.key.uuid.lowercased())
        }
        let windowStart = compactDay(sorted.first?.start ?? envelope.emittedAt)
        let windowEnd = compactDay(sorted.last?.end ?? envelope.emittedAt)
        let parts = stride(from: 0, to: max(sorted.count, 1), by: limit).map { start -> ArraySlice<SampleRecord> in
            sorted[start ..< min(start + limit, sorted.count)]
        }
        let many = parts.count > 1
        return parts.enumerated().map { index, slice in
            let fileName: String
            if many {
                fileName = String(
                    format: "ohe1-quantity-\(windowStart)-\(windowEnd)-part%02d.csv",
                    index + 1
                )
            } else {
                fileName = "ohe1-quantity-\(windowStart)-\(windowEnd).csv"
            }
            var rows = [quantityColumns.joined(separator: ",")]
            for sample in slice {
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
            return (
                quantity: Data((rows.joined(separator: "\r\n") + "\r\n").utf8),
                fileName: fileName
            )
        }
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
