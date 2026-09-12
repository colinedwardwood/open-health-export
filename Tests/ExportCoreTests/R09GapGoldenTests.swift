// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CorrectnessEngine
import EnginePorts
import Foundation
import MetricCatalog
import Testing
import TestSupport

@Test func r09FillQueueGapRecordsMatchGoldenNDJSON() throws {
    let tx = MemoryTransaction()
    let metric = MetricCatalog.heartRate.id
    let batches = [
        PendingBatch(
            id: BatchID(rawValue: "queue-1"),
            payloadURL: "/tmp/queue-1",
            expectedRecords: 2,
            byteCount: 8,
            metric: metric,
            createdAtEpoch: 1,
            rangeStartDay: "2026-01-01",
            rangeEndDay: "2026-01-01"
        ),
        PendingBatch(
            id: BatchID(rawValue: "queue-2"),
            payloadURL: "/tmp/queue-2",
            expectedRecords: 3,
            byteCount: 8,
            metric: metric,
            createdAtEpoch: 2,
            rangeStartDay: "2026-01-02",
            rangeEndDay: "2026-01-03"
        ),
    ]
    for batch in batches {
        try tx.enqueuePending(batch)
    }
    let evicted = try QueueAdmission.makeRoom(
        for: 3,
        on: tx,
        policy: QueuePolicy(cap: 10, lowWatermark: 4)
    )
    #expect(evicted.map(\.id.rawValue) == ["queue-1", "queue-2"])
    let actual = try GapRecordCanonical.ndjson(try tx.loadGaps())
    let goldenURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("qa/r09-queue-eviction-gaps.ndjson")
    let expected = try Data(contentsOf: goldenURL)
    #expect(actual == expected)
}
