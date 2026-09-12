// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CorrectnessEngine
import DestinationTrust
import EnginePorts
import Foundation
import MetricCatalog
import SinkLocalFile
import TestSupport
import Testing

/// R-08 / FIX-M05: container census survives restore; HealthKit sample UUIDs do not.
@Test func restoreFromBackupNewUUIDsAreReemittedWithoutSkipOrDuplicateState() async throws {
    let metric = MetricCatalog.heartRate.id
    var historical = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    historical.start = "2023-12-01T10:00:00Z"
    historical.end = historical.start
    var recent = heartSample("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
    recent.start = "2024-01-01T10:00:00Z"
    recent.end = recent.start
    var restoredHistorical = historical
    restoredHistorical.key = RecordKey(uuid: "cccccccc-cccc-cccc-cccc-cccccccccccc")
    var restoredRecent = recent
    restoredRecent.key = RecordKey(uuid: "dddddddd-dddd-dddd-dddd-dddddddddddd")

    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-restore-m05-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dest) }
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    let store = MemoryStateStore()
    let first = ExportRun(
        source: FixtureSource(
            pages: [
                SamplePage(
                    samples: [historical, recent],
                    tombstones: [],
                    metric: metric,
                    anchorBlob: Data([0xA0]),
                    observedThrough: Date(timeIntervalSince1970: 0)
                )
            ]
        ),
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    )
    _ = try await first.run()
    let cursor = try store.transaction.loadCursor(metric: metric)
    #expect(try store.transaction.loadEmittedIndex(uuid: historical.key.uuid) != nil)
    #expect(try store.transaction.loadEmittedIndex(uuid: recent.key.uuid) != nil)
    #expect(try store.transaction.loadCensus(metric: metric, day: "2023-12-01")?.sampleCount == 1)
    #expect(try store.transaction.loadCensus(metric: metric, day: "2024-01-01")?.sampleCount == 1)

    let restored = FixtureDays(
        byDay: [
            "2023-12-01": [restoredHistorical],
            "2024-01-01": [restoredRecent],
        ]
    )

    // Equal counts with new UUIDs must not classify as identical (the silent skip).
    let recentCensus = try #require(
        try store.transaction.loadCensus(metric: metric, day: "2024-01-01")
    )
    #expect(
        ReconcileCompare.compare(
            stored: recentCensus,
            observed: ReconcileCompare.fold(uuids: [restoredRecent.key.uuid])
        ) == .digestMismatch
    )

    // Trailing 7 days alone would be the "half a re-export": recent repaired, history skipped.
    let trailing = try await ReconcileSweep(
        observations: restored,
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch-trailing"),
        envelope: testEnvelope()
    ).run(throughDay: "2024-01-01")
    #expect(trailing.kind == .success)
    #expect(try store.transaction.loadCursor(metric: metric) == cursor)
    #expect(try store.transaction.loadEmittedIndex(uuid: restoredRecent.key.uuid) != nil)
    #expect(try store.transaction.loadEmittedIndex(uuid: recent.key.uuid) == nil)
    #expect(try store.transaction.loadEmittedIndex(uuid: historical.key.uuid) != nil)
    #expect(try store.transaction.loadEmittedIndex(uuid: restoredHistorical.key.uuid) == nil)
    #expect(try store.transaction.loadCensus(metric: metric, day: "2024-01-01")?.sampleCount == 1)
    #expect(try store.transaction.loadCensus(metric: metric, day: "2023-12-01")?.sampleCount == 1)

    let full = try await ReconcileSweep(
        observations: restored,
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch-full"),
        envelope: testEnvelope()
    ).runFullHistory(throughDay: "2024-01-01")
    #expect(full.kind == .success)
    #expect(try store.transaction.loadCursor(metric: metric) == cursor)
    #expect(try store.transaction.loadEmittedIndex(uuid: restoredHistorical.key.uuid) != nil)
    #expect(try store.transaction.loadEmittedIndex(uuid: historical.key.uuid) == nil)
    #expect(try store.transaction.loadEmittedIndex(uuid: restoredRecent.key.uuid) != nil)
    #expect(try store.transaction.loadEmittedIndex(uuid: recent.key.uuid) == nil)
    #expect(try store.transaction.loadCensus(metric: metric, day: "2023-12-01")?.sampleCount == 1)
    #expect(try store.transaction.loadCensus(metric: metric, day: "2024-01-01")?.sampleCount == 1)

    let repairPayloads = try ndjsonFiles(in: dest)
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .filter {
            $0.contains("\"reason\":\"reconcile\"") || $0.contains("\"reason\":\"full_reconcile\"")
        }
        .joined()
    #expect(kinds(in: repairPayloads, uuid: restoredRecent.key.uuid) == ["sample.quantity"])
    #expect(kinds(in: repairPayloads, uuid: restoredHistorical.key.uuid) == ["sample.quantity"])
    #expect(kinds(in: repairPayloads, uuid: recent.key.uuid) == ["tombstone"])
    #expect(kinds(in: repairPayloads, uuid: historical.key.uuid) == ["tombstone"])

    let again = try await ReconcileSweep(
        observations: restored,
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch-again"),
        envelope: testEnvelope()
    ).runFullHistory(throughDay: "2024-01-01")
    #expect(again.kind == .successNothingDue)
    #expect(try store.transaction.loadCursor(metric: metric) == cursor)
}

private func ndjsonFiles(in directory: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "ndjson" }
}

private func kinds(in payload: String, uuid: String) -> [String] {
    payload.split(whereSeparator: \.isNewline).compactMap { line in
        let text = String(line)
        guard text.contains("\"uuid\":\"\(uuid)\"") else { return nil }
        if text.contains("\"kind\":\"tombstone\"") { return "tombstone" }
        if text.contains("\"kind\":\"sample.quantity\"") { return "sample.quantity" }
        return nil
    }.sorted()
}
