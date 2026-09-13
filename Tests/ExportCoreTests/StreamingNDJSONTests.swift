// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation
import MetricCatalog
import Testing
import WireFormat

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
}
