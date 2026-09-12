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

    /// Decodes one `sample.quantity` line without requiring batch framing.
    /// Callers must classify the line first; accepting structural records here would
    /// make a streaming export checker capable of silently skipping them.
    public static func quantitySample(fromNDJSONLine data: Data) throws -> SampleRecord {
        // JSONDecoder uses correctly-rounded binary64 conversion. JSONSerialization
        // rounds some 17-digit decimals to the adjacent Double on Linux.
        let quantity = try JSONDecoder().decode(QuantityLine.self, from: data)
        guard quantity.kind == "sample.quantity" else {
            throw WireError.utf8
        }
        let wireId = quantity.metricId
        let resolved = MetricCatalog.all.first { $0.wireId == wireId }?.id
            ?? MetricID(rawValue: wireId)
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
        let parsed = try parse(data)
        let jsonPair = try NativeJSON.document(fromNDJSON: data)
        let encodings = ndjsonURL.deletingPathExtension().appendingPathExtension("encodings")
        try FileManager.default.createDirectory(at: encodings, withIntermediateDirectories: true)
        try jsonPair.canonical.write(
            to: encodings.appendingPathComponent("batch.json"),
            options: .atomic
        )
        try jsonPair.pretty.write(
            to: encodings.appendingPathComponent("batch.pretty.json"),
            options: .atomic
        )
        let csv = try NativeCSV.quantityFiles(
            samples: parsed.samples,
            envelope: parsed.envelope,
            ndjson: data
        )
        try csv.quantity.write(to: encodings.appendingPathComponent(csv.fileName), options: .atomic)
        for extra in csv.extra {
            try extra.0.write(to: encodings.appendingPathComponent(extra.1), options: .atomic)
        }
        try csv.meta.write(to: encodings.appendingPathComponent("_meta.json"), options: .atomic)
        guard parsed.haeEligible, let metric = parsed.metric else { return }
        let hae = try HAEWire.encode(
            samples: parsed.samples,
            tombstones: [],
            metric: metric,
            acknowledgingLoss: HAELossAccepted()
        )
        try hae.write(to: encodings.appendingPathComponent("batch.hae.json"), options: .atomic)
    }

    static func parse(_ data: Data) throws -> (
        envelope: WireEnvelope,
        samples: [SampleRecord],
        metric: MetricID?,
        haeEligible: Bool
    ) {
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            .map(String.init)
        var envelope = WireEnvelope(exporterId: "", seq: 1, emittedAt: "", observedAt: "")
        var samples: [SampleRecord] = []
        var metric: MetricID?
        var tombstones = false
        var sawHeader = false
        for line in lines {
            guard let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let kind = object["kind"] as? String
            else {
                throw WireError.utf8
            }
            switch kind {
            case "batch.header":
                sawHeader = true
                envelope = WireEnvelope(
                    exporterId: object["exporterId"] as? String ?? "",
                    seq: (object["seq"] as? NSNumber)?.intValue ?? 1,
                    emittedAt: object["emittedAt"] as? String ?? "",
                    observedAt: object["emittedAt"] as? String ?? "",
                    completeThrough: object["completeThrough"] as? String,
                    verifiedThrough: object["verifiedThrough"] as? String,
                    tzDatabaseVersion: object["tzDatabaseVersion"] as? String
                )
            case "sample.quantity":
                let sample = try quantitySample(fromNDJSONLine: Data(line.utf8))
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
        return (envelope, samples, metric, !tombstones && !samples.isEmpty)
    }
}
