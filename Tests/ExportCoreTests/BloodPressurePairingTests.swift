// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CorrectnessEngine
import CoreDomain
import DestinationTrust
import EnginePorts
import Foundation
import MetricCatalog
import SinkLocalFile
import Testing
import TestSupport
import WireFormat

@Test func bloodPressurePairingStaysOffTheComponentCensusAndCountsOnTheWire() async throws {
    let metric = MetricCatalog.bloodPressureSystolic.id
    let sample = SampleRecord(
        key: RecordKey(uuid: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1"),
        metric: metric,
        start: "2026-09-08T06:00:00Z",
        end: "2026-09-08T06:00:00Z",
        timeZoneOffsetMinutes: 0,
        timeZoneSource: .unknown,
        value: 120,
        unit: CanonicalUnit(symbol: "mmHg"),
        observedAt: "2026-09-08T06:01:00Z"
    )
    let pairing = CorrelationRecord(
        key: RecordKey(uuid: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1"),
        metric: MetricID(rawValue: "blood_pressure"),
        healthKitIdentifier: "HKCorrelationTypeIdentifierBloodPressure",
        correlationType: "bloodPressure",
        start: "2026-09-08T06:00:00Z",
        end: "2026-09-08T06:00:00Z",
        timeZoneOffsetMinutes: 0,
        timeZoneSource: .unknown,
        components: [
            CorrelationComponent(
                key: sample.key,
                metric: MetricID(rawValue: "blood_pressure_systolic"),
                healthKitIdentifier: "HKQuantityTypeIdentifierBloodPressureSystolic",
                value: 120,
                unit: CanonicalUnit(symbol: "mmHg")
            ),
            CorrelationComponent(
                key: RecordKey(uuid: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2"),
                metric: MetricID(rawValue: "blood_pressure_diastolic"),
                healthKitIdentifier: "HKQuantityTypeIdentifierBloodPressureDiastolic",
                value: 80,
                unit: CanonicalUnit(symbol: "mmHg")
            ),
        ],
        observedAt: "2026-09-08T06:01:00Z"
    )
    let page = SamplePage(
        samples: [sample],
        correlations: [pairing],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0x42]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    #expect(page.censusKeys.map(\.uuid) == [sample.key.uuid])
    #expect(page.encodedRecordCount == 2)

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-bp-pairing-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let destinationURL = root.appendingPathComponent("destination")
    try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
    let store = MemoryStateStore()
    let outcome = try await ExportRun(
        source: FixtureSource(pages: [page]),
        destination: .testing(LocalFileSink(directory: destinationURL)),
        store: store,
        metric: metric,
        scratchDirectory: root.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    ).run()
    #expect(outcome.kind == .success)
    let census = try await store.transact { try $0.loadCensus(metric: metric, day: "2026-09-08") }
    #expect(census?.sampleCount == 1)
    #expect(try await store.transact { try $0.loadEmittedIndex(uuid: sample.key.uuid) } != nil)
    #expect(try await store.transact { try $0.loadEmittedIndex(uuid: pairing.key.uuid) } == nil)
    let files = try FileManager.default.contentsOfDirectory(atPath: destinationURL.path)
        .filter { $0.hasSuffix(".ndjson") }
    let payload = try String(
        contentsOf: destinationURL.appendingPathComponent(files[0]),
        encoding: .utf8
    )
    #expect(payload.contains("\"kind\":\"sample.quantity\""))
    #expect(payload.contains("\"kind\":\"sample.correlation\""))
    #expect(payload.contains("\"correlationType\":\"bloodPressure\""))
}
