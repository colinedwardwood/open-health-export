// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import CoreDomain
import DestinationTrust
import EnginePorts
import Foundation
import MetricCatalog
import SinkLocalFile
import TestSupport
import Testing
import WireFormat
@testable import CorrectnessEngine

/// #168: category types (Sleep, Mindful minutes) are read a day at a time, so a daily
/// total exists for Mindful minutes and a reconcile can rebuild a missed sample.

private func category(
    _ uuid: String,
    metric: MetricID,
    start: String,
    minutes: Double,
    name: String = "raw_0"
) -> CategoryRecord {
    CategoryRecord(
        key: RecordKey(uuid: uuid),
        metric: metric,
        healthKitIdentifier: "HKCategoryTypeIdentifier",
        start: start,
        end: start,
        timeZoneOffsetMinutes: 0,
        timeZoneSource: .unknown,
        categoryValue: 0,
        categoryName: name,
        durationSeconds: minutes * 60,
        observedAt: "2024-01-01T23:00:00Z"
    )
}

private let mindful = MetricCatalog.mindfulSession.id
private let sleep = MetricCatalog.sleepAnalysis.id
private let sessionA = "c1000000-0000-4000-8000-00000000000a"
private let sessionB = "c1000000-0000-4000-8000-00000000000b"

private func scratch() throws -> (root: URL, destination: URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-category-day-\(UUID().uuidString)")
    let destination = root.appendingPathComponent("destination")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    return (root, destination)
}

private func delivered(_ directory: URL) throws -> String {
    try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "ndjson" }
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .joined()
}

private func sweep(
    metric: MetricID,
    days: [String: [CategoryRecord]],
    store: MemoryStateStore,
    root: URL,
    destination: URL
) async throws -> RunOutcome {
    try await ReconcileSweep(
        observations: FixtureDays(categoriesByDay: days),
        destination: .testing(LocalFileSink(directory: destination)),
        store: store,
        metric: metric,
        scratchDirectory: root.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    ).run(throughDay: "2024-01-01")
}

@Test func mindfulDurationsFoldToMinutesAndSleepHasNoDailyTotal() {
    let sessions = [
        category(sessionA, metric: mindful, start: "2024-01-01T08:00:00Z", minutes: 10),
        category(sessionB, metric: mindful, start: "2024-01-01T20:00:00Z", minutes: 5),
    ]
    let samples = CategoryDayFold.durationSamples(sessions, metric: mindful)
    #expect(samples.map(\.value) == [10, 5])
    #expect(samples.allSatisfy { $0.unit == MetricCatalog.mindfulSession.canonicalUnit })
    let fold = AggregateFold.foldDay(metric: mindful, day: "2024-01-01", samples: samples)
    #expect(fold.value == 15)
    #expect(fold.sampleCount == 2)
    #expect(fold.statistic == .sum)

    let stages = [
        category(sessionA, metric: sleep, start: "2024-01-01T22:00:00Z", minutes: 90, name: "asleepCore"),
        category(sessionB, metric: sleep, start: "2024-01-01T23:30:00Z", minutes: 30, name: "asleepREM"),
        category("c1000000-0000-4000-8000-00000000000c", metric: sleep, start: "2024-01-02T01:00:00Z", minutes: 60, name: "asleepCore"),
    ]
    #expect(CategoryDayFold.durationSamples(stages, metric: sleep).isEmpty)
    #expect(CategoryDayFold.minutesByStage(stages) == ["asleepCore": 150, "asleepREM": 30])
}

@Test func fixtureDaysReadsCategoriesByDayAndReportsTheirRange() async throws {
    let days = FixtureDays(categoriesByDay: [
        "2024-01-03": [category(sessionA, metric: mindful, start: "2024-01-03T08:00:00Z", minutes: 1)],
        "2024-01-01": [category(sessionB, metric: mindful, start: "2024-01-01T08:00:00Z", minutes: 1)],
    ])
    #expect(try await days.categories(metric: mindful, day: "2024-01-03").count == 1)
    #expect(try await days.categories(metric: sleep, day: "2024-01-03").isEmpty)
    #expect(try await days.availableDayRange(metric: mindful) == "2024-01-01" ... "2024-01-03")
}

@Test func mindfulExportProducesADailyDurationTotal() async throws {
    let first = category(sessionA, metric: mindful, start: "2024-01-01T08:00:00Z", minutes: 10)
    let second = category(sessionB, metric: mindful, start: "2024-01-01T20:00:00Z", minutes: 5)
    let (root, destination) = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    // The page carries only the new session; the day reader supplies the rest of the day.
    let outcome = try await ExportRun(
        source: FixtureSource(pages: [
            SamplePage(
                samples: [],
                categories: [second],
                tombstones: [],
                metric: mindful,
                anchorBlob: Data([0xB1]),
                observedThrough: Date(timeIntervalSince1970: 0)
            ),
        ]),
        destination: .testing(LocalFileSink(directory: destination)),
        store: MemoryStateStore(),
        metric: mindful,
        scratchDirectory: root.appendingPathComponent("scratch"),
        envelope: testEnvelope(),
        observations: FixtureDays(categoriesByDay: ["2024-01-01": [first, second]])
    ).run()
    #expect(outcome.kind == .success)
    let payload = try delivered(destination)
    #expect(payload.contains("\"kind\":\"aggregate\""))
    #expect(payload.contains("\"statistic\":\"sum\""))
    #expect(payload.contains("\"value\":15"))
    #expect(payload.contains("\"sampleCount\":2"))
    #expect(payload.contains("\"unit\":\"min\""))
}

@Test func reconcileRepairsALateMindfulSessionAndItsDailyTotal() async throws {
    let first = category(sessionA, metric: mindful, start: "2024-01-01T08:00:00Z", minutes: 10)
    let late = category(sessionB, metric: mindful, start: "2024-01-01T20:00:00Z", minutes: 5)
    let (root, destination) = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = MemoryStateStore()
    try store.transaction.upsertCensus(
        CensusRow(
            metric: mindful,
            day: "2024-01-01",
            sampleCount: 1,
            digest: Census.digestUUIDs([sessionA])
        )
    )
    let outcome = try await sweep(
        metric: mindful,
        days: ["2024-01-01": [first, late]],
        store: store,
        root: root,
        destination: destination
    )
    #expect(outcome.kind == .success)
    let payload = try delivered(destination)
    #expect(payload.contains(late.key.uuid))
    #expect(payload.contains("\"kind\":\"aggregate\""))
    #expect(payload.contains("\"value\":15"))
    let row = try store.transaction.loadCensus(metric: mindful, day: "2024-01-01")
    #expect(row?.sampleCount == 2)
}

@Test func reconcileTombstonesADeletedMindfulSessionAndRevisesTheTotal() async throws {
    let kept = category(sessionA, metric: mindful, start: "2024-01-01T08:00:00Z", minutes: 10)
    let (root, destination) = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = MemoryStateStore()
    try store.transaction.upsertCensus(
        CensusRow(
            metric: mindful,
            day: "2024-01-01",
            sampleCount: 2,
            digest: Census.digestUUIDs([sessionA, sessionB])
        )
    )
    for uuid in [sessionA, sessionB] {
        try store.transaction.upsertEmittedIndex(
            EmittedIndexRow(
                uuid: uuid,
                metric: mindful,
                day: "2024-01-01",
                digest: Census.digestUUIDs([uuid]),
                batchID: BatchID(rawValue: "earlier")
            )
        )
    }
    let outcome = try await sweep(
        metric: mindful,
        days: ["2024-01-01": [kept]],
        store: store,
        root: root,
        destination: destination
    )
    #expect(outcome.kind == .success)
    let payload = try delivered(destination)
    #expect(payload.contains("\"kind\":\"tombstone\""))
    #expect(payload.contains(sessionB))
    #expect(payload.contains("\"value\":10"))
    #expect(try store.transaction.loadCensus(metric: mindful, day: "2024-01-01")?.sampleCount == 1)
}

@Test func reconcileRepairsALateSleepStageWithoutADailyTotal() async throws {
    let core = category(sessionA, metric: sleep, start: "2024-01-01T22:00:00Z", minutes: 90, name: "asleepCore")
    let rem = category(sessionB, metric: sleep, start: "2024-01-01T23:30:00Z", minutes: 30, name: "asleepREM")
    let (root, destination) = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = MemoryStateStore()
    try store.transaction.upsertCensus(
        CensusRow(
            metric: sleep,
            day: "2024-01-01",
            sampleCount: 1,
            digest: Census.digestUUIDs([sessionA])
        )
    )
    let outcome = try await sweep(
        metric: sleep,
        days: ["2024-01-01": [core, rem]],
        store: store,
        root: root,
        destination: destination
    )
    #expect(outcome.kind == .success)
    let payload = try delivered(destination)
    #expect(payload.contains(rem.key.uuid))
    #expect(payload.contains("asleepREM"))
    #expect(!payload.contains("\"kind\":\"aggregate\""))
    #expect(try store.transaction.loadCensus(metric: sleep, day: "2024-01-01")?.sampleCount == 2)
}

@Test func homeAssistantDiscoveryDeclaresASensorForMindfulMinutesNotSleep() throws {
    let data = try HADiscovery.encodeDeviceConfig(
        exporterId: "device-1234",
        metrics: [mindful, sleep]
    )
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let components = try #require(root["cmps"] as? [String: Any])
    let sensor = try #require(components["mindful_session_sum_p1d"] as? [String: Any])
    #expect(sensor["state_topic"] as? String == "ohe/device-1234/v1/state/mindful_session/sum/P1D")
    #expect(sensor["unit_of_measurement"] as? String == "min")
    #expect(components.count == 1)
}
