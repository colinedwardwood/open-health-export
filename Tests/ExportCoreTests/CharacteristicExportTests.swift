// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CorrectnessEngine
import CoreDomain
import DestinationTrust
import Foundation
import MetricCatalog
import SinkLocalFile
import Testing
import TestSupport
import WireFormat

@Test func characteristicExportSkipsTheAnchoredPipelineAndEmitsOnce() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-characteristic-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let store = MemoryStateStore()
    let snapshot = CharacteristicRecord(
        characteristicId: "biologicalSex",
        value: "female",
        observedAt: "2026-09-12T21:00:00Z"
    )
    let run = ExportRun(
        source: FixtureSource(pages: []),
        destination: .testing(LocalFileSink(directory: root)),
        store: store,
        metric: MetricCatalog.biologicalSex.id,
        scratchDirectory: root,
        envelope: testEnvelope(),
        characteristics: FixtureCharacteristicSource(records: [
            MetricCatalog.biologicalSex.id: snapshot
        ])
    )
    let outcome = try await run.run()
    #expect(outcome.kind == .success)
    let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        .filter { $0.hasSuffix(".ndjson") }
    #expect(files.count >= 1)
    let payload = try String(
        contentsOf: root.appendingPathComponent(files[0]),
        encoding: .utf8
    )
    #expect(payload.contains("\"kind\":\"characteristic\""))
    #expect(payload.contains("\"characteristicId\":\"biologicalSex\""))
    #expect(payload.contains("\"reidentifying\":true"))
    #expect(!payload.contains("\"uuid\""))
}

@Test func characteristicExportWithNoValueIsNothingDue() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-characteristic-empty-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let outcome = try await ExportRun(
        source: FixtureSource(pages: []),
        destination: .testing(LocalFileSink(directory: root)),
        store: MemoryStateStore(),
        metric: MetricCatalog.dateOfBirth.id,
        scratchDirectory: root,
        envelope: testEnvelope(),
        characteristics: FixtureCharacteristicSource()
    ).run()
    #expect(outcome.kind == .successNothingDue)
}

@Test func characteristicTokensFormatClosedDateAndStayReidentifying() {
    #expect(MetricCatalog.isCharacteristic(MetricCatalog.fitzpatrickSkinType.id))
    #expect(!MetricCatalog.isCharacteristic(MetricCatalog.heartRate.id))
    #expect(MetricCatalog.biologicalSex.characteristicId == "biologicalSex")
    #expect(MetricCatalog.characteristics.allSatisfy { declaration in declaration.reidentifying })
}
