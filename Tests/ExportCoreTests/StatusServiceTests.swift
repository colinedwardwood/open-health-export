// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import CorrectnessEngine
import DestinationTrust
import EnginePorts
import Foundation
import NetEgress
import RunJournal
import TestSupport
import Testing
import Watchdog

// MARK: Fakes

private final class MemoryStatusStore: DestinationStatusStore, @unchecked Sendable {
    private let lock = NSLock()
    private var byID: [String: DestinationStatusSnapshot]

    init(_ snapshots: [DestinationStatusSnapshot] = []) {
        byID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.destinationID, $0) })
    }

    func readAll() -> [DestinationStatusSnapshot] {
        lock.withLock { byID.values.sorted { $0.destinationLabel < $1.destinationLabel } }
    }

    func read(destinationID: String) -> DestinationStatusSnapshot? {
        lock.withLock { byID[destinationID] }
    }

    func write(_ snapshot: DestinationStatusSnapshot) throws {
        lock.withLock { byID[snapshot.destinationID] = snapshot }
    }
}

private final class RecordingNotifier: StatusNotifier, @unchecked Sendable {
    private let lock = NSLock()
    private var _notices: [UserNotice] = []
    private var _rescheduled: [String] = []
    private var _widgetReloads: [String] = []
    var denied = false

    var notices: [UserNotice] { lock.withLock { _notices } }
    var rescheduled: [String] { lock.withLock { _rescheduled } }
    var widgetReloads: [String] { lock.withLock { _widgetReloads } }

    func notify(_ notice: UserNotice) async { lock.withLock { _notices.append(notice) } }
    func rescheduleOverdue(for snapshot: DestinationStatusSnapshot) async {
        lock.withLock { _rescheduled.append(snapshot.destinationID) }
    }
    func authorizationDenied() async -> Bool { denied }
    func reloadAllWidgets() { lock.withLock { _widgetReloads.append("all") } }
    func reloadStatusWidget() { lock.withLock { _widgetReloads.append("status") } }
}

private final class MemoryDenialMemory: NotificationDenialMemory, @unchecked Sendable {
    private let lock = NSLock()
    private var denied = false
    func previouslyDenied() -> Bool { lock.withLock { denied } }
    func setPreviouslyDenied(_ denied: Bool) { lock.withLock { self.denied = denied } }
}

private let statusNow = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01T00:00:00Z
private let nowEpoch = statusNow.timeIntervalSince1970

private struct Harness {
    let snapshots: MemoryStatusStore
    let notifier = RecordingNotifier()
    let memory = MemoryDenialMemory()
    let store = MemoryStateStore()
    let service: StatusService

    init(_ snapshots: [DestinationStatusSnapshot] = [], wakes: [WakeRecord] = []) {
        let snapshotStore = MemoryStatusStore(snapshots)
        self.snapshots = snapshotStore
        let store = self.store
        service = StatusService(
            snapshots: snapshotStore,
            notifier: notifier,
            denialMemory: memory,
            store: { store },
            wakes: { wakes },
            now: { statusNow },
            formatDate: { "t\(Int($0.timeIntervalSince1970))" }
        )
    }
}

private func snapshot(
    _ id: String,
    label: String? = nil,
    lastOutcome: String? = "success",
    lastSuccessEpoch: TimeInterval? = nil,
    errorClass: String? = nil,
    overdueAfter: TimeInterval? = nil,
    nextLatest: TimeInterval? = nil,
    securityEvents: Int = 0
) -> DestinationStatusSnapshot {
    DestinationStatusSnapshot(
        destinationID: id,
        destinationLabel: label,
        enabled: true,
        lastOutcome: lastOutcome,
        lastSuccessEpoch: lastSuccessEpoch,
        errorClass: errorClass,
        overdueThresholdSeconds: overdueAfter,
        nextAttemptLatestEpoch: nextLatest,
        unacknowledgedSecurityEventCount: securityEvents,
        writtenAtEpoch: 0
    )
}

// MARK: StatusService

@Test func statusServiceShowsEmptyCopyWithoutDestinations() {
    #expect(Harness().service.destinationStatusLines() == [DestinationStatusLine.emptyCopy])
}

@Test func statusServiceRendersOneLinePerDestination() {
    let harness = Harness([snapshot("https", label: "Server"), snapshot("mqtt", label: "Broker")])
    let lines = harness.service.destinationStatusLines()
    #expect(lines.count == 2)
    #expect(lines[0].contains("Broker"))
    #expect(lines[1].contains("Server"))
}

@Test func notificationErrorUsesTheNamedArchetypeAndTheDestinationLabel() {
    let harness = Harness([snapshot("mqtt", label: "Broker")])
    let error = harness.service.userFacingError(destinationID: "mqtt", archetype: .timeout)
    #expect(error?.archetype == .timeout)
    #expect(error?.destinationLabel == "Broker")
}

@Test func errorWithoutArchetypeComesFromTheSnapshotOrIsAbsent() {
    let harness = Harness([
        snapshot("https", lastOutcome: "failed", errorClass: "destinationUnreachable"),
        snapshot("files"),
    ])
    #expect(harness.service.userFacingError(destinationID: "https", archetype: nil) != nil)
    #expect(harness.service.userFacingError(destinationID: "files", archetype: nil) == nil)
    #expect(harness.service.userFacingError(destinationID: "missing", archetype: nil) == nil)
}

@Test func overdueBannerNamesOnlyDestinationsPastTheirDeadline() {
    let harness = Harness([
        snapshot("https", label: "Server", lastSuccessEpoch: nowEpoch - 7200, overdueAfter: 3600),
        snapshot("mqtt", label: "Broker", lastSuccessEpoch: nowEpoch - 60, overdueAfter: 3600),
    ])
    #expect(harness.service.overdueBannerDetail() == "Server. \(EscalationCopy.overdue)")
    #expect(Harness([snapshot("mqtt")]).service.overdueBannerDetail() == nil)
}

@Test func freshnessDisclosureFallsBackToEachClassTarget() {
    let lines = Harness().service.freshnessDisclosureLines()
    #expect(lines.map(\.id) == FreshnessClass.allCases.map { "freshness-class-\($0.rawValue)" })
    #expect(lines.map(\.text) == FreshnessClass.allCases.map { FreshnessTarget.classDisclosure($0) })
}

@Test func acknowledgingChangesClearsCountsAndRefreshesTheWidget() throws {
    let harness = Harness([snapshot("https", securityEvents: 2), snapshot("mqtt")])
    #expect(harness.service.destinationChangeBannerDetail() != nil)
    try harness.service.acknowledgeDestinationChanges()
    let https = try #require(harness.snapshots.read(destinationID: "https"))
    #expect(https.unacknowledgedSecurityEventCount == 0)
    #expect(https.writtenAtEpoch == nowEpoch)
    #expect(harness.snapshots.read(destinationID: "mqtt")?.writtenAtEpoch == 0)
    #expect(harness.service.destinationChangeBannerDetail() == nil)
    #expect(harness.notifier.widgetReloads == ["status"])
}

@Test func runFailureNoticeGoesToTheDestinationWithEvidence() async {
    let harness = Harness([
        snapshot("local-file"),
        snapshot("https", errorClass: "destinationUnreachable"),
    ])
    let label = await harness.service.notifyRunFailure(
        planned: ["local-file", "https"],
        label: { "label-\($0)" }
    )
    #expect(label == "label-https")
    let notice = try? #require(harness.notifier.notices.first)
    #expect(notice?.destinationID == "https")
    #expect(notice?.kind == .exportFailed)
    #expect(notice?.errorClass == "destinationUnreachable")
}

@Test func runFailureNoticeFallsBackToFirstPlannedAndSkipsWhenNoneArePlanned() async {
    let harness = Harness([snapshot("https", errorClass: "x")])
    #expect(await harness.service.notifyRunFailure(planned: ["mqtt", "companion"], label: { $0 }) == "mqtt")
    #expect(harness.notifier.notices.map(\.destinationID) == ["mqtt"])
    #expect(await harness.service.notifyRunFailure(planned: [], label: { $0 }) == nil)
    #expect(harness.notifier.notices.count == 1)
}

@Test func onlyFailedOutcomesNotify() async {
    let harness = Harness()
    await harness.service.notifyIfFailed(.success, destinationID: "https", destinationLabel: "Server")
    #expect(harness.notifier.notices.isEmpty)
    await harness.service.notifyIfFailed(.failed, destinationID: "https", destinationLabel: "Server")
    #expect(harness.notifier.notices.map(\.destination) == ["Server"])
}

@Test func failureSnapshotMarksOnlyThatDestination() throws {
    let harness = Harness([snapshot("https"), snapshot("mqtt")])
    harness.service.recordDestinationFailureSnapshot("https", errorClass: .destinationUnreachable)
    harness.service.recordDestinationFailureSnapshot("missing", errorClass: .destinationUnreachable)
    let https = try #require(harness.snapshots.read(destinationID: "https"))
    #expect(https.lastOutcome == RunOutcome.Kind.failed.rawValue)
    #expect(https.errorClass == ErrorClass.destinationUnreachable.rawValue)
    #expect(https.writtenAtEpoch == nowEpoch)
    #expect(harness.snapshots.read(destinationID: "mqtt")?.lastOutcome == "success")
    #expect(harness.snapshots.read(destinationID: "missing") == nil)
}

@Test func overdueReminderIsRescheduledForAKnownDestination() async {
    let harness = Harness([snapshot("https")])
    await harness.service.rescheduleOverdueNotification(destinationID: "https")
    await harness.service.rescheduleOverdueNotification(destinationID: "missing")
    #expect(harness.notifier.rescheduled == ["https"])
}

@Test func notificationDenialIsRecordedOnceAcrossLaunches() async throws {
    let harness = Harness([snapshot("https"), snapshot("mqtt", securityEvents: 1)])
    harness.notifier.denied = true
    try await harness.service.recordNotificationSuppressionIfNeeded()
    try await harness.service.recordNotificationSuppressionIfNeeded()
    let ledger = try await harness.store.transact { try $0.loadLedger() }
    #expect(ledger.map(\.outcomeKind) == ["security:notifications_denied"])
    #expect(ledger.first?.wallTimeEpoch == nowEpoch)
    #expect(harness.snapshots.read(destinationID: "https")?.unacknowledgedSecurityEventCount == 1)
    #expect(harness.snapshots.read(destinationID: "mqtt")?.unacknowledgedSecurityEventCount == 2)
    #expect(harness.notifier.widgetReloads == ["all"])
    #expect(harness.memory.previouslyDenied())
}

@Test func seededDenialRecordsEvenWhenRememberedAsDenied() async throws {
    let harness = Harness()
    harness.memory.setPreviouslyDenied(true)
    try await harness.service.recordNotificationSuppressionIfNeeded(forcedDenied: true)
    #expect(try await harness.store.transact { try $0.loadLedger() }.count == 1)
    harness.notifier.denied = false
    harness.memory.setPreviouslyDenied(true)
    try await harness.service.recordNotificationSuppressionIfNeeded()
    #expect(!harness.memory.previouslyDenied())
}

@Test func wakeAttributionNeedsAMeasuredDeadline() async throws {
    let none = try await Harness([snapshot("https")]).service.wakeAttributionLine()
    #expect(none == "Wake attribution: no measured delivery deadline is configured.")
    let pending = try await Harness([snapshot("https", nextLatest: nowEpoch + 600)])
        .service.wakeAttributionLine()
    let expected = WakeAttribution.classify(
        wakes: [],
        lastJournal: nil,
        nowEpoch: nowEpoch,
        expectedWakeByEpoch: nowEpoch + 600
    )
    #expect(pending == "Wake attribution: \(expected.userFacingCopy)")
}

// MARK: HistoryService

private func historyService(
    store: MemoryStateStore,
    seal: HashLedgerSeal = HashLedgerSeal(secret: "s"),
    sealURL: URL
) -> HistoryService {
    HistoryService(
        store: { store },
        seal: { seal },
        sealRecordURL: { sealURL },
        formatDate: { "t\(Int($0.timeIntervalSince1970))" }
    )
}

private func temporarySealURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-history-\(UUID().uuidString)")
        .appendingPathComponent("ledger-head-seal.json")
}

@Test func ledgerLinesLeadWithTheSealVerdictThenNewestEntries() async throws {
    let store = MemoryStateStore()
    let seal = HashLedgerSeal(secret: "s")
    let url = temporarySealURL()
    let service = historyService(store: store, seal: seal, sealURL: url)
    #expect(try await service.ledgerIntegrityLine() == "WARNING: ledger head has not been device-sealed")

    try await store.transact { tx in
        try tx.appendLedger(EgressEntry(destination: "https", sampleCount: 3, outcomeKind: "success", byteCount: 10, wallTimeEpoch: 100))
        try tx.appendLedger(EgressEntry(destination: "mqtt", sampleCount: 1, outcomeKind: "failed", byteCount: 5, wallTimeEpoch: 200))
    }
    let entries = try await store.transact { try $0.loadLedger() }
    try await LedgerHeadSealRecordFile.update(entries: entries, seal: seal, sealedAtEpoch: 1, url: url)

    let lines = try await service.ledgerLines()
    #expect(lines.count == 3)
    #expect(lines[0].hasPrefix("Chain and device seal valid · 2 entries · head "))
    #expect(lines[1] == "t200 · mqtt · failed · 1 records · 5 bytes")
    #expect(lines[2] == "t100 · https · success · 3 records · 10 bytes")

    let otherDevice = historyService(store: store, seal: HashLedgerSeal(secret: "other"), sealURL: url)
    #expect(try await otherDevice.ledgerIntegrityLine() == "WARNING: ledger identity changed")
}

@Test func ledgerIntegrityCopyCoversEveryVerdict() {
    #expect(HistoryService.integrityLine(.valid(head: LedgerChain.genesisHash, count: 0))
        == "Chain and device seal valid · 0 entries · head genesis")
    #expect(HistoryService.integrityLine(.chainInvalid(sequence: 4))
        == "WARNING: chain verification failed at sequence 4")
    #expect(HistoryService.integrityLine(.headMismatch) == "WARNING: sealed head does not match the ledger")
}

@Test func historyListsProblemsFirstAfterTheRetentionNote() async throws {
    let store = MemoryStateStore()
    let service = historyService(store: store, sealURL: temporarySealURL())
    #expect(try await service.historyLines() == [RunHistoryDetail.emptyStateCopy, RunHistoryDetail.retentionCopy])

    try await store.transact { tx in
        try tx.appendJournal(RunEvent(runID: RunID(rawValue: "ok"), outcomeKind: "success", detail: ""))
        try tx.appendJournal(RunEvent(runID: RunID(rawValue: "bad"), outcomeKind: "failed", detail: "x"))
    }
    let events = try await service.historyEvents()
    #expect(events.map(\.runID.rawValue) == ["bad", "ok"])
    let lines = try await service.historyLines()
    #expect(lines.first == RunHistoryDetail.retentionCopy)
    #expect(lines.count == 1 + events.flatMap { RunHistoryDetail.lines(for: $0) }.count)
}

@Test func browserSendStateReadsThroughTheStore() async throws {
    let store = MemoryStateStore()
    let service = historyService(store: store, sealURL: temporarySealURL())
    #expect(try await service.indexHorizonDay() == nil)
    #expect(try await service.sentThroughDay(metric: MetricID(rawValue: "heartRate")) == nil)
}

// MARK: TransparencyService

private func transparency(
    sources: DataFlowSources? = DataFlowSources(),
    store: (any StateStore)? = MemoryStateStore(),
    journal: DiagnosticJournal = DiagnosticJournal(events: [], degraded: [])
) -> TransparencyService {
    TransparencyService(
        sources: { sources },
        selectedTypeCount: { 7 },
        store: {
            guard let store else { throw CocoaError(.fileNoSuchFile) }
            return store
        },
        networkActivityURL: { throw CocoaError(.fileNoSuchFile) },
        diagnosticJournal: { _, _ in journal },
        marketingVersion: "1.2.3",
        build: BuildIdentity(sourceCommit: "abc1234", buildHash: "hash"),
        now: { statusNow },
        formatDate: { "t\(Int($0.timeIntervalSince1970))" }
    )
}

@Test func dataFlowHopsNameHostsAndCredentialKindsOnly() {
    let hops = TransparencyService.dataFlowHops(
        DataFlowSources(
            localFolder: .some("Health"),
            https: .init(urlString: "https://example.com:8443/ingest", allowInsecureHTTP: false, hasBearer: true),
            homeAssistant: .init(urlString: "http://ha.local/api/webhook/x", allowInsecureHTTP: true),
            mqtt: .init(urlString: "mqtts://broker", allowInsecure: false, hasClientCertificate: false, hasUsernameOrPassword: true),
            companionServiceName: "Colin's Mac",
            otlpURLString: "https://otel.example/v1/metrics"
        )
    )
    #expect(hops == [
        DataFlowHop(id: "local-file", host: "Files · Health", transport: "Local files", credential: DataFlowHop.noNetwork),
        DataFlowHop(id: "https", host: "example.com:8443", transport: "HTTPS", credential: DataFlowHop.bearerToken),
        DataFlowHop(id: "home-assistant", host: "ha.local", transport: "HTTP webhook", credential: DataFlowHop.webhookSecret),
        DataFlowHop(id: "mqtt", host: "broker", transport: "MQTTS", credential: DataFlowHop.usernamePassword),
        DataFlowHop(id: "companion", host: "Colin's Mac", transport: "Mac companion", credential: DataFlowHop.pairing),
        DataFlowHop(id: "otlp", host: "otel.example", transport: "OTLP HTTP", credential: DataFlowHop.noCredential),
    ])
    #expect(TransparencyService.dataFlowHops(DataFlowSources(localFolder: .some(nil)))[0].host == "Files")
    #expect(transparency(sources: nil).dataFlowHops().isEmpty)
    #expect(TransparencyService.dataFlowHost("not a url") == "not a url")
}

@Test func wipeInventoryCountsDestinationsCredentialsAndStoredRuns() async throws {
    let sources = DataFlowSources(
        localFolder: .some(nil),
        https: .init(urlString: "https://a", allowInsecureHTTP: false, hasBearer: true),
        mqtt: .init(urlString: "mqtt://b", allowInsecure: true, hasClientCertificate: false, hasUsernameOrPassword: false),
        otlpURLString: "https://otel/v1"
    )
    let store = MemoryStateStore()
    try await store.transact {
        try $0.appendJournal(RunEvent(runID: RunID(rawValue: "r"), outcomeKind: "success", detail: ""))
    }
    let inventory = await transparency(sources: sources, store: store).wipeInventory()
    #expect(inventory.destinationCount == 3)
    #expect(inventory.credentialCount == 1)
    #expect(inventory.runCount == 1)

    let noStore = await transparency(sources: sources, store: nil).wipeInventory()
    #expect(noStore == WipeInventory(destinationCount: 3, credentialCount: 1))
}

@Test func networkActivityLinesStartWithTheSelfReportedCaveat() {
    let empty = TransparencyService.networkActivityLines(rows: [], sourceCommit: "abc", formatDate: { _ in "" })
    #expect(empty == [EgressAttemptLog.selfReportedCaveat(sourceCommit: "abc"), EgressAttemptLog.emptyCopy])
    let row = NetworkActivityRow(host: "example.com", kinds: ["export"], count: 2, bytes: 40, firstSeenEpoch: 1, lastSeenEpoch: 2)
    let lines = TransparencyService.networkActivityLines(rows: [row], sourceCommit: "abc", formatDate: { "t\(Int($0.timeIntervalSince1970))" })
    #expect(lines.last == "example.com · 2 · 40 bytes · t1 → t2")
}

@Test func provenanceAndTypeCountComeFromInjectedValues() async {
    let service = transparency()
    let lines = service.buildProvenanceLines()
    #expect(lines.first == BuildIdentity.versionLine(version: "1.2.3", commit: "abc1234"))
    #expect(await service.dataFlowTypeCount() == 7)
}

@Test func diagnosticBundleCarriesTheInjectedHeader() throws {
    let bundle = try transparency().diagnosticBundle(
        environment: DiagnosticEnvironment(
            appVersion: "1.2.3",
            osVersion: "26.0",
            deviceModel: "iPhone",
            localeIdentifier: "en_US",
            utcOffsetMinutes: 60
        )
    )
    let text = String(decoding: bundle.payload, as: UTF8.self)
    #expect(text.contains("1.2.3"))
    #expect(text.contains("abc1234"))
    #expect(text.contains(statusNow.ISO8601Format()))
    #expect(!bundle.preview.isEmpty)
}
