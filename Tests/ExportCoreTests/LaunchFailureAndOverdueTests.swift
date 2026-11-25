// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import CorrectnessEngine
import DestinationTrust
import EnginePorts
import Foundation
import SinkLocalFile
import TestSupport
import Testing
import Watchdog

// MARK: #62 launch and background failures

private final class MemoryIssues: LaunchIssueMemory, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [LaunchIssue] = []
    func issues() -> [LaunchIssue] { lock.withLock { stored } }
    func save(_ issues: [LaunchIssue]) { lock.withLock { stored = issues } }
}

private struct Boom: Error {}

private func recorder(
    _ store: MemoryStateStore = MemoryStateStore(),
    memory: MemoryIssues = MemoryIssues(),
    open: Bool = true
) -> LaunchFailureRecorder {
    LaunchFailureRecorder(
        store: {
            if open { return store }
            throw Boom()
        },
        memory: memory,
        now: { Date(timeIntervalSince1970: 5_000) }
    )
}

@Test func launchFailureIsJournalledWithAnErrorClassAndRemembered() async {
    let store = MemoryStateStore()
    let memory = MemoryIssues()
    let recorded = await recorder(store, memory: memory)
        .record(.observerStart, error: Boom(), trigger: .launch)
    #expect(recorded == .internalFault)
    let event = store.transaction.journal.last
    #expect(event?.outcomeKind == "launch_failure")
    #expect(event?.errorClass == ErrorClass.internalFault.rawValue)
    #expect(event?.detail == LaunchStage.observerStart.rawValue)
    #expect(event?.trigger == .launch)
    #expect(event?.isProblemOutcome == true)
    #expect(memory.issues() == [
        LaunchIssue(stage: .observerStart, errorClass: "internalFault", atEpoch: 5_000),
    ])
}

@Test func aLockedKeychainIsADeferralClassifiedAsADeviceLock() async {
    #expect(LaunchFailureRecorder.isDeferral(SecretStoreError.locked))
    #expect(!LaunchFailureRecorder.isDeferral(SecretStoreError.notFound))
    #expect(!LaunchFailureRecorder.isDeferral(Boom()))
    #expect(LaunchFailureRecorder.errorClass(for: SecretStoreError.locked) == .deviceLocked)
    #expect(LaunchFailureRecorder.errorClass(for: DestinationSendError.lowPowerMode) == .lowPowerMode)
    let store = MemoryStateStore()
    await recorder(store).record(.observerExport, error: SecretStoreError.locked, trigger: .bgAppRefresh)
    #expect(store.transaction.journal.last?.errorClass == ErrorClass.deviceLocked.rawValue)
}

@Test func repeatedFailuresKeepOneIssuePerStageAndResolveClearsIt() async {
    let memory = MemoryIssues()
    let recorder = recorder(memory: memory)
    await recorder.record(.observerStart, error: Boom(), trigger: .launch)
    await recorder.record(.observerStart, error: Boom(), trigger: .launch)
    await recorder.record(.wakeLedger, error: Boom(), trigger: .launch)
    #expect(recorder.issues().count == 2)
    recorder.resolve(.observerStart)
    recorder.resolve(.observerStart)
    #expect(recorder.issues().map(\.stage) == [.wakeLedger])
}

@Test func anUnopenableJournalStillRemembersTheFailure() async {
    let memory = MemoryIssues()
    await recorder(memory: memory, open: false)
        .record(.queueExpiry, error: Boom(), trigger: .launch)
    #expect(memory.issues().map(\.stage) == [.queueExpiry])
}

@Test func statusShowsABannerForAnObserverRegistrationFailure() {
    let issue = LaunchIssue(stage: .observerStart, errorClass: "internalFault", atEpoch: 1)
    let notices = StatusNotices.notices(
        backgroundRefresh: .available, lowPowerMode: false, submitFailure: nil, issues: [issue]
    )
    #expect(notices.map(\.id) == ["launch-observer_start"])
    #expect(notices[0].detail.english.contains("Watching for new Health data failed."))
    #expect(notices[0].tone == .blocked)
    let locked = LaunchIssue(stage: .observerExport, errorClass: "deviceLocked", atEpoch: 2)
    let both = StatusNotices.notices(
        backgroundRefresh: .available, lowPowerMode: false, submitFailure: nil, issues: [issue, locked]
    )
    #expect(both.map(\.id) == ["launch-observer_export", "launch-observer_start"])
    #expect(both[0].tone == .attention)
    let unknown = LaunchIssue(stage: .queueExpiry, errorClass: "mystery", atEpoch: 3)
    let fallback = StatusNotices.notices(
        backgroundRefresh: .available, lowPowerMode: false, submitFailure: nil, issues: [unknown]
    )
    #expect(fallback[0].detail.english.contains("Open History"))
}

@Test func statusExplainsWhyBackgroundExportsCannotRun() {
    #expect(StatusNotices.notices(
        backgroundRefresh: .available, lowPowerMode: false, submitFailure: nil, issues: []
    ).isEmpty)
    let denied = StatusNotices.notices(
        backgroundRefresh: .denied, lowPowerMode: false, submitFailure: nil, issues: []
    )
    #expect(denied.map(\.id) == ["background-refresh"])
    #expect(denied[0].title.english == "Background App Refresh is off")
    let restricted = StatusNotices.notices(
        backgroundRefresh: .restricted, lowPowerMode: true, submitFailure: "refresh (code 1)", issues: []
    )
    #expect(restricted.map(\.id) == ["background-refresh", "low-power", "background-submit"])
    #expect(restricted[2].detail.english.contains("refresh (code 1)"))
    for stage in LaunchStage.allCases {
        #expect(!stage.label.english.isEmpty)
    }
}

// MARK: #63 overdue alarm blind spots

private let sixHours: TimeInterval = 6 * 3600

private func snapshot(
    enabledAt: TimeInterval?,
    lastSuccess: TimeInterval? = nil,
    overdue: TimeInterval? = 6 * 3600,
    role: DestinationExportRole = .designated,
    enabled: Bool = true
) -> DestinationStatusSnapshot {
    DestinationStatusSnapshot(
        destinationID: "https",
        enabled: enabled,
        exportRole: role,
        lastSuccessEpoch: lastSuccess,
        enabledAtEpoch: enabledAt,
        staleThresholdSeconds: overdue.map { $0 / 2 },
        overdueThresholdSeconds: overdue,
        writtenAtEpoch: 0
    )
}

@Test func aDestinationThatNeverSucceededAlarmsSixHoursAfterItWasEnabled() {
    let never = snapshot(enabledAt: 1_000)
    #expect(OverdueNotificationSchedule.fireEpoch(snapshot: never) == 1_000 + sixHours)
    let unmeasured = snapshot(enabledAt: 1_000, overdue: nil)
    #expect(OverdueNotificationSchedule.fireEpoch(snapshot: unmeasured) == 1_000 + sixHours)
    #expect(never.state(at: 1_000 + sixHours - 1) == .noExportsYet)
    #expect(never.state(at: 1_000 + sixHours) == .overdue)
    #expect(unmeasured.state(at: 1_000 + sixHours) == .overdue)
}

@Test func theAlarmCountsFromTheLaterOfEnablingAndTheLastSuccess() {
    let succeeded = snapshot(enabledAt: 1_000, lastSuccess: 9_000)
    #expect(OverdueNotificationSchedule.fireEpoch(snapshot: succeeded) == 9_000 + sixHours)
    let reEnabled = snapshot(enabledAt: 20_000, lastSuccess: 9_000)
    #expect(OverdueNotificationSchedule.fireEpoch(snapshot: reEnabled) == 20_000 + sixHours)
    let legacy = snapshot(enabledAt: nil, lastSuccess: 9_000)
    #expect(OverdueNotificationSchedule.fireEpoch(snapshot: legacy) == 9_000 + sixHours)
    #expect(OverdueNotificationSchedule.fireEpoch(snapshot: snapshot(enabledAt: nil)) == nil)
    #expect(snapshot(enabledAt: nil).alarmAnchorEpoch == nil)
    #expect(snapshot(enabledAt: nil, overdue: nil).effectiveOverdueThresholdSeconds == nil)
}

@Test func pausedAndManualOnlyDestinationsNeverAlarm() {
    #expect(OverdueNotificationSchedule.fireEpoch(snapshot: snapshot(enabledAt: 1, enabled: false)) == nil)
    #expect(OverdueNotificationSchedule.fireEpoch(snapshot: snapshot(enabledAt: 1, role: .manualOnly)) == nil)
}

@Test func theTimelineSchedulesAnOverdueEntryForANeverSucceededDestination() {
    let entries = DestinationTimelinePlanner.entries(
        snapshots: [snapshot(enabledAt: 1_000)], nowEpoch: 2_000
    )
    #expect(entries.map(\.dateEpoch).contains(1_000 + sixHours))
}

@Test func enablingADestinationStampsWhenItWasEnabled() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-enabled-\(UUID().uuidString)/status.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try DestinationSnapshotFile.recordSecurityEvents(
        1, destinationID: "https", writtenAtEpoch: 100, at: url
    )
    #expect(try DestinationSnapshotFile.read(from: url).enabledAtEpoch == 100)
    try DestinationSnapshotFile.recordSecurityEvents(
        1, destinationID: "https", enabled: true, writtenAtEpoch: 200, at: url
    )
    #expect(try DestinationSnapshotFile.read(from: url).enabledAtEpoch == 100)
    try DestinationSnapshotFile.recordSecurityEvents(
        1, destinationID: "https", enabled: false, writtenAtEpoch: 300, at: url
    )
    try DestinationSnapshotFile.recordSecurityEvents(
        1, destinationID: "https", enabled: true, writtenAtEpoch: 400, at: url
    )
    #expect(try DestinationSnapshotFile.read(from: url).enabledAtEpoch == 400)
}

private struct AlwaysLocked: SampleSource {
    func page(metric: MetricID, afterAnchor: Data?) async throws -> SamplePage {
        throw DestinationSendError.destinationUnreachable
    }
}

private func runOnce(
    source: any SampleSource,
    role: DestinationExportRole = .designated,
    snapshotURL: URL,
    root: URL
) async throws -> RunOutcome {
    let destination = RunDestination(
        id: "https",
        destination: .testing(LocalFileSink(directory: root)),
        role: role,
        snapshotURL: snapshotURL
    )
    let run = ExportRun(
        source: source,
        destination: .testing(LocalFileSink(directory: root)),
        store: MemoryStateStore(),
        metric: MetricID(rawValue: "heartRate"),
        scratchDirectory: root,
        destinationName: "https",
        envelope: testEnvelope(),
        trigger: .bgAppRefresh,
        snapshotURL: snapshotURL,
        destinations: [destination]
    )
    return try await run.run()
}

@Test func anAlwaysFailingDestinationKeepsItsEnabledAtAndAlarmsSixHoursLater() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-overdue-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("status.json")
    try DestinationSnapshotFile.write(
        snapshot(enabledAt: 1_000, overdue: nil), to: url
    )
    for _ in 0..<2 {
        _ = try? await runOnce(source: AlwaysLocked(), snapshotURL: url, root: root)
    }
    let written = try DestinationSnapshotFile.read(from: url)
    #expect(written.lastSuccessEpoch == nil)
    #expect(written.enabledAtEpoch == 1_000)
    #expect(OverdueNotificationSchedule.fireEpoch(snapshot: written) == 1_000 + sixHours)
}

@Test func aFirstSnapshotWithoutEnabledAtFallsBackToWhenItWasWritten() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-overdue-legacy-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("status.json")
    _ = try? await runOnce(source: AlwaysLocked(), snapshotURL: url, root: root)
    #expect(try DestinationSnapshotFile.read(from: url).enabledAtEpoch != nil)
    var legacy = snapshot(enabledAt: nil)
    legacy.writtenAtEpoch = 777
    try DestinationSnapshotFile.write(legacy, to: url)
    _ = try? await runOnce(source: AlwaysLocked(), snapshotURL: url, root: root)
    #expect(try DestinationSnapshotFile.read(from: url).enabledAtEpoch == 777)
}

@Test func anEmptyReadAdvancesTheSuccessClockButNothingOwedDoesNot() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-nothing-due-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let read = root.appendingPathComponent("read.json")
    let readOutcome = try await runOnce(source: FixtureSource(pages: []), snapshotURL: read, root: root)
    #expect(readOutcome.kind == .successNothingDue)
    #expect(readOutcome.readExecuted && readOutcome.advancesFreshness)
    #expect(try DestinationSnapshotFile.read(from: read).lastSuccessEpoch != nil)

    // Manual-only installs are owed nothing on a background trigger, so no read ran.
    let skipped = root.appendingPathComponent("skipped.json")
    let skippedOutcome = try await runOnce(
        source: FixtureSource(pages: []), role: .manualOnly, snapshotURL: skipped, root: root
    )
    #expect(skippedOutcome.kind == .successNothingDue)
    #expect(!skippedOutcome.readExecuted && !skippedOutcome.advancesFreshness)
    #expect(try DestinationSnapshotFile.read(from: skipped).lastSuccessEpoch == nil)
}

@Test func onlyDeliveryOrARealEmptyReadAdvancesFreshness() {
    #expect(RunOutcome.derive(from: RunTally(read: 1, committed: 1, acked: 1)).advancesFreshness)
    #expect(!RunOutcome.derive(from: RunTally(nothingDue: true)).advancesFreshness)
    #expect(RunOutcome.derive(from: RunTally(nothingDue: true, readExecuted: true)).advancesFreshness)
    #expect(!RunOutcome.derive(from: RunTally(failed: 1, terminalError: .internalFault)).advancesFreshness)
}
