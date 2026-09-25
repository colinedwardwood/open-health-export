// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CorrectnessEngine
import EnginePorts
import Foundation
import SinkLocalFile
import StorageSQLite
import Testing

/// Returns its one page after a pause, so two runs that start together are both
/// reading before either commits: the window #31 is about.
private struct SlowOnePageSource: SampleSource {
    var page: SamplePage

    func page(metric: MetricID, afterAnchor: Data?) async throws -> SamplePage {
        try await Task.sleep(for: .milliseconds(150))
        guard afterAnchor != page.anchorBlob else {
            return SamplePage(
                samples: [],
                tombstones: [],
                metric: metric,
                anchorBlob: page.anchorBlob,
                observedThrough: page.observedThrough
            )
        }
        return page
    }
}

/// #31: foreground catch-up, an observer wake, a Shortcut or the Control Centre control
/// can start the same metric's export at once. The second run must wait and then start
/// from the first one's cursor, so the page is committed and delivered once.
@Test func concurrentRunsOfOneMetricDeliverEachPageOnce() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("cccccccc-cccc-4ccc-8ccc-cccccccccccc")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0xC1]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-single-flight-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let out = root.appendingPathComponent("out")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
    let run = ExportRun(
        source: SlowOnePageSource(page: page),
        destination: .testing(LocalFileSink(directory: out)),
        store: store,
        metric: metric,
        scratchDirectory: root.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    )
    async let first = run.run()
    async let second = run.run()
    _ = try await (first, second)

    let delivered = try FileManager.default.contentsOfDirectory(atPath: out.path)
        .filter { $0.hasSuffix(".ndjson") }
    #expect(delivered.count == 1, "\(delivered)")
    let cursor = try await store.transact { try $0.loadCursor(metric: metric) }
    #expect(cursor?.anchorBlob == page.anchorBlob)
}
