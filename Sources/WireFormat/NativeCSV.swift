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
        let text = String(decoding: ndjson, as: UTF8.self)
        let lines = text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline).map(String.init)
        var headerLine = ""
        var footerLine = ""
        for line in lines {
            if line.contains("\"kind\":\"batch.header\"") { headerLine = line }
            if line.contains("\"kind\":\"batch.footer\"") { footerLine = line }
        }
        return try quantityFiles(
            samples: samples,
            envelope: envelope,
            headerLine: headerLine,
            footerLine: footerLine,
            rowLimit: rowLimit
        )
    }

    static func quantityFiles(
        samples: [SampleRecord],
        envelope: WireEnvelope,
        headerLine: String,
        footerLine: String,
        rowLimit: Int = spreadsheetDataRowLimit
    ) throws -> (quantity: Data, meta: Data, fileName: String, extra: [(Data, String)]) {
        let chunks = try quantityChunks(
            samples: samples,
            envelope: envelope,
            rowLimit: rowLimit
        )
        let meta = "{\"csvDropsMetadata\":true,\"footer\":\(footerLine),\"header\":\(headerLine)}\n"
        let extra = Array(chunks.dropFirst())
        return (chunks[0].quantity, Data(meta.utf8), chunks[0].fileName, extra)
    }

    /// Writes the same files `quantityFiles` returns, streaming rows straight from the
    /// NDJSON on disk. The row count and window come from the scan, so part filenames
    /// are known before the first row is written.
    static func writeQuantityFiles(
        scan: NativeSidecars.Scan,
        readingSamplesFrom url: URL,
        into encodings: URL,
        rowLimit: Int = spreadsheetDataRowLimit
    ) throws {
        let limit = max(1, rowLimit)
        let fallback = scan.envelope.emittedAt
        let windowStart = compactDay(scan.quantityCount == 0 ? fallback : scan.firstStart)
        let windowEnd = compactDay(scan.quantityCount == 0 ? fallback : scan.lastEnd)
        let parts = (max(scan.quantityCount, 1) + limit - 1) / limit
        let many = parts > 1

        func partName(_ index: Int) -> String {
            many
                ? String(format: "ohe1-quantity-\(windowStart)-\(windowEnd)-part%02d.csv", index + 1)
                : "ohe1-quantity-\(windowStart)-\(windowEnd).csv"
        }

        let meta = "{\"csvDropsMetadata\":true,\"footer\":\(scan.footerLine),\"header\":\(scan.headerLine)}\n"
        try Data(meta.utf8).write(to: encodings.appendingPathComponent("_meta.json"), options: .atomic)

        var partIndex = 0
        var rowsInPart = 0
        var buffer = Data()
        buffer.reserveCapacity(flushBytes + 1_024)
        var handle: FileHandle?

        func closePart() throws {
            if !buffer.isEmpty, let handle {
                try handle.write(contentsOf: buffer)
            }
            buffer.removeAll(keepingCapacity: true)
            try handle?.close()
            handle = nil
        }

        func openPart() throws {
            let destination = encodings.appendingPathComponent(partName(partIndex))
            try Data().write(to: destination)
            handle = try FileHandle(forWritingTo: destination)
            rowsInPart = 0
            try appendRow(quantityColumns.joined(separator: ","))
        }

        func appendRow(_ row: String) throws {
            buffer.append(contentsOf: row.utf8)
            buffer.append(contentsOf: "\r\n".utf8)
            if buffer.count >= flushBytes, let handle {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }

        try openPart()
        try NativeSidecars.forEachQuantitySample(at: url) { sample in
            if rowsInPart == limit {
                try closePart()
                partIndex += 1
                try openPart()
            }
            try appendRow(row(for: sample, envelope: scan.envelope))
            rowsInPart += 1
        }
        try closePart()
    }

    private static let flushBytes = 64 * 1_024

    private static func row(for sample: SampleRecord, envelope: WireEnvelope) -> String {
        let decl = MetricCatalog.declaration(for: sample.metric)
        return [
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
                rows.append(row(for: sample, envelope: envelope))
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
