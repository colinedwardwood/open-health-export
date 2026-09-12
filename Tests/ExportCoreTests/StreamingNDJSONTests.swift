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

    let decoded = try NativeSidecars.quantitySample(fromNDJSONLine: Data(line.utf8))
    #expect(decoded.key == sample.key)
    #expect(decoded.metric == sample.metric)
    #expect(decoded.value == sample.value)
}
