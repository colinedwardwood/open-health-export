// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import EnginePorts
import Foundation
import MetricCatalog
import StorageSQLite
import Testing
@testable import WireFormat

@Test func nativeJSONRejectsMalformedAndUnframedBatches() throws {
    #expect(throws: (any Error).self) {
        _ = try NativeJSON.document(fromNDJSON: Data("{\"x\":1}\n".utf8), maxBytes: 1_024)
    }
    let headerOnly = try NativeWire.encode(
        samples: [heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01")],
        tombstones: [],
        metric: MetricCatalog.heartRate.id,
        batchID: BatchID(rawValue: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01"),
        envelope: testEnvelope()
    )
    let withoutFooter = Data(
        String(decoding: headerOnly, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .filter { !$0.contains("batch.footer") }
            .joined(separator: "\n")
            .utf8
    )
    #expect(throws: WireError.utf8) {
        _ = try NativeJSON.document(fromNDJSON: withoutFooter, maxBytes: 1_024)
    }
}

@Test func nativeCSVQuotesCommasAndSplitsParts() throws {
    var sample = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa02")
    sample.source = SampleSourceIdentity(name: "Watch, Series", bundleIdentifier: "app.watch")
    sample.device = SampleDevice(name: "Watch")
    sample.wasUserEntered = true
    let quoted = try NativeCSV.quantityChunks(
        samples: [sample],
        envelope: testEnvelope()
    )
    let text = String(decoding: quoted[0].quantity, as: UTF8.self)
    #expect(text.contains("\"Watch, Series\""))
    #expect(text.contains("true"))
    let parts = try NativeCSV.quantityChunks(
        samples: [
            heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa03"),
            heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa04", start: "2024-01-02T00:00:00Z"),
        ],
        envelope: testEnvelope(),
        rowLimit: 1
    )
    #expect(parts.count == 2)
    #expect(parts[0].fileName.contains("-part01.csv"))
    let files = try NativeCSV.quantityFiles(
        samples: [
            heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa03"),
            heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa04", start: "2024-01-02T00:00:00Z"),
        ],
        envelope: testEnvelope(),
        ndjson: try NativeWire.encode(
            samples: [heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa03")],
            tombstones: [],
            metric: MetricCatalog.heartRate.id,
            batchID: BatchID(rawValue: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa03"),
            envelope: testEnvelope()
        ),
        rowLimit: 1
    )
    #expect(files.extra.count == 1)
}

@Test func nativeSidecarsWriteSplitsAndSkipHAEOnTombstones() throws {
    #expect(throws: WireError.utf8) {
        _ = try NativeSidecars.quantitySample(
            fromNDJSONLine: Data(
                """
                {"kind":"nope","metricId":"heartRate","uuid":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa07","start":"2024-01-01T00:00:00Z","end":"2024-01-01T00:00:00Z","tzOffsetMinutes":0,"tzSource":"bogus","value":60,"unit":"count/min","observedAt":"2024-01-01T00:00:00Z"}
                """.utf8
            )
        )
    }
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-sidecar-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let samples = [
        heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa05"),
        heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa06", start: "2024-01-02T00:00:00Z"),
    ]
    let ndjson = try NativeWire.encode(
        samples: samples,
        tombstones: [
            TombstoneRecord(
                key: RecordKey(uuid: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa07"),
                metric: MetricCatalog.heartRate.id
            ),
        ],
        metric: MetricCatalog.heartRate.id,
        batchID: BatchID(rawValue: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa08"),
        envelope: testEnvelope()
    )
    let url = dir.appendingPathComponent("batch.ndjson")
    try ndjson.write(to: url)
    try NativeSidecars.write(fromNDJSON: ndjson, beside: url)
    let encodings = dir.appendingPathComponent("batch.encodings")
    #expect(!FileManager.default.fileExists(atPath: encodings.appendingPathComponent("batch.hae.json").path))
}

@Test func sqliteCoversDayIndexLookupsAndUnreadableDiagnostics() async throws {
    #expect(throws: StorageError.self) {
        _ = try SQLiteStateStore(path: "/tmp")
    }
    let missing = SQLiteDiagnosticReader.read(path: "/no/such/ohe-\(UUID().uuidString).sqlite")
    #expect(missing.degraded.contains("database_unreadable"))

    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-sqlite-cov-\(UUID().uuidString).sqlite")
        .path
    let store = try SQLiteStateStore(path: path)
    let metric = MetricCatalog.heartRate.id
    let row = EmittedIndexRow(
        uuid: "11111111-1111-1111-1111-111111111112",
        metric: metric,
        day: "2024-01-01",
        digest: "aa",
        batchID: BatchID(rawValue: "b1")
    )
    try await store.transact { try $0.upsertEmittedIndex(row) }
    #expect(try await store.transact { try $0.loadEmittedIndex(metric: metric, day: "2024-01-01") } == [row])
    #expect(try await store.transact { try $0.latestEmittedDay(metric: metric) } == "2024-01-01")
    #expect(try await store.transact { try $0.loadAggregateEmitSeq(bucketKey: "missing") } == nil)
    #expect(try await store.transact { try $0.loadTypeStatus(metric: metric) } == nil)
    try await store.transact {
        try $0.upsertAnchorHold(
            AnchorHold(
                metric: metric,
                reason: .replaySuspected,
                detectedAtEpoch: 1,
                observedSamples: 9
            )
        )
    }
    let holds = try await store.transact { try $0.loadAnchorHolds() }
    #expect(holds.count == 1)
    #expect(holds[0].lastEmittedDay == nil)
    try await store.transact { try $0.removeEmittedIndex(uuid: row.uuid) }
    #expect(try await store.transact { try $0.loadEmittedIndex(uuid: row.uuid) } == nil)
}

@Test func haStateEncodesBucketBoundsAndDiscoveryRejectsEmptyIds() throws {
    #expect(throws: HADiscoveryError.badExporterId) {
        _ = try HADiscovery.sanitizeExporterId("!!!")
    }
    let encoded = try HAState.encode(
        HAStatePoint(
            value: 1,
            bucketStart: "2024-01-01T00:00:00Z",
            bucketEnd: "2024-01-02T00:00:00Z",
            timeZoneIdentifier: "UTC",
            sampleCount: 1,
            state: "ok",
            computation: "localSampleFold"
        )
    )
    let text = String(decoding: encoded, as: UTF8.self)
    #expect(text.contains("bucketStart"))
    #expect(text.contains("bucketEnd"))
}
