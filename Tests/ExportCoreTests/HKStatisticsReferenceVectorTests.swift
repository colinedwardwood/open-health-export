// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation
import MetricCatalog
import SinkLocalFile
import Testing
import TestSupport
@testable import CorrectnessEngine
@testable import WireFormat

private struct HKStatisticsVectorFile: Decodable {
    var version: Int
    var kind: String
    var canonicality: String
    var day: String
    var vectors: [HKStatisticsVector]
}

private struct HKStatisticsVector: Decodable {
    var metricId: String
    var value: Double
}

@Test func r80EveryHkStatisticsExceptionHasALinuxReferenceVector() async throws {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("spec/v1.0.0/fixtures/hk-statistics-reference-vectors.json")
    let file = try JSONDecoder().decode(
        HKStatisticsVectorFile.self,
        from: Data(contentsOf: url)
    )
    #expect(file.version == 1)
    #expect(file.kind == "synthetic-pipeline-reference")
    #expect(file.canonicality == "pending-R-87-device-pass")
    #expect(Set(file.vectors.map(\.metricId)).count == file.vectors.count)

    let exceptionIDs = MetricCatalog.hkStatisticsExceptions.compactMap {
        MetricCatalog.declaration(for: $0)?.wireId
    }.sorted()
    #expect(file.vectors.map(\.metricId).sorted() == exceptionIDs)

    for vector in file.vectors {
        let declaration = try #require(
            MetricCatalog.all.first { $0.wireId == vector.metricId }
        )
        let metric = declaration.id
        let store = MemoryStateStore()
        try store.transaction.markDirty(metric: metric, day: file.day)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohe-r80-\(vector.metricId)-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let run = ExportRun(
            source: FixtureSource(pages: []),
            destination: .testing(LocalFileSink(directory: destination)),
            store: store,
            metric: metric,
            scratchDirectory: root.appendingPathComponent("scratch"),
            envelope: testEnvelope(),
            statistics: FixtureStatistics(
                byDay: [
                    file.day: statisticsRecord(
                        metric: metric,
                        day: file.day,
                        value: vector.value
                    ),
                ]
            )
        )
        #expect(try await run.run().kind == .success, "\(vector.metricId) export failed")
        #expect(try store.transaction.dirtyDays(metric: metric).isEmpty, "\(vector.metricId)")
        let delivered = try FileManager.default.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "ndjson" }
        let payload = try String(
            contentsOf: try #require(delivered.first),
            encoding: .utf8
        )
        #expect(payload.contains("\"kind\":\"aggregate\""), "\(vector.metricId)")
        #expect(
            payload.contains("\"metricId\":\"\(vector.metricId)\""),
            "\(vector.metricId)"
        )
        #expect(payload.contains("\"value\":\(Int(vector.value))"), "\(vector.metricId)")
        #expect(
            payload.contains("\"healthKitStatisticsCollectionQuery\""),
            "\(vector.metricId)"
        )
    }
}
