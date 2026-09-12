// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CoreTemporal
@testable import CorrectnessEngine
import EnginePorts
import Foundation
import MetricCatalog
import Testing
import TestSupport

private struct CoverageRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

private func coverageISODay(_ offset: Int) -> String {
    let calendar = TemporalContext.utc.calendar()
    var components = DateComponents()
    components.year = 2026
    components.month = 1
    components.day = 1
    let start = calendar.date(from: components)!
    let date = calendar.date(byAdding: .day, value: offset, to: start)!
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return DayBucket(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0).isoDay
}

@Test func reliabilityCoverageRejectsSilentPendingDrop() throws {
    let tx = MemoryTransaction()
    let batch = PendingBatch(
        id: BatchID(rawValue: "lost"),
        payloadURL: "/tmp/lost",
        expectedRecords: 4,
        byteCount: 8,
        metric: MetricCatalog.heartRate.id,
        rangeStartDay: "2026-01-01",
        rangeEndDay: "2026-01-02"
    )
    try tx.enqueuePending(batch)
    #expect(try ReliabilityCoverage.holds(on: tx, read: 4))
    tx.pending.removeValue(forKey: batch.id)
    #expect(try ReliabilityCoverage.holds(on: tx, read: 4) == false)
}

@Test func r21AckShortfallIsNeverSuccess() {
    #expect(RunOutcome.derive(from: RunTally(read: 10, acked: 9)).kind != .success)
    #expect(RunOutcome.derive(from: RunTally(read: 10, acked: 10)).kind == .success)
}

@Test func overlappingEvictionGapsOvercoverAndCountExactly() throws {
    let tx = MemoryTransaction()
    let metric = MetricCatalog.heartRate.id
    let early = PendingBatch(
        id: BatchID(rawValue: "early"),
        payloadURL: "/tmp/early",
        expectedRecords: 3,
        byteCount: 20,
        metric: metric,
        createdAtEpoch: 1,
        rangeStartDay: "2026-01-01",
        rangeEndDay: "2026-01-05"
    )
    let late = PendingBatch(
        id: BatchID(rawValue: "late"),
        payloadURL: "/tmp/late",
        expectedRecords: 4,
        byteCount: 20,
        metric: metric,
        createdAtEpoch: 2,
        rangeStartDay: "2026-01-03",
        rangeEndDay: "2026-01-08"
    )
    try tx.enqueuePending(early)
    try tx.enqueuePending(late)
    let evicted = try QueueAdmission.makeRoom(
        for: 1,
        on: tx,
        policy: QueuePolicy(cap: 30, lowWatermark: 1)
    )
    #expect(Set(evicted.map(\.id.rawValue)) == ["early", "late"])
    let gaps = try tx.loadGaps()
    #expect(gaps.reduce(0) { $0 + $1.expectedRecords } == 7)
    #expect(ReliabilityCoverage.gapsOvercoverEvicted(gaps, evicted))
    #expect(try ReliabilityCoverage.holds(on: tx, read: 7))
}

@Test func deliveredUnionGapCoversReadAcrossEnqueueEvictAckPurgeAndTTL() throws {
    let metric = MetricCatalog.heartRate.id
    let policy = QueuePolicy(cap: 40, lowWatermark: 16)
    for seed in 1 ... 40 {
        var rng = CoverageRNG(seed: UInt64(seed))
        let tx = MemoryTransaction()
        var read = 0
        var nextID = 0
        var evicted: [PendingBatch] = []
        for step in 1 ... 80 {
            switch rng.next() % 5 {
            case 0, 1:
                nextID += 1
                let records = Int(rng.next() % 5) + 1
                let startOff = Int(rng.next() % 20)
                let span = Int(rng.next() % 4)
                let batch = PendingBatch(
                    id: BatchID(rawValue: "s\(seed)-b\(nextID)"),
                    payloadURL: "/tmp/\(seed)-\(nextID)",
                    expectedRecords: records,
                    byteCount: records * 4,
                    metric: metric,
                    createdAtEpoch: TimeInterval(step),
                    rangeStartDay: coverageISODay(startOff),
                    rangeEndDay: coverageISODay(startOff + span)
                )
                try tx.enqueuePending(batch)
                read += records
                evicted.append(
                    contentsOf: try QueueAdmission.makeRoom(for: 0, on: tx, policy: policy)
                )
            case 2:
                if let batch = try tx.pendingBatches().first {
                    try tx.recordDelivery(
                        DeliveryReceipt(
                            batchID: batch.id,
                            accepted: batch.expectedRecords,
                            statusOnly: false
                        )
                    )
                }
            case 3:
                let victims = try tx.pendingBatches()
                _ = try TypePurge.apply(
                    metric: metric,
                    reason: TypeDisableReason.authorizationRevoked,
                    destination: "coverage",
                    atEpoch: TimeInterval(step),
                    on: tx
                )
                evicted.append(contentsOf: victims)
                let generation = try tx.loadTypeStatus(metric: metric)?.generation ?? 1
                try tx.upsertTypeStatus(
                    TypeStatus(
                        metric: metric,
                        disabled: false,
                        reason: "coverage_grant",
                        generation: generation
                    )
                )
            default:
                let before = try tx.pendingBatches()
                _ = try QueueExpiry.apply(
                    nowEpoch: TimeInterval(step) + QueueExpiry.timeToLive + 1,
                    destination: "coverage",
                    on: tx
                )
                let remaining = Set(try tx.pendingBatches().map(\.id))
                evicted.append(contentsOf: before.filter { !remaining.contains($0.id) })
            }
            #expect(
                try ReliabilityCoverage.holds(on: tx, read: read),
                "silent loss at seed \(seed) step \(step)"
            )
        }
        let gappedIDs = Set(try tx.loadGaps().map(\.batchID))
        let extents = evicted.filter { gappedIDs.contains($0.id) }
        #expect(
            ReliabilityCoverage.gapsOvercoverEvicted(try tx.loadGaps(), extents),
            "I5 under-cover at seed \(seed)"
        )
    }
}
