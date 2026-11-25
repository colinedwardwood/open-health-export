// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import DestinationTrust
import EnginePorts
import Foundation
import NetEgress
import Testing
import Watchdog
@testable import CorrectnessEngine

// MARK: Fakes

private final class MemoryExportSettings: ExportSettingsStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var windowHours: Int?
    private var freshnessMinutes: Int?
    private var lastReconcile: TimeInterval?

    init(windowHours: Int? = nil, freshnessMinutes: Int? = nil, lastReconcile: TimeInterval? = nil) {
        self.windowHours = windowHours
        self.freshnessMinutes = freshnessMinutes
        self.lastReconcile = lastReconcile
    }

    func exportWindowHours() -> Int? { lock.withLock { windowHours } }
    func freshnessIntervalMinutes() -> Int? { lock.withLock { freshnessMinutes } }
    func lastScheduledFullReconcileEpoch() -> TimeInterval? { lock.withLock { lastReconcile } }
    func setLastScheduledFullReconcileEpoch(_ epoch: TimeInterval) { lock.withLock { lastReconcile = epoch } }
}

private struct FixedConditions: ExportConditionsSource {
    var value = ExportConditions()
    var path = NetworkPathConditions.clear

    func conditions() -> ExportConditions { value }
    func networkPath() -> NetworkPathConditions { path }
}

private final class MemorySnapshots: DestinationStatusStore, @unchecked Sendable {
    private let lock = NSLock()
    private var byID: [String: DestinationStatusSnapshot]

    init(_ snapshots: [DestinationStatusSnapshot]) {
        byID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.destinationID, $0) })
    }

    func readAll() -> [DestinationStatusSnapshot] {
        lock.withLock { byID.values.sorted { $0.destinationID < $1.destinationID } }
    }

    func read(destinationID: String) -> DestinationStatusSnapshot? {
        lock.withLock { byID[destinationID] }
    }

    func write(_ snapshot: DestinationStatusSnapshot) throws {
        lock.withLock { byID[snapshot.destinationID] = snapshot }
    }
}

private struct NeverSink: DestinationSink {
    func send(fileHandle: String, idempotencyKey: BatchID) async throws -> DeliveryReceipt {
        throw DestinationSendError.destinationUnreachable
    }
}

private let heart = MetricID(rawValue: "heart_rate")
private let steps = MetricID(rawValue: "step_count")

private func snapshot(_ id: String, label: String? = nil, outcome: String? = "success") -> DestinationStatusSnapshot {
    DestinationStatusSnapshot(
        destinationID: id,
        destinationLabel: label,
        enabled: true,
        lastOutcome: outcome,
        writtenAtEpoch: 0
    )
}

private func scope(
    _ id: String,
    _ metrics: Set<MetricID>,
    start: String? = nil,
    end: String? = nil
) throws -> DestinationExportScope {
    func day(_ text: String?) -> Date? {
        text.flatMap { try? Date("\($0)T00:00:00Z", strategy: .iso8601) }
    }
    return try DestinationExportScope(
        destinationID: id,
        metrics: metrics,
        startInclusive: day(start),
        endExclusive: day(end)
    )
}

private func runDestination(_ id: String, scope: DestinationExportScope?) -> RunDestination {
    RunDestination(id: id, destination: .testing(NeverSink()), scope: scope)
}

private func row(_ id: String, _ kind: RunOutcome.Kind, errorClass: String? = nil) -> DestinationRunRow {
    DestinationRunRow(
        destinationID: id,
        outcomeKind: kind.rawValue,
        detail: "",
        expectedRecords: 0,
        acceptedRecords: 0,
        errorClass: errorClass
    )
}

// MARK: Which destinations a trigger runs

@Test func exportPlanRunsOnlyEnabledDestinationsTheTriggerAllows() {
    let enabled: Set = ["local-file", "https", "companion"]
    let manualOnly: Set = ["https"]
    let planned = { (trigger: RunTrigger) in
        ExportPlan.destinations(
            for: trigger,
            among: DestinationRepository.healthDestinationIDs,
            isEnabled: { enabled.contains($0) },
            allowsExport: { id, trigger in trigger == .manual || !manualOnly.contains(id) }
        )
    }
    #expect(planned(.manual) == ["local-file", "https", "companion"])
    #expect(planned(.observerQuery) == ["local-file", "companion"])
    #expect(planned(.bgAppRefresh) == ["local-file", "companion"])
}

@Test func exportPlanBackfillCountsManualOnlyAndKeepsAResumedJobsSinks() {
    let planned = ExportPlan.backfillDestinations(
        among: DestinationRepository.healthDestinationIDs,
        isEnabled: { $0 != "mqtt" }
    )
    #expect(planned == ["local-file", "https", "home-assistant", "companion"])
    #expect(ExportPlan.backfillOwed(planned: planned, resumedPlan: nil) == planned)
    // A sink enabled mid-job does not inherit the job's completed days.
    #expect(
        ExportPlan.backfillOwed(planned: planned, resumedPlan: ["https", "mqtt", "local-file"])
            == ["local-file", "https"]
    )
}

@Test func drainLimitGivesForegroundRunsTheBacklogAndWakesOnlyAFewBatches() {
    for trigger in [RunTrigger.manual, .widgetControl, .appForeground, .launch] {
        #expect(ExportPlan.drainLimit(trigger: trigger) == 32)
    }
    for trigger in [RunTrigger.observerQuery, .bgAppRefresh, .bgProcessing, .shortcut] {
        #expect(ExportPlan.drainLimit(trigger: trigger) == 4)
    }
}

@Test func exportPlanCoversOnlyDestinationsWhoseScopeAsksForTheType() throws {
    let archive = runDestination("local-file", scope: try scope("local-file", [heart, steps]))
    let server = runDestination("https", scope: try scope("https", [steps]))
    let unscoped = runDestination("mqtt", scope: nil)
    #expect(ExportPlan.covering([archive, server, unscoped], metric: heart).map(\.id) == ["local-file", "mqtt"])
    #expect(ExportPlan.covering([archive, server, unscoped], metric: steps).map(\.id) == ["local-file", "https", "mqtt"])
    #expect(
        ExportPlan.metrics(for: [try scope("a", [steps]), try scope("b", [heart, steps])])
            == [heart, steps]
    )
}

@Test func exportPlanFindsQueueEvictionsThisRunAdded() {
    let old = GapRecord(batchID: BatchID(rawValue: "old"), rangeDescription: "queue_eviction:x", rangeStartDay: "2026-01-01", rangeEndDay: "2026-01-02")
    let fresh = GapRecord(batchID: BatchID(rawValue: "new"), rangeDescription: "queue_eviction:y")
    let other = GapRecord(batchID: BatchID(rawValue: "other"), rangeDescription: "anchor_reset")
    #expect(!ExportPlan.evictedDuringRun(gaps: [old, other], before: [old.batchID]))
    #expect(ExportPlan.evictedDuringRun(gaps: [old, fresh], before: [old.batchID]))
    // Only a gap with a day range can be re-exported.
    #expect(ExportPlan.reExportableQueueGaps([old, fresh, other]).map(\.batchID) == [old.batchID])
}

@Test func exportPlanRedQueueAndOwedLabel() {
    let policy = QueuePolicy.production
    #expect(!ExportPlan.queueIsRed(queuedBytes: policy.catchUpLimit))
    #expect(ExportPlan.queueIsRed(queuedBytes: policy.redLimit))
    #expect(ExportPlan.owedDestinationLabel([]) == "no enabled destination")
    #expect(ExportPlan.owedDestinationLabel(["local-file", "mqtt"]) == "local-file,mqtt")
}

@Test func backfillWindowSpansTheUnionOfScopesWithinAvailableHistory() throws {
    let scopes = [
        try scope("local-file", [heart], start: "2024-03-01"),
        try scope("https", [heart, steps], start: "2024-01-15", end: "2024-02-01"),
    ]
    let window = ExportPlan.backfillWindow(
        scopes: scopes,
        available: [heart: "2024-01-01" ... "2024-06-30", steps: "2024-01-20" ... "2024-06-30"]
    )
    #expect(window == BackfillWindow(metrics: [heart, steps], firstDay: "2024-01-15", lastDay: "2024-06-30"))
}

@Test func backfillWindowSkipsTypesWithoutHistoryOrScopesWithoutAStart() throws {
    #expect(ExportPlan.backfillWindow(scopes: [try scope("a", [heart], start: "2024-01-01")], available: [:]) == nil)
    // A scope with no start date never asks for history.
    #expect(ExportPlan.backfillWindow(scopes: [try scope("a", [heart])], available: [heart: "2024-01-01" ... "2024-02-01"]) == nil)
    // Window entirely after the available history.
    #expect(
        ExportPlan.backfillWindow(
            scopes: [try scope("a", [heart], start: "2025-01-01")],
            available: [heart: "2024-01-01" ... "2024-02-01"]
        ) == nil
    )
}

// MARK: Tuning under low power, thermal and settings

@Test func exportTuningFollowsTheExportWindowAndHalvesPagesWhenHot() {
    let settings = MemoryExportSettings(windowHours: 12)
    let cool = ExportTuning(settings: settings, conditions: FixedConditions())
    #expect(cool.samplePageLimit() == SamplePaging.pageLimit(windowHours: 12))
    #expect(!cool.isThermalDeferred() && !cool.prefersStoredCompression())
    for level in [ThermalLevel.serious, .critical] {
        let hot = ExportTuning(settings: settings, conditions: FixedConditions(value: ExportConditions(thermal: level)))
        #expect(hot.isThermalDeferred())
        #expect(hot.prefersStoredCompression())
        #expect(hot.samplePageLimit() == SamplePaging.pageLimit(windowHours: 12, thermalHalved: true))
    }
    let fair = ExportTuning(settings: settings, conditions: FixedConditions(value: ExportConditions(thermal: .fair)))
    #expect(!fair.isThermalDeferred())
    let unset = ExportTuning(settings: MemoryExportSettings(), conditions: FixedConditions())
    #expect(unset.samplePageLimit() == SamplePaging.pageLimit(windowHours: 24))
}

@Test func exportTuningDefersForLowPowerAndReadsTheFreshnessCadence() {
    let low = ExportTuning(
        settings: MemoryExportSettings(freshnessMinutes: 30),
        conditions: FixedConditions(
            value: ExportConditions(lowPowerMode: true),
            path: NetworkPathConditions(isExpensive: true, isConstrained: false)
        )
    )
    #expect(low.isLowPowerDeferred())
    #expect(!low.isThermalDeferred())
    #expect(low.freshnessCadenceSeconds() == 1_800)
    #expect(low.networkPathConditions().isExpensive)
    let defaults = ExportTuning(settings: MemoryExportSettings(freshnessMinutes: 0), conditions: FixedConditions())
    #expect(!defaults.isLowPowerDeferred())
    #expect(defaults.freshnessCadenceSeconds() == 60)
    #expect(ExportTuning(settings: MemoryExportSettings(), conditions: FixedConditions()).freshnessCadenceSeconds() == 900)
}

// MARK: Scheduled reconcile (O-9)

@Test func scheduledReconcileFollowsOnlyForegroundAndLaunchRuns() {
    for trigger in RunTrigger.allCases {
        #expect(ScheduledReconcileGate.follows(trigger) == (trigger == .appForeground || trigger == .launch))
    }
}

@Test func scheduledReconcileIsParkedInAmberAndRunsDaily() {
    let settings = MemoryExportSettings()
    let gate = ScheduledReconcileGate(settings: settings)
    let amber = QueuePolicy.production.catchUpLimit
    #expect(gate.decide(queuedBytes: amber, nowEpoch: 1_000) == .parked)
    #expect(gate.decide(queuedBytes: 0, nowEpoch: 1_000) == .due)
    gate.recordRun(atEpoch: 1_000)
    #expect(settings.lastScheduledFullReconcileEpoch() == 1_000)
    #expect(gate.decide(queuedBytes: 0, nowEpoch: 1_000 + 3_600) == .notDue)
    #expect(gate.decide(queuedBytes: 0, nowEpoch: 1_000 + ScheduledReconcile.defaultInterval) == .due)
}

// MARK: Destination status after a run

@Test func outcomeRecorderAppliesEachSinksOwnRowAndLeavesOthersAlone() {
    let snapshots = MemorySnapshots([
        snapshot("local-file"),
        snapshot("https", outcome: "failed"),
        snapshot("mqtt", outcome: "failed"),
    ])
    let recorder = ExportOutcomeRecorder(snapshots: snapshots, now: { Date(timeIntervalSince1970: 500) })
    recorder.apply(
        [row("local-file", .failed, errorClass: "destination_unreachable"), row("https", .success)],
        to: ["local-file", "https", "mqtt"]
    )
    let archive = snapshots.read(destinationID: "local-file")
    #expect(archive?.lastOutcome == "failed")
    #expect(archive?.errorClass == "destination_unreachable")
    #expect(archive?.lastSuccessEpoch == nil)
    let server = snapshots.read(destinationID: "https")
    #expect(server?.lastOutcome == "success")
    #expect(server?.lastSuccessEpoch == 500)
    #expect(server?.writtenAtEpoch == 500)
    // No row: nothing was attempted, so the last result stands.
    #expect(snapshots.read(destinationID: "mqtt")?.lastOutcome == "failed")
    #expect(snapshots.read(destinationID: "mqtt")?.writtenAtEpoch == 0)
}

@Test func outcomeRecorderGivesEachDestinationItsOwnRunOutcome() throws {
    let snapshots = MemorySnapshots([snapshot("local-file"), snapshot("https"), snapshot("companion"), snapshot("mqtt", outcome: "failed")])
    let recorder = ExportOutcomeRecorder(snapshots: snapshots, now: { Date(timeIntervalSince1970: 9) })
    try recorder.applyRunOutcome(
        planned: ["local-file", "https", "companion", "mqtt"],
        unreconstructed: ["mqtt"],
        kindsByDestination: ["local-file": [.success, .success], "https": [.success, .failed]],
        combined: .partial
    )
    #expect(snapshots.read(destinationID: "local-file")?.lastOutcome == CombinedExportSummary.kind([.success, .success]).rawValue)
    #expect(snapshots.read(destinationID: "https")?.lastOutcome == CombinedExportSummary.kind([.success, .failed]).rawValue)
    // Queued-only sink keeps the combined outcome; an unrebuildable one keeps its own failure.
    #expect(snapshots.read(destinationID: "companion")?.lastOutcome == "partial")
    #expect(snapshots.read(destinationID: "mqtt")?.lastOutcome == "failed")
    #expect(snapshots.read(destinationID: "mqtt")?.writtenAtEpoch == 0)
}

@Test func outcomeRecorderMarksInterruptedRunsCancelledBySystem() throws {
    let snapshots = MemorySnapshots([snapshot("https", label: "Home server")])
    let recorder = ExportOutcomeRecorder(snapshots: snapshots, now: { Date(timeIntervalSince1970: 0) })
    try recorder.markInterrupted(["https", "unknown"], atEpoch: 42)
    let server = snapshots.read(destinationID: "https")
    #expect(server?.lastOutcome == RunOutcome.Kind.cancelledBySystem.rawValue)
    #expect(server?.errorClass == ErrorClass.cancelledBySystem.rawValue)
    #expect(server?.writtenAtEpoch == 42)
    #expect(recorder.label("https") == "Home server")
    #expect(recorder.label("unknown") == "unknown")
}

// MARK: Wipe

@Test func wipeRemovesEveryDestinationRecordAndEngineArtifact() {
    let artifacts = Set(ExportWipe.applicationSupportArtifacts)
    #expect(artifacts.count == ExportWipe.applicationSupportArtifacts.count)
    for sidecar in [
        DestinationSidecar.httpsRecord(destinationID: "https"),
        .httpsRecord(destinationID: "home-assistant"),
        .mqttRecord,
        .companionTestReport,
        .localFileTestReport,
        .localFolderBookmark,
    ] {
        #expect(artifacts.contains(sidecar.filename), "\(sidecar.filename) survives a wipe")
    }
    for artifact in [
        "exports", "scratch", "backfill-scratch", "demo-exports", "demo-scratch",
        "demo-state.sqlite", "backfill-raw.json", "backfill-aggregate.json",
        "exporter-id", "wake-ledger.log", "health-authorization.json", "network-activity.json",
        "mqtt-client.p12", "otlp-destination.json", "imported-destination-drafts.json",
    ] {
        #expect(artifacts.contains(artifact), "\(artifact) survives a wipe")
    }
}
