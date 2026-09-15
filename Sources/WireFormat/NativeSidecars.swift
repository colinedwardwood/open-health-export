// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation
import MetricCatalog

/// Live encodings that ride next to the canonical NDJSON archive (R-12).
public enum NativeSidecars {
    private struct QuantityLine: Decodable {
        let kind: String
        let metricId: String
        let uuid: String
        let start: String
        let end: String
        let tzOffsetMinutes: Int
        let tzSource: String
        let value: Double
        let unit: String
        let observedAt: String
    }

    private static let metricByWireId: [String: MetricID] = Dictionary(
        uniqueKeysWithValues: MetricCatalog.all.map { ($0.wireId, $0.id) }
    )

    /// Decodes one `sample.quantity` line without requiring batch framing.
    /// Callers must classify the line first; accepting structural records here would
    /// make a streaming export checker capable of silently skipping them.
    public static func quantitySample(fromNDJSONLine data: Data) throws -> SampleRecord {
        try quantitySample(fromNDJSONLine: data, decoder: JSONDecoder())
    }

    public static func quantitySample(
        fromNDJSONLine data: Data,
        decoder: JSONDecoder
    ) throws -> SampleRecord {
        // JSONDecoder uses correctly-rounded binary64 conversion. JSONSerialization
        // rounds some 17-digit decimals to the adjacent Double on Linux.
        let quantity = try decoder.decode(QuantityLine.self, from: data)
        guard quantity.kind == "sample.quantity" else {
            throw WireError.utf8
        }
        let wireId = quantity.metricId
        let resolved = metricByWireId[wireId] ?? MetricID(rawValue: wireId)
        return SampleRecord(
            key: RecordKey(uuid: quantity.uuid),
            metric: resolved,
            start: quantity.start,
            end: quantity.end,
            timeZoneOffsetMinutes: quantity.tzOffsetMinutes,
            timeZoneSource: TimeZoneSource(rawValue: quantity.tzSource) ?? .unknown,
            value: quantity.value,
            unit: CanonicalUnit(symbol: quantity.unit),
            observedAt: quantity.observedAt
        )
    }

    public static func quantitySamples(fromNDJSON data: Data) throws -> [SampleRecord] {
        try parse(data).samples
    }

    public static func write(fromNDJSON data: Data, beside ndjsonURL: URL) throws {
        let staging = ndjsonURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).ndjson")
        try data.write(to: staging, options: .withoutOverwriting)
        defer { try? FileManager.default.removeItem(at: staging) }
        try write(fromNDJSONAt: staging, beside: ndjsonURL)
    }

    /// Every sidecar is derived from the NDJSON already on disk, so none of them needs
    /// the page in memory. Re-reading the file per encoding costs IO the OS caches;
    /// holding a 10k-record page as records, CSV rows and a `CanonicalJSON` tree at the
    /// same time cost roughly 50 MiB of R-74's 100 MiB ceiling.
    public static func write(fromNDJSONAt url: URL, beside ndjsonURL: URL) throws {
        let scan = try scan(at: url)
        let encodings = ndjsonURL.deletingPathExtension().appendingPathExtension("encodings")
        try FileManager.default.createDirectory(at: encodings, withIntermediateDirectories: true)
        try NativeCSV.writeQuantityFiles(
            scan: scan,
            readingSamplesFrom: url,
            into: encodings
        )
        if scan.haeEligible, let metric = scan.metric {
            try HAEWire.write(
                readingSamplesFrom: url,
                metric: metric,
                to: encodings.appendingPathComponent("batch.hae.json"),
                acknowledgingLoss: HAELossAccepted()
            )
        }
        try NativeJSON.writeDocuments(
            fromNDJSONAt: url,
            canonical: encodings.appendingPathComponent("batch.json"),
            pretty: encodings.appendingPathComponent("batch.pretty.json")
        )
    }

    /// Batch framing plus the counts and window the sidecars need, and not one sample.
    /// The wire body is already ordered by `(start, uuid)`, so the first and last
    /// quantity lines give the CSV window without sorting anything.
    struct Scan {
        var envelope = WireEnvelope(exporterId: "", seq: 1, emittedAt: "", observedAt: "")
        var metric: MetricID?
        var quantityCount = 0
        var firstStart = ""
        var lastEnd = ""
        var headerLine = ""
        var footerLine = ""
        var sawTombstone = false

        var haeEligible: Bool { !sawTombstone && quantityCount > 0 }
    }

    static func scan(at url: URL) throws -> Scan {
        var scan = Scan()
        var sawHeader = false
        try forEachLine(at: url) { kind, line, object in
            switch kind {
            case "batch.header":
                sawHeader = true
                scan.headerLine = String(decoding: line, as: UTF8.self)
                scan.envelope = WireEnvelope(
                    exporterId: object["exporterId"] as? String ?? "",
                    seq: (object["seq"] as? NSNumber)?.intValue ?? 1,
                    emittedAt: object["emittedAt"] as? String ?? "",
                    observedAt: object["emittedAt"] as? String ?? "",
                    completeThrough: object["completeThrough"] as? String,
                    verifiedThrough: object["verifiedThrough"] as? String,
                    tzDatabaseVersion: object["tzDatabaseVersion"] as? String
                )
            case "batch.footer":
                scan.footerLine = String(decoding: line, as: UTF8.self)
            case "sample.quantity":
                let sample = try quantitySample(fromNDJSONLine: line)
                if scan.metric == nil { scan.metric = sample.metric }
                if scan.quantityCount == 0 { scan.firstStart = sample.start }
                scan.lastEnd = sample.end
                scan.quantityCount += 1
            case "tombstone":
                scan.sawTombstone = true
            default:
                break
            }
        }
        guard sawHeader else { throw WireError.utf8 }
        return scan
    }

    static func forEachQuantitySample(
        at url: URL,
        _ body: (SampleRecord) throws -> Void
    ) throws {
        try forEachLine(at: url) { kind, line, _ in
            guard kind == "sample.quantity" else { return }
            try body(try quantitySample(fromNDJSONLine: line))
        }
    }

    private static func forEachLine(
        at url: URL,
        _ body: (String, Data, [String: Any]) throws -> Void
    ) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var reader = NDJSONLineReader(handle: handle)
        while let line = try reader.next() {
            guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let kind = object["kind"] as? String
            else {
                throw WireError.utf8
            }
            try body(kind, line, object)
        }
    }

    static func parse(_ data: Data) throws -> (
        envelope: WireEnvelope,
        samples: [SampleRecord],
        metric: MetricID?,
        haeEligible: Bool,
        headerLine: String,
        footerLine: String
    ) {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohe-sidecar-parse-\(UUID().uuidString).ndjson")
        try data.write(to: staging, options: .withoutOverwriting)
        defer { try? FileManager.default.removeItem(at: staging) }
        return try parse(at: staging)
    }

    static func parse(at url: URL) throws -> (
        envelope: WireEnvelope,
        samples: [SampleRecord],
        metric: MetricID?,
        haeEligible: Bool,
        headerLine: String,
        footerLine: String
    ) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var reader = NDJSONLineReader(handle: handle)
        var envelope = WireEnvelope(exporterId: "", seq: 1, emittedAt: "", observedAt: "")
        var samples: [SampleRecord] = []
        var metric: MetricID?
        var tombstones = false
        var sawHeader = false
        var headerLine = ""
        var footerLine = ""
        while let line = try reader.next() {
            guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let kind = object["kind"] as? String
            else {
                throw WireError.utf8
            }
            switch kind {
            case "batch.header":
                sawHeader = true
                headerLine = String(decoding: line, as: UTF8.self)
                envelope = WireEnvelope(
                    exporterId: object["exporterId"] as? String ?? "",
                    seq: (object["seq"] as? NSNumber)?.intValue ?? 1,
                    emittedAt: object["emittedAt"] as? String ?? "",
                    observedAt: object["emittedAt"] as? String ?? "",
                    completeThrough: object["completeThrough"] as? String,
                    verifiedThrough: object["verifiedThrough"] as? String,
                    tzDatabaseVersion: object["tzDatabaseVersion"] as? String
                )
            case "batch.footer":
                footerLine = String(decoding: line, as: UTF8.self)
            case "sample.quantity":
                let sample = try quantitySample(fromNDJSONLine: line)
                let resolved = sample.metric
                if metric == nil { metric = resolved }
                samples.append(sample)
            case "tombstone":
                tombstones = true
            default:
                break
            }
        }
        guard sawHeader else { throw WireError.utf8 }
        return (envelope, samples, metric, !tombstones && !samples.isEmpty, headerLine, footerLine)
    }
}
