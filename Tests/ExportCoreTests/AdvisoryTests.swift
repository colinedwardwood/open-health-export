// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CorrectnessEngine
import CoreDomain
import CoreTemporal
import DestinationTrust
import EnginePorts
import Foundation
import MetricCatalog
import NetEgress
import SinkLocalFile
import TestSupport
import Testing
import Watchdog
import WireFormat

private func emptyBodyFile() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-advisory-empty-\(UUID().uuidString)")
    try Data().write(to: url)
    return url
}

private func sampleFeed(seq: Int = 1, keyID: String = AdvisoryPinnedKeys.activeID) -> AdvisoryFeed {
    AdvisoryFeed(
        seq: seq,
        validFrom: "2026-01-01T00:00:00Z",
        expiresAt: "2026-12-31T00:00:00Z",
        keyID: keyID,
        items: [
            AdvisoryItem(
                id: "ADV-001",
                published: "2026-01-15T00:00:00Z",
                severity: "high",
                affected: "0.1–0.2",
                description: "Update before continuing to use MQTT over the public internet.",
                url: "https://github.com/colinedwardwood/open-health-export/security/advisories"
            )
        ]
    )
}

private let checkInstant = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-02T00:00:00Z

private actor ToggleDestinationSink: DestinationSink {
    private var failing = true

    func allowDelivery() {
        failing = false
    }

    func send(
        fileHandle: String,
        idempotencyKey: BatchID
    ) async throws -> DeliveryReceipt {
        if failing {
            throw DestinationSendError.destinationUnreachable
        }
        let text = try String(contentsOfFile: fileHandle, encoding: .utf8)
        return DeliveryReceipt(
            batchID: idempotencyKey,
            accepted: max(0, text.split(whereSeparator: \.isNewline).count - 2),
            statusOnly: false
        )
    }
}

@Test func hmacSHA256MatchesRFC4231Case1() {
    let key = Data(repeating: 0x0b, count: 20)
    let message = Data("Hi There".utf8)
    #expect(
        HMACSHA256.hex(key: key, message: message)
            == "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
    )
}

@Test func advisoryGoldenRequestMatchesCommittedFixture() throws {
    let request = try AdvisoryRequest.make(
        marketingVersion: "0.1.9+51",
        emptyBody: try emptyBodyFile()
    )
    let dump = try AdvisoryRequest.wireDump(request)
    let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("spec/v1.0.0/fixtures/advisory-golden-request.txt")
    let expected = String(decoding: try Data(contentsOf: fixture), as: UTF8.self)
    #expect(dump == expected)
    #expect(request.url.query == nil)
    #expect(request.method == "GET")
}

@Test func advisoryGoldenRequestRejectsQueryOrConditionalHeaders() throws {
    var request = try AdvisoryRequest.make(
        marketingVersion: "0.1.0",
        emptyBody: try emptyBodyFile()
    )
    request.headers["If-None-Match"] = "abc"
    #expect(throws: EgressError.transport("advisory request forbids if-none-match")) {
        _ = try AdvisoryRequest.wireDump(request)
    }
}

@Test func advisoryDocumentVerifiesActiveAndSuccessorKeys() throws {
    let active = try AdvisoryDocument.parse(
        try AdvisoryCanonical.envelopeJSON(sampleFeed()),
        lastSeenSeq: 0,
        now: checkInstant
    )
    #expect(active.seq == 1)
    #expect(active.items.count == 1)
    let successor = try AdvisoryDocument.parse(
        try AdvisoryCanonical.envelopeJSON(sampleFeed(seq: 2, keyID: AdvisoryPinnedKeys.successorID)),
        lastSeenSeq: 1,
        now: checkInstant
    )
    #expect(successor.keyID == AdvisoryPinnedKeys.successorID)
}

@Test func advisoryDocumentRejectsRollbackExpiryAndBehaviourFields() throws {
    #expect(throws: AdvisoryError.rollback) {
        _ = try AdvisoryDocument.parse(
            try AdvisoryCanonical.envelopeJSON(sampleFeed(seq: 1)),
            lastSeenSeq: 1,
            now: checkInstant
        )
    }
    #expect(throws: AdvisoryError.expired) {
        _ = try AdvisoryDocument.parse(
            try AdvisoryCanonical.envelopeJSON(sampleFeed()),
            lastSeenSeq: 0,
            now: Date(timeIntervalSince1970: 1_798_761_600) // 2027-01-01
        )
    }
    var json = String(decoding: try AdvisoryCanonical.envelopeJSON(sampleFeed()), as: UTF8.self)
    json = json.replacingOccurrences(
        of: "\"url\":",
        with: "\"disable_export\":true,\"url\":"
    )
    #expect(throws: AdvisoryError.extraField("disable_export")) {
        _ = try AdvisoryDocument.parse(Data(json.utf8), lastSeenSeq: 0, now: checkInstant)
    }
}

@Test func advisoryItemIsPresentationOnly() {
    let names = Mirror(reflecting: sampleFeed().items[0]).children.compactMap(\.label)
    #expect(names == ["id", "published", "severity", "affected", "description", "url"])
}

@Test func advisoryFetchIsLedgeredAndDisableable() async throws {
    let body = try AdvisoryCanonical.envelopeJSON(sampleFeed())
    let transport = RecordingHTTPTransport(response: OutboundHTTPResponse(status: 200, body: body))
    let store = MemoryStateStore()
    let result = try await AdvisoryClient.fetch(
        transport: transport,
        store: store,
        state: AdvisoryState(),
        now: checkInstant,
        marketingVersion: "0.1.0",
        foregroundVisible: true,
        emptyBody: try emptyBodyFile()
    )
    #expect(result.ledgerOutcome == "advisory:verified")
    #expect(result.presentation.fetched)
    #expect(result.state.lastSeenSeq == 1)
    let ledger = try await store.transact { try $0.loadLedger() }
    #expect(ledger.map(\.destination) == ["advisory:advisories.openhealthexporter.org"])
    #expect(await transport.requests.count == 1)

    let skipped = try await AdvisoryClient.fetch(
        transport: transport,
        store: store,
        state: AdvisoryState(enabled: false, lastVerifiedEpoch: checkInstant.timeIntervalSince1970),
        now: checkInstant,
        marketingVersion: "0.1.0",
        foregroundVisible: true,
        emptyBody: try emptyBodyFile()
    )
    #expect(skipped.ledgerOutcome == "advisory:disabled")
    #expect(skipped.presentation.banner?.hasPrefix("security advisories are off") == true)
    #expect(await transport.requests.count == 1)
}

@Test func backgroundWakeDoesNotFetchAdvisories() async throws {
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 200, body: Data())
    )
    let result = try await AdvisoryClient.fetch(
        transport: transport,
        store: MemoryStateStore(),
        state: AdvisoryState(),
        now: checkInstant,
        marketingVersion: "0.1.0",
        foregroundVisible: false,
        emptyBody: try emptyBodyFile()
    )
    #expect(result.ledgerOutcome == "advisory:not-due")
    #expect(await transport.requests.isEmpty)
}

@Test func exportSucceedsWhenAdvisoryEndpointIsBlackHoled() async throws {
    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-advisory-export-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    let run = ExportRun(
        source: CountingSource(),
        destination: .testing(LocalFileSink(directory: dest)),
        store: MemoryStateStore(),
        metric: MetricCatalog.heartRate.id,
        scratchDirectory: dest.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    )
    let export = try await run.run()
    #expect(export.kind == .success || export.kind == .successNothingDue)

    let failed = try await AdvisoryClient.fetch(
        transport: ForbiddenHTTPTransport(),
        store: MemoryStateStore(),
        state: AdvisoryState(),
        now: checkInstant,
        marketingVersion: "0.1.0",
        foregroundVisible: true,
        emptyBody: try emptyBodyFile()
    )
    #expect(failed.ledgerOutcome == "advisory:failed")
    #expect(failed.presentation.banner == AdvisoryStaleness.staleCopy)
    #expect(failed.presentation.fetched == false)
}

@Test func staleCopyDistinguishesSilenceFromSuppression() {
    let now = Date(timeIntervalSince1970: AdvisoryStaleness.freshWindow + 1)
    #expect(AdvisoryStaleness.isStale(lastVerified: Date(timeIntervalSince1970: 0), now: now))
    #expect(AdvisoryStaleness.staleCopy == "security advisories are stale")
}

@Test func provisionalFreshnessCopyNamesTheRatifiedFloorWithoutAPromise() {
    #expect(FreshnessTarget.alarmFloor == 6 * 60 * 60)
    #expect(FreshnessTarget.provisionalDisclosure.contains("6 hours"))
    #expect(FreshnessTarget.provisionalDisclosure.contains("not a delivery promise"))
    for freshnessClass in FreshnessClass.allCases {
        let line = FreshnessTarget.classDisclosure(freshnessClass)
        #expect(line.contains("Class \(freshnessClass.rawValue.uppercased())"))
        #expect(line.contains("pending R-71"))
        #expect(line.contains("not a delivery promise"))
    }
    let measured = FreshnessTarget.classDisclosure(.a, localP95: 4 * 3600)
    #expect(measured.contains("this device's p95 is 4"))
    #expect(measured.contains("The overdue alarm uses 8"))
}

@Test func shortcutExportRequiresDisclosureAndEnabledLocalArchive() {
    #expect(
        ShortcutExportAuthorization.denyReason(
            disclosureAcknowledged: false,
            localFileEnabled: false
        )?.contains("disclosure") == true
    )
    #expect(
        ShortcutExportAuthorization.denyReason(
            disclosureAcknowledged: true,
            localFileEnabled: false
        )?.contains("local archive") == true
    )
    #expect(
        ShortcutExportAuthorization.denyReason(
            disclosureAcknowledged: true,
            localFileEnabled: true
        ) == nil
    )
    #expect(RunTrigger.shortcut.rawValue == "shortcut")
}

@Test func overdueNotificationScheduleUsesLastSuccessAndNeverInventsAThreshold() {
    var snapshot = DestinationStatusSnapshot(
        destinationID: "local-file",
        enabled: true,
        lastSuccessEpoch: 1_000,
        writtenAtEpoch: 1_000
    )
    #expect(OverdueNotificationSchedule.fireEpoch(snapshot: snapshot) == nil)
    snapshot.overdueThresholdSeconds = 3_600
    #expect(OverdueNotificationSchedule.fireEpoch(snapshot: snapshot) == 4_600)
    snapshot.enabled = false
    #expect(OverdueNotificationSchedule.fireEpoch(snapshot: snapshot) == nil)
}

@Test func notificationSuppressionRecordsOnlyTheTransitionToDenied() {
    #expect(
        NotificationSuppression.shouldRecord(
            previouslyDenied: false,
            currentlyDenied: true
        )
    )
    #expect(
        !NotificationSuppression.shouldRecord(
            previouslyDenied: true,
            currentlyDenied: true
        )
    )
    #expect(
        !NotificationSuppression.shouldRecord(
            previouslyDenied: true,
            currentlyDenied: false
        )
    )
}

@Test func missedWindowsKeepOneOverdueDeadlineAndSuccessClearsStaleness() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-staleness-integration-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let snapshotURL = root.appendingPathComponent("status.json")
    try DestinationSnapshotFile.write(
        DestinationStatusSnapshot(
            destinationID: "test",
            enabled: true,
            state: .healthy,
            lastOutcome: "success",
            lastSuccessEpoch: 1_000,
            overdueThresholdSeconds: 100,
            writtenAtEpoch: 1_000
        ),
        to: snapshotURL
    )
    let initial = try DestinationSnapshotFile.read(from: snapshotURL)
    let initialDeadline = try #require(
        OverdueNotificationSchedule.fireEpoch(snapshot: initial)
    )
    #expect(initialDeadline == 1_100)

    let metric = MetricCatalog.heartRate.id
    let pages = (1 ... 3).map { index in
        SamplePage(
            samples: [
                SampleRecord(
                    key: RecordKey(uuid: String(format: "00000000-0000-4000-8000-%012d", index)),
                    metric: metric,
                    start: "2026-01-01T00:0\(index):00Z",
                    end: "2026-01-01T00:0\(index):00Z",
                    timeZoneOffsetMinutes: 0,
                    timeZoneSource: .unknown,
                    value: Double(70 + index),
                    unit: CanonicalUnit(symbol: "bpm"),
                    observedAt: "2026-01-01T00:0\(index):00Z"
                ),
            ],
            tombstones: [],
            metric: metric,
            anchorBlob: Data([UInt8(index)]),
            observedThrough: Date(timeIntervalSince1970: TimeInterval(index))
        )
    }
    let store = MemoryStateStore()
    let sink = ToggleDestinationSink()
    var registeredDeadlines: Set<TimeInterval> = [initialDeadline]
    for instant in [1_200.0, 1_250.0] {
        let outcome = try await ExportRun(
            source: FixtureSource(pages: pages),
            destination: .testing(sink),
            store: store,
            metric: metric,
            scratchDirectory: root.appendingPathComponent("scratch-\(Int(instant))"),
            envelope: testEnvelope(),
            clock: FrozenClock(instant: Date(timeIntervalSince1970: instant)),
            snapshotURL: snapshotURL
        ).run()
        #expect(outcome.kind == .failed)
        let snapshot = try DestinationSnapshotFile.read(from: snapshotURL)
        #expect(snapshot.state(at: instant) == .overdue)
        registeredDeadlines.insert(
            try #require(OverdueNotificationSchedule.fireEpoch(snapshot: snapshot))
        )
    }
    #expect(registeredDeadlines == [1_100])

    await sink.allowDelivery()
    let recoveredAt = 1_300.0
    let recovered = try await ExportRun(
        source: FixtureSource(pages: pages),
        destination: .testing(sink),
        store: store,
        metric: metric,
        scratchDirectory: root.appendingPathComponent("scratch-recovered"),
        envelope: testEnvelope(),
        clock: FrozenClock(instant: Date(timeIntervalSince1970: recoveredAt)),
        snapshotURL: snapshotURL
    ).run()
    #expect(recovered.kind == .success)
    let healthy = try DestinationSnapshotFile.read(from: snapshotURL)
    #expect(healthy.state(at: recoveredAt) == .healthy)
    #expect(OverdueNotificationSchedule.fireEpoch(snapshot: healthy) == 1_400)
}

@Test func watchdogEscalatesOnWidgetWhenNotificationsAreDenied() async throws {
    let snapshot = DestinationStatusSnapshot(
        destinationID: "local-file",
        destinationLabel: "This iPhone",
        enabled: true,
        state: .healthy,
        lastOutcome: "success",
        lastSuccessEpoch: 1_000,
        overdueThresholdSeconds: 100,
        writtenAtEpoch: 1_000
    )
    let now = FrozenClock(instant: Date(timeIntervalSince1970: 1_200)).now()
    let denied = Escalation.plan(
        snapshot: snapshot,
        now: now,
        notificationsAuthorized: false
    )
    #expect(denied.overdue)
    #expect(denied.notification == nil)
    #expect(denied.claimsNotificationBadge == false)
    #expect(denied.inAppCopy == EscalationCopy.overdueNotificationsOff)
    #expect(denied.widgetEntries.contains { $0.dateEpoch == 1_200 })
    let notifier = RecordingNotifier(authorizationDenied: true)
    #expect(try await Escalation.deliver(denied, notifier: notifier) == .skippedAuthorizationDenied)
    #expect(await notifier.notices.isEmpty)

    let allowed = Escalation.plan(
        snapshot: snapshot,
        now: now,
        notificationsAuthorized: true
    )
    #expect(allowed.notification?.kind == .exportOverdue)
    let posting = RecordingNotifier()
    #expect(try await Escalation.deliver(allowed, notifier: posting) == .posted)
    #expect(await posting.kinds == [.exportOverdue])
    #expect(
        NoticeCopy.render(allowed.notification!).title == "Export overdue"
    )
}
