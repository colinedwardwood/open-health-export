// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation
import StorageSQLite
import Testing
import Watchdog

private func freshnessStorePath() -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-freshness-\(UUID().uuidString).sqlite")
        .path
}

private func latency(
    index: Int,
    freshnessClass: FreshnessClass = .b,
    recordedAt: TimeInterval
) -> RunFreshnessLatency {
    RunFreshnessLatency(
        runID: RunID(rawValue: "run-\(index)"),
        destinationID: "grafana",
        freshnessClass: freshnessClass,
        firstObservedAtEpoch: recordedAt - 10,
        observationLatencySeconds: TimeInterval(index + 1),
        deliveryLatencySeconds: TimeInterval((index + 1) * 2),
        recordedAtEpoch: recordedAt
    )!
}

@Test func runFreshnessLatencyRejectsInvalidEvidence() {
    #expect(
        RunFreshnessLatency(
            runID: RunID(rawValue: "run"),
            destinationID: "grafana",
            freshnessClass: .a,
            firstObservedAtEpoch: 10,
            observationLatencySeconds: -1,
            deliveryLatencySeconds: 1,
            recordedAtEpoch: 11
        ) == nil
    )
}

@Test func freshnessLatencyRoundTripsAndFiltersByDestinationAndClass() async throws {
    let path = freshnessStorePath()
    let wanted = latency(index: 1, recordedAt: 100)
    let otherClass = latency(index: 2, freshnessClass: .c, recordedAt: 200)
    do {
        let store = try SQLiteStateStore(path: path)
        try await store.transact {
            try $0.appendFreshnessLatency(wanted)
            try $0.appendFreshnessLatency(otherClass)
        }
    }

    let reopened = try SQLiteStateStore(path: path)
    let loaded = try await reopened.transact {
        try $0.loadFreshnessLatencies(destinationID: "grafana", freshnessClass: .b)
    }
    #expect(loaded == [wanted])

    try await reopened.wipe(atEpoch: 300)
    let afterWipe = try await reopened.transact {
        try $0.loadFreshnessLatencies(destinationID: "grafana", freshnessClass: .b)
    }
    #expect(afterWipe.isEmpty)
}

@Test func localFreshnessEstimateRequiresBothEvidenceGates() {
    let start: TimeInterval = 1_000
    let short = (0..<100).map {
        latency(index: $0, recordedAt: start + TimeInterval($0 * 60))
    }
    #expect(!FreshnessTarget.localEstimate(observations: short).isQualified)

    let qualifying = (0..<100).map {
        latency(
            index: $0,
            recordedAt: start + Double($0) * FreshnessTarget.minimumSpan / 99
        )
    }
    let estimate = FreshnessTarget.localEstimate(observations: qualifying)
    #expect(estimate.isQualified)
    #expect(estimate.observationP95Seconds == 95)
    #expect(estimate.deliveryP95Seconds == 190)
    #expect(estimate.totalP95Seconds == 285)
}

@Test func snapshotThresholdsUseAlarmFloorUntilLocalP95Qualifies() {
    let empty = FreshnessTarget.snapshotThresholds(estimates: [:])
    #expect(empty.overdue == FreshnessTarget.alarmFloor)
    #expect(empty.stale == FreshnessTarget.staleFloor)
    let unqualified = LocalFreshnessEstimate(sampleCount: 10, spanSeconds: 60)
    let stillFloor = FreshnessTarget.snapshotThresholds(estimates: [.b: unqualified])
    #expect(stillFloor.overdue == FreshnessTarget.alarmFloor)
    let qualified = LocalFreshnessEstimate(
        sampleCount: FreshnessTarget.minimumSamples,
        spanSeconds: FreshnessTarget.minimumSpan,
        observationP95Seconds: 1,
        deliveryP95Seconds: 1,
        totalP95Seconds: 100 * 60 * 60
    )
    let capped = FreshnessTarget.snapshotThresholds(estimates: [.a: qualified])
    #expect(capped.overdue == FreshnessTarget.alarmCap)
    #expect(capped.stale == FreshnessTarget.staleFloor)
}

@Test func loweringFreshnessCadenceWidensOverdueBeforeTheSixHourFloorMoves() {
    let defaultCadence = FreshnessTarget.snapshotThresholds(estimates: [:], cadenceSeconds: 15 * 60)
    var settings = OwnedExportSettings(freshnessIntervalMinutes: 15)
    UserFacingFixApplier.apply(.lowerFreshness, to: &settings)
    let slower = FreshnessTarget.snapshotThresholds(
        estimates: [:],
        cadenceSeconds: TimeInterval(settings.freshnessIntervalMinutes * 60)
    )
    #expect(defaultCadence.overdue == FreshnessTarget.alarmFloor)
    #expect(slower.overdue == FreshnessTarget.alarmFloor)
    let twoHours = FreshnessTarget.snapshotThresholds(estimates: [:], cadenceSeconds: 2 * 60 * 60)
    #expect(twoHours.overdue == 8 * 60 * 60)
    #expect(twoHours.stale == 4 * 60 * 60)
}

@Test func destinationSnapshotDecodesWithoutNewFreshnessField() throws {
    let data = Data(
        """
        {
          "destinationID":"legacy",
          "enabled":true,
          "lastOutcome":"success",
          "lastSuccessEpoch":10,
          "writtenAtEpoch":20
        }
        """.utf8
    )
    let snapshot = try JSONDecoder().decode(DestinationStatusSnapshot.self, from: data)
    #expect(snapshot.freshnessEstimates.isEmpty)
}

@Test func pendingDisclosureDoesNotClaimAnR71Measurement() {
    let estimate = LocalFreshnessEstimate(sampleCount: 99, spanSeconds: 20 * 86_400)
    let text = FreshnessTarget.classDisclosure(.b, estimate: estimate)
    #expect(text.contains("not yet available"))
    #expect(text.contains("pending R-71"))
    #expect(!text.contains("p95 observation latency"))
}
