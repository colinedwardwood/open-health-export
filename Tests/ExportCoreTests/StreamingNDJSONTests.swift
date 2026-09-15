// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation
import MetricCatalog
import Testing
@testable import WireFormat

@Test func ndjsonLineReaderStreamsAcrossChunkBoundariesAndAcceptsFinalLine() throws {
    let pipe = Pipe()
    try pipe.fileHandleForWriting.write(contentsOf: Data("one\r\ntwo\nthree".utf8))
    try pipe.fileHandleForWriting.close()
    var reader = NDJSONLineReader(handle: pipe.fileHandleForReading, chunkSize: 2)

    #expect(try reader.next() == Data("one".utf8))
    #expect(try reader.next() == Data("two".utf8))
    #expect(try reader.next() == Data("three".utf8))
    #expect(try reader.next() == nil)
}

@Test func ndjsonLineReaderDropsConsumedPrefixInBulk() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-ndjson-bulk-\(UUID().uuidString)")
    let lines = (0..<8_000).map { "record-\($0)" }
    try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var reader = NDJSONLineReader(handle: handle, chunkSize: 32)
    for expected in lines {
        #expect(try reader.next() == Data(expected.utf8))
    }
    #expect(try reader.next() == nil)
}

@Test func ndjsonLineReaderRejectsAnUnboundedRecord() throws {
    let pipe = Pipe()
    try pipe.fileHandleForWriting.write(contentsOf: Data("12345\n".utf8))
    try pipe.fileHandleForWriting.close()
    var reader = NDJSONLineReader(
        handle: pipe.fileHandleForReading,
        chunkSize: 2,
        maximumLineBytes: 4
    )

    #expect(throws: NDJSONLineReaderError.lineTooLong(maximumBytes: 4)) {
        try reader.next()
    }
}

@Test func quantityLineDecoderNeedsNoBatchAndPreservesBinary64Value() throws {
    let sample = SampleRecord(
        key: RecordKey(uuid: "82000000-0000-4000-8000-000000000001"),
        metric: MetricCatalog.heartRate.id,
        start: "2026-09-11T00:00:00Z",
        end: "2026-09-11T00:00:00Z",
        timeZoneOffsetMinutes: 0,
        timeZoneSource: .unknown,
        value: 9_007_199_254_740_991,
        unit: CanonicalUnit(symbol: "count/min"),
        observedAt: "2026-09-11T00:00:00Z"
    )
    let line = try NativeWire.encode(
        sample,
        envelope: WireEnvelope(
            exporterId: "00000000-0000-4000-8000-000000000082",
            seq: 1,
            emittedAt: sample.observedAt,
            observedAt: sample.observedAt
        )
    )

    let payload = Data(line.utf8)
    let decoder = JSONDecoder()
    let decoded = try NativeSidecars.quantitySample(fromNDJSONLine: payload, decoder: decoder)
    #expect(decoded.key == sample.key)
    #expect(decoded.metric == sample.metric)
    #expect(decoded.value == sample.value)
    #expect(NDJSONFieldScan.unescapedString(named: "kind", in: payload) == "sample.quantity")
    #expect(NDJSONFieldScan.unescapedString(named: "metricId", in: payload) == "heart_rate")
}

@Test func ndjsonFieldScanRefusesEscapedValuesSoCallersFallBack() {
    let line = Data(#"{"kind":"sample.quantity","note":"say \"hi\""}"#.utf8)
    #expect(NDJSONFieldScan.unescapedString(named: "kind", in: line) == "sample.quantity")
    #expect(NDJSONFieldScan.unescapedString(named: "note", in: line) == nil)
    #expect(NDJSONFieldScan.unescapedString(named: "kind", in: Data("{}".utf8)) == nil)
    #expect(NDJSONFieldScan.unescapedString(named: "kind", in: Data(#"{"kind":"open"#.utf8)) == nil)
}

@Test func ndjsonDataRecordCountsSkipFramingAndHonorCRLF() throws {
    let sample = SampleRecord(
        key: RecordKey(uuid: "82000000-0000-4000-8000-000000000002"),
        metric: MetricCatalog.heartRate.id,
        start: "2026-09-11T00:00:00Z",
        end: "2026-09-11T00:00:00Z",
        timeZoneOffsetMinutes: 0,
        timeZoneSource: .unknown,
        value: 72,
        unit: CanonicalUnit(symbol: "count/min"),
        observedAt: "2026-09-11T00:00:00Z"
    )
    let batch = try NativeWire.encode(
        samples: [sample],
        tombstones: [],
        metric: sample.metric,
        batchID: BatchID(rawValue: "82000000-0000-4000-8000-000000000003"),
        envelope: WireEnvelope(
            exporterId: "00000000-0000-4000-8000-000000000082",
            seq: 1,
            emittedAt: sample.observedAt,
            observedAt: sample.observedAt
        )
    )
    #expect(NativeWire.countQuantityRecords(in: batch) == 1)
    #expect(NativeWire.countRecords(in: batch) == 1)
    #expect(NativeWire.volumeReceiptCounts(in: batch).quantityRecords == 1)
    #expect(NativeWire.volumeReceiptCounts(in: batch).acceptedRecords == 1)
    let crlf = Data(
        String(decoding: batch, as: UTF8.self)
            .replacingOccurrences(of: "\n", with: "\r\n")
            .utf8
    )
    #expect(NativeWire.countQuantityRecords(in: crlf) == 1)
    #expect(NativeWire.countRecords(in: crlf) == 1)
    #expect(NativeWire.countRecords(in: Data("\n\n".utf8)) == 0)
}

@Test func compiledSchemaWithoutOneOfAndUnknownKindsStayHonest() throws {
    let direct: [String: Any] = [
        "type": "object",
        "required": ["kind"],
        "properties": ["kind": ["type": "string"]],
    ]
    try WireJSONSchema.validate(
        instance: ["kind": "x"],
        compiled: WireJSONSchema.compile(direct)
    )
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let schema = try WireJSONSchema.load(
        Data(contentsOf: root.appendingPathComponent("spec/v1.0.0/schema/ohe.wire.1.json"))
    )
    #expect(throws: JSONSchemaError.noOneOfMatch) {
        try WireJSONSchema.validate(
            instance: ["kind": "not.a.record"],
            compiled: WireJSONSchema.compile(schema)
        )
    }
    try WireJSONSchema.validateNDJSON(Data("\n\r\n".utf8), schema: schema)
}

@Test func nativeWireHeaderTypesIncludeOffMetricSamples() throws {
    var steps = heartSample("00000000-0000-0000-0000-000000000002")
    steps.metric = MetricID(rawValue: "stepCount")
    let data = try NativeWire.encode(
        samples: [
            heartSample("00000000-0000-0000-0000-000000000001"),
            steps,
        ],
        tombstones: [],
        metric: MetricID(rawValue: "heartRate"),
        batchID: BatchID(rawValue: "0192f3c1-0000-0000-0000-0000000000aa"),
        envelope: testEnvelope()
    )
    let header = String(decoding: data, as: UTF8.self)
        .split(whereSeparator: \.isNewline)
        .first
        .map(String.init) ?? ""
    #expect(header.contains("\"heart_rate\""))
    #expect(header.contains("\"step_count\""))
}

@Test func volumeReceiptCountsFromFileMatchInMemory() throws {
    let sample = SampleRecord(
        key: RecordKey(uuid: "82000000-0000-4000-8000-000000000004"),
        metric: MetricCatalog.heartRate.id,
        start: "2026-09-11T00:00:00Z",
        end: "2026-09-11T00:00:00Z",
        timeZoneOffsetMinutes: 0,
        timeZoneSource: .unknown,
        value: 72,
        unit: CanonicalUnit(symbol: "count/min"),
        observedAt: "2026-09-11T00:00:00Z"
    )
    let batch = try NativeWire.encode(
        samples: [sample],
        tombstones: [],
        metric: sample.metric,
        batchID: BatchID(rawValue: "82000000-0000-4000-8000-000000000005"),
        envelope: WireEnvelope(
            exporterId: "00000000-0000-4000-8000-000000000082",
            seq: 1,
            emittedAt: sample.observedAt,
            observedAt: sample.observedAt
        )
    )
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-receipt-\(UUID().uuidString).ndjson")
    try batch.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let fromFile = try NativeWire.volumeReceiptCounts(at: url)
    let fromMemory = NativeWire.volumeReceiptCounts(in: batch)
    #expect(fromFile.quantityRecords == fromMemory.quantityRecords)
    #expect(fromFile.acceptedRecords == fromMemory.acceptedRecords)
    #expect(try NativeWire.countRecords(at: url) == NativeWire.countRecords(in: batch))
    #expect(try NativeWire.payloadIsDemo(at: url) == NativeWire.payloadIsDemo(batch))
}

@Test func streamedJSONSidecarsMatchTheInMemoryDocument() throws {
    let sample = SampleRecord(
        key: RecordKey(uuid: "82000000-0000-4000-8000-000000000006"),
        metric: MetricCatalog.heartRate.id,
        start: "2026-09-11T00:00:00Z",
        end: "2026-09-11T00:00:00Z",
        timeZoneOffsetMinutes: 0,
        timeZoneSource: .unknown,
        value: 64,
        unit: CanonicalUnit(symbol: "count/min"),
        observedAt: "2026-09-11T00:00:00Z"
    )
    let batch = try NativeWire.encode(
        samples: [sample],
        tombstones: [],
        metric: sample.metric,
        batchID: BatchID(rawValue: "82000000-0000-4000-8000-000000000007"),
        envelope: WireEnvelope(
            exporterId: "00000000-0000-4000-8000-000000000082",
            seq: 1,
            emittedAt: sample.observedAt,
            observedAt: sample.observedAt
        )
    )
    let expected = try NativeJSON.document(fromNDJSON: batch)
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-json-stream-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let canonical = dir.appendingPathComponent("batch.json")
    let pretty = dir.appendingPathComponent("batch.pretty.json")
    let source = dir.appendingPathComponent("batch.ndjson")
    try batch.write(to: source)
    try NativeJSON.writeDocuments(fromNDJSONAt: source, canonical: canonical, pretty: pretty)
    #expect(try Data(contentsOf: canonical) == expected.canonical)
    #expect(try Data(contentsOf: pretty) == expected.pretty)
}
