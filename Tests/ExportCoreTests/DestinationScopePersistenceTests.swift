// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import EnginePorts
import Foundation
import StorageSQLite
import Testing
import TestSupport

private func scopeStorePath() -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-scope-\(UUID().uuidString).sqlite")
        .path
}

@Test func sec16MissingDestinationScopeIsNilRatherThanAnEmptyGrant() async throws {
    let store = try SQLiteStateStore(path: scopeStorePath())
    let loaded = try await store.transact { try $0.loadDestinationScope(destinationID: "https") }
    #expect(loaded == nil)
}

@Test func sec16DestinationScopeRoundTripsThroughSQLite() async throws {
    let store = try SQLiteStateStore(path: scopeStorePath())
    let scope = try DestinationExportScope(
        destinationID: "https",
        metrics: [MetricID(rawValue: "heart_rate"), MetricID(rawValue: "step_count")],
        startInclusive: Date(timeIntervalSince1970: 1000),
        endExclusive: Date(timeIntervalSince1970: 2000)
    )
    try await store.transact { try $0.upsertDestinationScope(scope) }
    let loaded = try await store.transact { try $0.loadDestinationScope(destinationID: "https") }
    #expect(loaded == scope)
    #expect(loaded?.isConfigured == true)
    // A second destination is unaffected by the first one's grant.
    let other = try await store.transact { try $0.loadDestinationScope(destinationID: "mqtt") }
    #expect(other == nil)
}

@Test func sec16DestinationScopeOverwriteKeepsOneRowPerDestination() async throws {
    let store = try SQLiteStateStore(path: scopeStorePath())
    try await store.transact {
        try $0.upsertDestinationScope(
            DestinationExportScope(
                destinationID: "mqtt",
                metrics: [MetricID(rawValue: "heart_rate")],
                startInclusive: Date(timeIntervalSince1970: 1000)
            )
        )
    }
    let narrowed = try DestinationExportScope(
        destinationID: "mqtt",
        metrics: [MetricID(rawValue: "step_count")],
        startInclusive: Date(timeIntervalSince1970: 5000),
        endExclusive: Date(timeIntervalSince1970: 6000)
    )
    try await store.transact { try $0.upsertDestinationScope(narrowed) }
    let loaded = try await store.transact { try $0.loadDestinationScope(destinationID: "mqtt") }
    #expect(loaded == narrowed)
    #expect(loaded?.metrics == [MetricID(rawValue: "step_count")])
    #expect(loaded?.endExclusive == Date(timeIntervalSince1970: 6000))
}

/// A stored scope that grants nothing is still a decision somebody made, so it has to come
/// back as a scope and not as "no row".
@Test func sec16StoredEmptyScopeIsDistinguishableFromNoScope() async throws {
    let store = try SQLiteStateStore(path: scopeStorePath())
    let empty = try DestinationExportScope(destinationID: "companion")
    try await store.transact { try $0.upsertDestinationScope(empty) }
    let loaded = try await store.transact {
        try $0.loadDestinationScope(destinationID: "companion")
    }
    #expect(loaded == empty)
    #expect(loaded?.metrics.isEmpty == true)
    #expect(loaded?.startInclusive == nil)
    #expect(loaded?.isConfigured == false)
}

@Test func sec16DestinationScopesSurviveReopeningTheSameFile() async throws {
    let path = scopeStorePath()
    let scope = try DestinationExportScope(
        destinationID: "https",
        metrics: [MetricID(rawValue: "heart_rate")],
        startInclusive: Date(timeIntervalSince1970: 1000)
    )
    let first = try SQLiteStateStore(path: path)
    try await first.transact { try $0.upsertDestinationScope(scope) }
    let reopened = try SQLiteStateStore(path: path)
    let loaded = try await reopened.transact {
        try $0.loadDestinationScope(destinationID: "https")
    }
    #expect(loaded == scope)
}

@Test func sec16WipeClearsDestinationScopes() async throws {
    let store = try SQLiteStateStore(path: scopeStorePath())
    try await store.transact {
        try $0.upsertDestinationScope(
            DestinationExportScope(
                destinationID: "https",
                metrics: [MetricID(rawValue: "heart_rate")],
                startInclusive: Date(timeIntervalSince1970: 1000)
            )
        )
    }
    try await store.wipe(atEpoch: 10)
    let loaded = try await store.transact { try $0.loadDestinationScope(destinationID: "https") }
    #expect(loaded == nil)
}

@Test func sec16PriorSQLiteSchemaGainsScopeStorageWithoutLosingTheCursor() async throws {
    let path = scopeStorePath()
    let metric = MetricID(rawValue: "heartRate")
    let checkpoint = CheckpointEnvelope(
        tzDatabaseVersion: "2024a",
        epoch: 7,
        adapterAnchor: Data([0x33, 0x44])
    )
    try SQLiteV1Fixture.write(
        path: path,
        metric: metric,
        checkpoint: checkpoint,
        runID: "legacy-scope-run"
    )
    let store = try SQLiteStateStore(path: path)

    let snap = try await store.transact { try $0.loadCursor(metric: metric) }
    #expect(snap?.epoch == 7)
    #expect(snap?.anchorBlob == Data([0x33, 0x44]))
    let journal = try await store.transact { try $0.loadJournal() }
    #expect(journal.map(\.runID.rawValue) == ["legacy-scope-run"])

    // The migrated file has no scopes, which is what makes the app migration possible.
    let before = try await store.transact { try $0.loadDestinationScope(destinationID: "https") }
    #expect(before == nil)
    let scope = try DestinationExportScope(
        destinationID: "https",
        metrics: [MetricID(rawValue: "heart_rate")],
        startInclusive: Date(timeIntervalSince1970: 1000)
    )
    try await store.transact { try $0.upsertDestinationScope(scope) }
    let after = try await store.transact { try $0.loadDestinationScope(destinationID: "https") }
    #expect(after == scope)
    let cursorAfterScopeWrite = try await store.transact { try $0.loadCursor(metric: metric) }
    #expect(cursorAfterScopeWrite?.epoch == 7)
}

@Test func sec16MemoryStoreMatchesTheSQLiteScopeContract() async throws {
    let store = MemoryStateStore()
    func loadScope(_ destinationID: String) async throws -> DestinationExportScope? {
        try await store.transact { try $0.loadDestinationScope(destinationID: destinationID) }
    }
    #expect(try await loadScope("https") == nil)

    let empty = try DestinationExportScope(destinationID: "https")
    try await store.transact { try $0.upsertDestinationScope(empty) }
    #expect(try await loadScope("https") == empty)

    let granted = try DestinationExportScope(
        destinationID: "https",
        metrics: [MetricID(rawValue: "heart_rate")],
        startInclusive: Date(timeIntervalSince1970: 1000)
    )
    try await store.transact { try $0.upsertDestinationScope(granted) }
    #expect(try await loadScope("https") == granted)
    #expect(try await loadScope("mqtt") == nil)

    try await store.wipe(atEpoch: 10)
    #expect(try await loadScope("https") == nil)
}
