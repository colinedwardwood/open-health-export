import CoreDomain
import Foundation
import MetricCatalog

/// Live encodings that ride next to the canonical NDJSON archive (R-12).
public enum NativeSidecars {
    private struct QuantityValue: Decodable {
        let value: Double
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
                    tzDatabaseVersion: object["tzDatabaseVersion"] as? String
                )
            case "sample.quantity":
                let wireId = object["metricId"] as? String ?? ""
                let resolved = MetricCatalog.all.first { $0.wireId == wireId }?.id
                    ?? MetricID(rawValue: wireId)
                if metric == nil { metric = resolved }
                // Foundation JSONSerialization rounds some 17-digit decimals to
                // the adjacent Double on Linux. JSONDecoder uses correctly-rounded
                // binary64 conversion and preserves the canonical wire value.
                let quantity = try JSONDecoder().decode(
                    QuantityValue.self,
                    from: Data(line.utf8)
                )
                samples.append(
                    SampleRecord(
                        key: RecordKey(uuid: object["uuid"] as? String ?? ""),
                        metric: resolved,
                        start: object["start"] as? String ?? "",
                        end: object["end"] as? String ?? "",
                        timeZoneOffsetMinutes: (object["tzOffsetMinutes"] as? NSNumber)?.intValue ?? 0,
                        timeZoneSource: TimeZoneSource(
                            rawValue: object["tzSource"] as? String ?? "unknown"
                        ) ?? .unknown,
                        value: quantity.value,
                        unit: CanonicalUnit(symbol: object["unit"] as? String ?? ""),
                        observedAt: object["observedAt"] as? String ?? ""
                    )
                )
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
