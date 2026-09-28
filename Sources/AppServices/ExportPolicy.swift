// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CorrectnessEngine
import EnginePorts
import Foundation
import NetEgress
import Watchdog

// MARK: Device conditions and settings

/// The device's thermal state, without the platform type (#42).
public enum ThermalLevel: Sendable, Equatable, CaseIterable {
    case nominal
    case fair
    case serious
    case critical
}

/// What the device is doing right now that changes how an export behaves.
public struct ExportConditions: Sendable, Equatable {
    public var lowPowerMode: Bool
    public var thermal: ThermalLevel

    public init(lowPowerMode: Bool = false, thermal: ThermalLevel = .nominal) {
        self.lowPowerMode = lowPowerMode
        self.thermal = thermal
    }

    /// Low Power Mode parks catch-up work; the live read still goes.
    public var defersForLowPower: Bool { lowPowerMode }

    /// Reliability thermal policy: at serious or worse, backfill parks, HealthKit pages
    /// halve and payloads are stored rather than compressed.
    public var defersForThermal: Bool {
        switch thermal {
        case .serious, .critical:
            true
        case .nominal, .fair:
            false
        }
    }
}

/// Where the device conditions come from. The app reads the process and the network
/// path monitor; tests hand in fixed values.
public protocol ExportConditionsSource: Sendable {
    func conditions() -> ExportConditions
    func networkPath() -> NetworkPathConditions
}

/// The owned settings an export reads. Nil means never set.
public protocol ExportSettingsStorage: Sendable {
    /// UX-29: the 413 shorten-window action writes this.
    func exportWindowHours() -> Int?
    func freshnessIntervalMinutes() -> Int?
    func lastScheduledFullReconcileEpoch() -> TimeInterval?
    func setLastScheduledFullReconcileEpoch(_ epoch: TimeInterval)
}

/// The knobs every run is built with, from the settings and the device conditions.
public struct ExportTuning: Sendable {
    public static let defaultWindowHours = 24
    public static let defaultFreshnessMinutes = 15

    private let settings: any ExportSettingsStorage
    private let source: any ExportConditionsSource

    public init(settings: any ExportSettingsStorage, conditions: any ExportConditionsSource) {
        self.settings = settings
        self.source = conditions
    }

    /// UX-29: HealthKit pages follow the owned export window so the next batch after a
    /// 413 is smaller, and halve under thermal pressure.
    public func samplePageLimit() -> Int {
        SamplePaging.pageLimit(
            windowHours: settings.exportWindowHours() ?? Self.defaultWindowHours,
            thermalHalved: isThermalDeferred()
        )
    }

    public func freshnessCadenceSeconds() -> TimeInterval {
        TimeInterval(max(1, settings.freshnessIntervalMinutes() ?? Self.defaultFreshnessMinutes) * 60)
    }

    public func isLowPowerDeferred() -> Bool {
        source.conditions().defersForLowPower
    }

    public func isThermalDeferred() -> Bool {
        source.conditions().defersForThermal
    }

    /// Under thermal pressure gzip stores rather than spends CPU compressing.
    public func prefersStoredCompression() -> Bool {
        isThermalDeferred()
    }

    public func networkPathConditions() -> NetworkPathConditions {
        source.networkPath()
    }
}

// MARK: Scheduled full reconcile (O-9)

public enum ScheduledReconcileDecision: Sendable, Equatable {
    /// The queue is already in I6 Amber: a full reconcile would evict live deltas.
    case parked
    case notDue
    case due
}

/// O-9: a low-priority full reconcile on a daily cadence after a foreground or launch
/// run, skipped while the queue is in I6 Amber so live deltas are not evicted.
public struct ScheduledReconcileGate: Sendable {
    public static let parkedLine = "scheduled full reconcile skipped: catch_up_parked"
    public static let ranLine = "scheduled full reconcile"

    private let settings: any ExportSettingsStorage

    public init(settings: any ExportSettingsStorage) {
        self.settings = settings
    }

    /// Only a run the person can see starting is followed by the daily reconcile.
    public static func follows(_ trigger: RunTrigger) -> Bool {
        trigger == .appForeground || trigger == .launch
    }

    public func decide(queuedBytes: Int, nowEpoch: TimeInterval) -> ScheduledReconcileDecision {
        if !CatchUpAdmission.allows(queuedBytes: queuedBytes) {
            return .parked
        }
        return ScheduledReconcile.due(
            lastEpoch: settings.lastScheduledFullReconcileEpoch(),
            nowEpoch: nowEpoch
        ) ? .due : .notDue
    }

    /// Recorded only once the reconcile has finished, so a failed one is retried.
    public func recordRun(atEpoch epoch: TimeInterval) {
        settings.setLastScheduledFullReconcileEpoch(epoch)
    }
}

// MARK: Which destinations, which work

/// The day window a new backfill job spans, and the types it covers.
public struct BackfillWindow: Sendable, Equatable {
    public var metrics: [MetricID]
    public var firstDay: String
    public var lastDay: String

    public init(metrics: [MetricID], firstDay: String, lastDay: String) {
        self.metrics = metrics
        self.firstDay = firstDay
        self.lastDay = lastDay
    }
}

/// The pure decisions behind running an export (#42): which destinations a trigger
/// runs, how much backlog a wake may drain, what a sweep covers.
public enum ExportPlan {
    public static let manualOnlyExportLine =
        "manualOnly: Automatic export skipped. This installation allows explicit exports only."
    public static let manualOnlyReconcileLine =
        "manualOnly: Full reconcile skipped. This installation allows explicit exports only."
    public static let noBackfillDestinationLine =
        "No destination is enabled, so there is nowhere to send history."
    public static let noBackfillHistoryLine =
        "No supported Health history is available for backfill."
    public static let traceparentAutoDisabledLine =
        "traceparent auto-disabled after a header-plausible failure"
    public static let queueEvictionPrefix = "queue_eviction:"

    /// The enabled destinations this trigger may export to, in display order. A
    /// manual-only destination is left out of every automatic trigger.
    public static func destinations(
        for trigger: RunTrigger,
        among candidates: [String],
        isEnabled: (String) -> Bool,
        allowsExport: (String, RunTrigger) -> Bool
    ) -> [String] {
        candidates.filter { isEnabled($0) && allowsExport($0, trigger) }
    }

    /// Backfill is an explicit user action (R-11/O-5), so manual-only sinks count.
    public static func backfillDestinations(
        among candidates: [String],
        isEnabled: (String) -> Bool
    ) -> [String] {
        candidates.filter(isEnabled)
    }

    /// A resumed job keeps the sinks it was planned for: a day marked complete means
    /// complete for those, and a sink enabled mid-job would silently inherit that
    /// completion. It gets its own job once this one finishes.
    public static func backfillOwed(planned: [String], resumedPlan: [String]?) -> [String] {
        guard let resumedPlan else { return planned }
        return planned.filter { resumedPlan.contains($0) }
    }

    /// A background wake has seconds, not minutes, and the read it was woken for
    /// matters more than an old obligation. A foreground run can afford the backlog.
    public static func drainLimit(trigger: RunTrigger) -> Int {
        switch trigger {
        case .manual, .widgetControl, .appForeground, .launch:
            32
        case .observerQuery, .bgAppRefresh, .bgProcessing, .shortcut:
            4
        }
    }

    /// Whether a destination's scope asks for this type. A destination with no scope
    /// takes everything.
    public static func covers(_ scope: DestinationExportScope?, metric: MetricID) -> Bool {
        scope.map { $0.metrics.contains(metric) } ?? true
    }

    /// The destinations one read of this type fans out to.
    public static func covering(
        _ destinations: [RunDestination],
        metric: MetricID
    ) -> [RunDestination] {
        destinations.filter { covers($0.scope, metric: metric) }
    }

    /// The types a run covers when none were named: the union of every scope, in a
    /// stable order.
    public static func metrics(for scopes: [DestinationExportScope]) -> [MetricID] {
        Set(scopes.flatMap(\.metrics)).sorted { $0.rawValue < $1.rawValue }
    }

    public static func succeeded(_ kind: RunOutcome.Kind) -> Bool {
        kind == .success || kind == .successNothingDue
    }

    /// I6 Red: drop derived attempt bodies, truncate the WAL, raise the notice.
    public static func queueIsRed(queuedBytes: Int) -> Bool {
        QueueRed.occupancy(queuedBytes: queuedBytes) >= .red
    }

    public static func isQueueEviction(_ gap: GapRecord) -> Bool {
        gap.rangeDescription.hasPrefix(queueEvictionPrefix)
    }

    /// The queue-eviction gaps with a day range, which is what a re-export needs.
    public static func reExportableQueueGaps(_ gaps: [GapRecord]) -> [GapRecord] {
        gaps.filter {
            isQueueEviction($0) && $0.rangeStartDay != nil && $0.rangeEndDay != nil
        }
    }

    /// Whether this run evicted something from the queue that was not already a gap.
    public static func evictedDuringRun(gaps: [GapRecord], before: Set<BatchID>) -> Bool {
        gaps.contains { !before.contains($0.batchID) && isQueueEviction($0) }
    }

    /// A stop or purge drops what every sink was owed, so the ledger names them all.
    public static func owedDestinationLabel(_ destinationIDs: [String]) -> String {
        destinationIDs.isEmpty ? "no enabled destination" : destinationIDs.joined(separator: ",")
    }

    /// The first day a scope asks for, as a UTC day. A scope with no start never
    /// contributes history.
    static func startDay(_ scope: DestinationExportScope) -> String {
        String((scope.startInclusive ?? .distantFuture).ISO8601Format().prefix(10))
    }

    static func endDay(_ scope: DestinationExportScope) -> String? {
        scope.endExclusive.map {
            String($0.addingTimeInterval(-1).ISO8601Format().prefix(10))
        }
    }

    /// The window a new backfill job spans. Each sink carries its own window, so the
    /// job spans their union and the per-sink sweep drops the days that sink never
    /// asked for. `available` is the history Health holds per type; a type with none
    /// is skipped. Nil when nothing is left to backfill.
    public static func backfillWindow(
        scopes: [DestinationExportScope],
        available: [MetricID: ClosedRange<String>]
    ) -> BackfillWindow? {
        var metrics: [MetricID] = []
        var firstDay: String?
        var lastDay: String?
        for metric in Self.metrics(for: scopes) {
            guard let range = available[metric] else { continue }
            for scope in scopes where scope.metrics.contains(metric) {
                let lower = max(range.lowerBound, startDay(scope))
                let upper = min(range.upperBound, endDay(scope) ?? range.upperBound)
                guard lower <= upper else { continue }
                if !metrics.contains(metric) { metrics.append(metric) }
                firstDay = min(firstDay ?? lower, lower)
                lastDay = max(lastDay ?? upper, upper)
            }
        }
        guard let firstDay, let lastDay, !metrics.isEmpty else { return nil }
        return BackfillWindow(metrics: metrics, firstDay: firstDay, lastDay: lastDay)
    }
}

// MARK: Destination status after a run

/// Writes each destination's own result to its own status snapshot after a run (#42).
public struct ExportOutcomeRecorder: Sendable {
    private let snapshots: any DestinationStatusStore
    private let now: @Sendable () -> Date

    public init(snapshots: any DestinationStatusStore, now: @escaping @Sendable () -> Date) {
        self.snapshots = snapshots
        self.now = now
    }

    /// Applies each sink's own result to its own status, for a run that fanned one
    /// read out to several of them.
    ///
    /// A repair sweep writes the status of the destination it was constructed
    /// around, which is one of N. The others were delivered to in the same sweep,
    /// so leaving their status untouched left the widget and the destinations list
    /// showing a result from an earlier run, and a sink that was just repaired
    /// could still read as overdue. A sink with no row of its own keeps what it
    /// had, because nothing was attempted against it.
    public func apply(_ rows: [DestinationRunRow], to destinationIDs: [String]) {
        let epoch = now().timeIntervalSince1970
        for destinationID in destinationIDs {
            guard let row = rows.first(where: { $0.destinationID == destinationID }),
                  let kind = RunOutcome.Kind(rawValue: row.outcomeKind),
                  var snapshot = snapshots.read(destinationID: destinationID)
            else { continue }
            snapshot.applyLastOutcome(kind.rawValue)
            snapshot.errorClass = row.errorClass
            if ExportPlan.succeeded(kind) {
                snapshot.lastSuccessEpoch = epoch
            }
            snapshot.writtenAtEpoch = epoch
            try? snapshots.write(snapshot)
        }
    }

    /// At the end of an automatic run: each destination's own results across the
    /// types it was owed. A sink with no results of its own — one this trigger could
    /// only queue for — keeps the run's combined outcome, because nothing was attempted
    /// against it to say otherwise. A destination that could not be rebuilt already
    /// has its own failure recorded and is skipped.
    public func applyRunOutcome(
        planned: [String],
        unreconstructed: Set<String>,
        kindsByDestination: [String: [RunOutcome.Kind]],
        combined: RunOutcome.Kind
    ) throws {
        for destinationID in planned where !unreconstructed.contains(destinationID) {
            guard var snapshot = snapshots.read(destinationID: destinationID) else { continue }
            let own = kindsByDestination[destinationID].map(CombinedExportSummary.kind)
            snapshot.applyLastOutcome((own ?? combined).rawValue)
            snapshot.writtenAtEpoch = now().timeIntervalSince1970
            try snapshots.write(snapshot)
        }
    }

    /// UX-26: runs sealed after process death read as cancelled by the system.
    public func markInterrupted(_ destinationIDs: [String], atEpoch epoch: TimeInterval) throws {
        for destinationID in destinationIDs {
            guard var snapshot = snapshots.read(destinationID: destinationID) else { continue }
            snapshot.applyLastOutcome(RunOutcome.Kind.cancelledBySystem.rawValue)
            snapshot.errorClass = ErrorClass.cancelledBySystem.rawValue
            snapshot.writtenAtEpoch = epoch
            try snapshots.write(snapshot)
        }
    }

    /// The label a destination's status shows, or its ID when it has none yet.
    public func label(_ destinationID: String) -> String {
        snapshots.readAll().first { $0.destinationID == destinationID }?.destinationLabel
            ?? destinationID
    }
}

// MARK: Wipe

public enum ExportWipe {
    /// Everything the app keeps under Application Support that a wipe removes, beyond
    /// the state store the engine wipes itself.
    public static let applicationSupportArtifacts = [
        "exports",
        "scratch",
        "backfill-scratch",
        "demo-exports",
        "demo-scratch",
        "demo-state.sqlite",
        "demo-state.sqlite-shm",
        "demo-state.sqlite-wal",
        "https-destination.json",
        "home-assistant-destination.json",
        "mqtt-destination.json",
        "mqtt-client.p12",
        "imported-destination-drafts.json",
        "otlp-destination.json",
        "local-file-test.json",
        "local-export-folder.bookmark",
        "companion-test.json",
        "backfill-raw.json",
        "backfill-aggregate.json",
        "backfill-raw-manifest.json",
        "backfill-aggregate-manifest.json",
        "advisory-request-body",
        "exporter-id",
        "wake-ledger.log",
        "health-authorization.json",
        "network-activity.json",
    ]
}
