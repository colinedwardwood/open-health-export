// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation
import MetricCatalog

/// R-84 / wire G1: encode committed logical input with injected clocks and IDs.
public enum FrozenEncoder {
    public struct Artifacts: Equatable, Sendable {
        public var ndjson: Data
        public var json: Data
        public var prettyJSON: Data
        public var csvQuantity: Data
        public var csvMeta: Data
        public var csvFileName: String
    }

    public static func artifacts(fromLogicalInput data: Data) throws -> Artifacts {
        let samplesAndEnvelope = try decodeLogicalInput(data)
        let ndjson = try NativeWire.encode(
            samples: samplesAndEnvelope.samples,
            tombstones: [],
            metric: samplesAndEnvelope.samples.first?.metric ?? MetricCatalog.heartRate.id,
            batchID: samplesAndEnvelope.batchID,
            envelope: samplesAndEnvelope.envelope
        )
        let jsonPair = try NativeJSON.document(fromNDJSON: ndjson)
        let csv = try NativeCSV.quantityFiles(
            samples: samplesAndEnvelope.samples,
            envelope: samplesAndEnvelope.envelope,
            ndjson: ndjson
        )
        return Artifacts(
            ndjson: ndjson,
            json: jsonPair.canonical,
            prettyJSON: jsonPair.pretty,
            csvQuantity: csv.quantity,
            csvMeta: csv.meta,
            csvFileName: csv.fileName
        )
    }

    public static func nativeNDJSON(fromLogicalInput data: Data) throws -> Data {
        try artifacts(fromLogicalInput: data).ndjson
    }

    static func decodeLogicalInput(_ data: Data) throws -> (
        samples: [SampleRecord],
        batchID: BatchID,
        envelope: WireEnvelope
    ) {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WireError.utf8
        }
        let envelope = WireEnvelope(
            exporterId: object["exporterId"] as? String ?? "",
            seq: (object["seq"] as? NSNumber)?.intValue ?? 1,
            emittedAt: object["emittedAt"] as? String ?? "",
            observedAt: object["observedAt"] as? String ?? "",
            completeThrough: object["completeThrough"] as? String
        )
        let batchID = BatchID(rawValue: object["batchId"] as? String ?? "")
        let sampleObjects = object["samples"] as? [[String: Any]] ?? []
        let samples = sampleObjects.map { row -> SampleRecord in
            SampleRecord(
                key: RecordKey(uuid: row["uuid"] as? String ?? ""),
                metric: MetricID(rawValue: row["metric"] as? String ?? ""),
                start: row["start"] as? String ?? "",
                end: row["end"] as? String ?? "",
                timeZoneOffsetMinutes: (row["tzOffsetMinutes"] as? NSNumber)?.intValue ?? 0,
                timeZoneSource: TimeZoneSource(
                    rawValue: row["tzSource"] as? String ?? "unknown"
                ) ?? .unknown,
                value: (row["value"] as? NSNumber)?.doubleValue ?? 0,
                unit: CanonicalUnit(symbol: row["unit"] as? String ?? ""),
                observedAt: row["observedAt"] as? String ?? ""
            )
        }
        return (samples, batchID, envelope)
    }
}
