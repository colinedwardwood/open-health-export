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

    public static func write(fromNDJSONAt url: URL, beside ndjsonURL: URL) throws {
        var parsed = try parse(at: url)
        let encodings = ndjsonURL.deletingPathExtension().appendingPathExtension("encodings")
        try FileManager.default.createDirectory(at: encodings, withIntermediateDirectories: true)
        let csv = try NativeCSV.quantityFiles(
            samples: parsed.samples,
            envelope: parsed.envelope,
            headerLine: parsed.headerLine,
            footerLine: parsed.footerLine
        )
        try csv.quantity.write(to: encodings.appendingPathComponent(csv.fileName), options: .atomic)
        for extra in csv.extra {
            try extra.0.write(to: encodings.appendingPathComponent(extra.1), options: .atomic)
        }
        try csv.meta.write(to: encodings.appendingPathComponent("_meta.json"), options: .atomic)
        if parsed.haeEligible, let metric = parsed.metric {
            let hae = try HAEWire.encode(
                samples: parsed.samples,
                tombstones: [],
                metric: metric,
                acknowledgingLoss: HAELossAccepted()
            )
            try hae.write(to: encodings.appendingPathComponent("batch.hae.json"), options: .atomic)
        }
        parsed.samples = []
        try NativeJSON.writeDocuments(
            fromNDJSONAt: url,
            canonical: encodings.appendingPathComponent("batch.json"),
            pretty: encodings.appendingPathComponent("batch.pretty.json")
        )
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
