// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CoreTemporal
import DiagnosticBundle
import DestinationTrust
import EnginePorts
import Foundation
import MetricCatalog
import NetEgress
import SinkLocalFile
import StorageSQLite
import TestSupport
import Testing
import Watchdog
import RunJournal
import Redaction
@testable import CorrectnessEngine
@testable import WireFormat

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private struct DeviceLockedSource: SampleSource {
    func page(metric: MetricID, afterAnchor: Data?) async throws -> SamplePage {
        throw DestinationSendError.deviceLocked
    }
}

@Test func errorClassManifestIsInBijectionWithTheEnum() {
    let keys = ErrorClass.allCases.map { ErrorClassManifest.record(for: $0).userCopyKey }
    #expect(Set(keys).count == ErrorClass.allCases.count)
    #expect(ErrorClassManifest.records.count == ErrorClass.allCases.count)
    for errorClass in ErrorClass.allCases {
        #expect(ErrorClassManifest.records[errorClass] != nil)
    }
    let copies = ErrorClass.allCases
        .map { ErrorClassManifest.record(for: $0).userFacingCopy }
        .filter { !$0.isEmpty }
    #expect(Set(copies).count == copies.count)
    #expect(
        ErrorClassManifest.record(for: .localNetworkDenied).userFacingCopy
            != ErrorClassManifest.record(for: .destinationUnreachable).userFacingCopy
    )
    #expect(!ErrorClassManifest.record(for: .deviceLocked).scheduleFailure)
    #expect(ErrorClassManifest.record(for: .budgetExhausted).scheduleFailure)
}

@Test func lockedStoreReadRecordsBlockedJournalOutcome() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-store-locked-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = MemoryStateStore()
    let run = ExportRun(
        source: DeviceLockedSource(),
        destination: .testing(LocalFileSink(directory: root)),
        store: store,
        metric: MetricCatalog.heartRate.id,
        scratchDirectory: root,
        envelope: testEnvelope(),
        trigger: .bgProcessing
    )

    let outcome = try await run.run()

    #expect(outcome.kind == .blockedDeviceLocked)
    let event = try #require(store.transaction.journal.last)
    #expect(event.outcomeKind == RunOutcome.Kind.blockedDeviceLocked.rawValue)
    #expect(event.errorClass == ErrorClass.deviceLocked.rawValue)
    #expect(event.trigger == .bgProcessing)
    #expect(store.transaction.pending.isEmpty)
}

@Test func lowPowerModeParksExportAsDeferredWithoutReadingHealth() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-low-power-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = MemoryStateStore()
    let snapshotURL = root.appendingPathComponent("status.json")
    let run = ExportRun(
        source: DeviceLockedSource(),
        destination: .testing(LocalFileSink(directory: root)),
        store: store,
        metric: MetricCatalog.heartRate.id,
        scratchDirectory: root,
        envelope: testEnvelope(),
        trigger: .bgProcessing,
        snapshotURL: snapshotURL,
        deferForLowPower: true
    )
    let outcome = try await run.run()
    #expect(outcome.kind == .blockedLowPower)
    let event = try #require(store.transaction.journal.last)
    #expect(event.outcomeKind == RunOutcome.Kind.blockedLowPower.rawValue)
    #expect(event.errorClass == ErrorClass.lowPowerMode.rawValue)
    let snapshot = try DestinationSnapshotFile.read(from: snapshotURL)
    #expect(snapshot.state == .deferred)
    #expect(snapshot.errorClass == ErrorClass.lowPowerMode.rawValue)
}

private struct HealthDataRestrictedSource: SampleSource {
    func page(metric: MetricID, afterAnchor: Data?) async throws -> SamplePage {
        throw DestinationSendError.healthDataRestricted
    }
}

@Test func restrictedStoreReadRecordsFailedPolicyOutcome() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-store-restricted-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = MemoryStateStore()
    let run = ExportRun(
        source: HealthDataRestrictedSource(),
        destination: .testing(LocalFileSink(directory: root)),
        store: store,
        metric: MetricCatalog.heartRate.id,
        scratchDirectory: root,
        envelope: testEnvelope(),
        trigger: .bgProcessing
    )
    let outcome = try await run.run()
    #expect(outcome.kind == .failed)
    let event = try #require(store.transaction.journal.last)
    #expect(event.errorClass == ErrorClass.healthDataRestricted.rawValue)
    #expect(store.transaction.pending.isEmpty)
}

@Test func diagnosticBundleIsBoundedManifestDerivedAndRedacted() throws {
    let canaries = RedactionCanary.tokens
    let canary = canaries.joined(separator: " ")
    let events = [
        RunEvent(
            runID: RunID(rawValue: canary),
            outcomeKind: "failed",
            detail: canary,
            trigger: .manual,
            samplesRead: 1
        ),
        RunEvent(
            runID: RunID(rawValue: "raw-health-type-heartRate"),
            outcomeKind: "success",
            detail: canary,
            trigger: .observerQuery,
            samplesRead: 2,
            samplesCommitted: 2,
            samplesAcked: 2
        ),
    ]
    let data = try BundleAssembler(maxRuns: 1).assemble(
        header: DiagnosticHeader(
            appVersion: "0.1.0",
            osVersion: "test",
            deviceModel: "test-device",
            localeIdentifier: "en_US",
            utcOffsetMinutes: 0,
            generatedAt: "2024-01-01T00:00:00Z"
        ),
        events: events
    )
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(text.contains("\"schema\":\"ohe.diagnostic/1\""))
    #expect(text.contains("\"runID\":\"bundle-run-1\""))
    #expect(text.contains("\"samplesAcked\":2"))
    for secret in canaries {
        #expect(!text.contains(secret))
    }
    #expect(!text.contains("heartRate"))
    #expect(!text.contains("\"detail\""))
    #expect(!text.contains("\"destination\""))
}

@Test func diagnosticSharePayloadDoesNotExistBeforeFullPreview() {
    let payload = Data("{\"schema\":\"ohe.diagnostic/1\"}".utf8)
    var gate = DiagnosticPreviewGate()
    #expect(gate.sharePayload == nil)
    gate.reachedEnd(of: payload)
    #expect(gate.sharePayload == payload)
}

@Test func diagnosticBundleRejectsContentAboveHardCap() {
    let event = RunEvent(
        runID: RunID(rawValue: "r"),
        outcomeKind: String(repeating: "x", count: 200),
        detail: ""
    )
    #expect(throws: DiagnosticBundleError.self) {
        _ = try BundleAssembler(maxRuns: 1, maxBytes: 10).assemble(
            header: DiagnosticHeader(
                appVersion: "0.1.0",
                osVersion: "test",
                deviceModel: "test",
                localeIdentifier: "en_US",
                utcOffsetMinutes: 0,
                generatedAt: "2024-01-01T00:00:00Z"
            ),
            events: [event]
        )
    }
}

@Test(arguments: [
    DiagnosticDegradation.networkUnavailable,
    .healthAuthorizationLimited,
    .destinationConfigurationInvalid,
])
func diagnosticBundleDoesNotDependOnTheDegradedSubsystem(
    _ degradation: DiagnosticDegradation
) throws {
    let data = try BundleAssembler().assemble(
        header: DiagnosticHeader(
            appVersion: "test",
            osVersion: "test",
            deviceModel: "test",
            localeIdentifier: "en_US_POSIX",
            utcOffsetMinutes: 0,
            generatedAt: "2024-01-01T00:00:00Z",
            degraded: [degradation.rawValue]
        ),
        events: [
            RunEvent(
                runID: RunID(rawValue: "degraded-run"),
                outcomeKind: "failed",
                detail: "intentionally excluded",
                errorClass: degradation.rawValue
            )
        ]
    )
    let object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let header = try #require(object["header"] as? [String: Any])
    let notes = try #require(header["degraded"] as? [String])
    #expect(!data.isEmpty)
    #expect(object["schema"] as? String == "ohe.diagnostic/1")
    #expect(notes == [degradation.rawValue])
    #expect((object["runs"] as? [[String: Any]])?.count == 1)
}

@Test func diagnosticBundleSurvivesAMissingDatabase() throws {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("missing-\(UUID().uuidString).sqlite").path
    let read = SQLiteDiagnosticReader.read(path: path)
    #expect(read.events.isEmpty)
    #expect(read.degraded.contains(DiagnosticDegradation.databaseUnreadable.rawValue))
    let data = try BundleAssembler().assemble(
        header: DiagnosticHeader(
            appVersion: "test",
            osVersion: "test",
            deviceModel: "test",
            localeIdentifier: "en_US_POSIX",
            utcOffsetMinutes: 0,
            generatedAt: "2024-01-01T00:00:00Z",
            degraded: read.degraded
        ),
        events: read.events
    )
    #expect(!data.isEmpty)
    #expect(
        String(decoding: data, as: UTF8.self)
            .contains(DiagnosticDegradation.databaseUnreadable.rawValue)
    )
}

@Test func diagnosticReaderUsesIndependentReadOnlyConnectionAndBoundsRuns() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-diagnostic-reader-\(UUID().uuidString).sqlite")
    do {
        let store = try SQLiteStateStore(path: url.path)
        for index in 0..<4 {
            try await store.transact { tx in
                try tx.appendJournal(
                    RunEvent(
                        runID: RunID(rawValue: "run-\(index)"),
                        outcomeKind: "success",
                        detail: "not included",
                        trigger: .launch,
                        samplesRead: index,
                        samplesCommitted: index,
                        samplesAcked: index
                    )
                )
            }
        }
    }
    let read = SQLiteDiagnosticReader.read(path: url.path, maxRuns: 2)
    #expect(read.events.map(\.runID.rawValue) == ["run-2", "run-3"])
    #expect(read.degraded.isEmpty)
    #expect(read.skippedRows == 0)
}

/// OBS-02, written to the requirement's own acceptance case: 1,200 runs over 120
/// simulated days. Both bounds are asserted and so is the footprint, because "bounded
/// on-disk footprint" is only a gate if it is a number.
@Test func journalRetentionHoldsOverTwelveHundredRunsAndStaysBounded() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-retention-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let day: TimeInterval = 24 * 60 * 60
    let totalDays = 120
    let runsPerDay = 10
    let now = TimeInterval(totalDays) * day

    do {
        let store = try SQLiteStateStore(path: url.path)
        // Oldest first, so the sweep has genuinely expired rows to find rather than
        // only ever seeing a table that was already inside the bound.
        for dayIndex in 0 ..< totalDays {
            let age = TimeInterval(totalDays - 1 - dayIndex) * day
            for slot in 0 ..< runsPerDay {
                try await store.transact { tx in
                    try tx.appendJournal(
                        RunEvent(
                            runID: RunID(rawValue: "run-\(dayIndex)-\(slot)"),
                            outcomeKind: "success",
                            detail: "",
                            trigger: .bgProcessing,
                            wallTimeEpoch: now - age
                        )
                    )
                }
            }
        }

        let retained = try await store.transact { tx in
            try tx.unprojectedJournal(limit: 10_000)
        }
        let cutoff = now - JournalRetention.seconds

        // 90 days at ten runs a day is the tighter bound here, so it is the one that
        // decides: days 0 through 90 inclusive survive, the other 29 do not.
        #expect(retained.count == (JournalRetention.days + 1) * runsPerDay)
        #expect(retained.count <= JournalRetention.runs)
        #expect(retained.allSatisfy { $0.wallTimeEpoch >= cutoff })
        // The newest run is never the one evicted.
        #expect(retained.contains { $0.runID.rawValue == "run-119-9" })
        #expect(!retained.contains { $0.runID.rawValue == "run-0-0" })
    }

    let size = try FileManager.default
        .attributesOfItem(atPath: url.path)[.size] as? Int ?? .max
    #expect(size <= 5 * 1024 * 1024, "journal reached \(size) bytes")
}

/// OBS-02's other half: the run-count bound has to bite when runs arrive faster than
/// the age bound can expire them, or a retry loop grows the store without limit.
@Test func journalRunCountBoundCapsABurstInsideTheAgeWindow() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-retention-burst-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let store = try SQLiteStateStore(path: url.path)
    let now: TimeInterval = 10_000_000

    // All within one hour, so nothing is old enough to expire by age.
    for index in 0 ..< (JournalRetention.runs + 200) {
        try await store.transact { tx in
            try tx.appendJournal(
                RunEvent(
                    runID: RunID(rawValue: "burst-\(index)"),
                    outcomeKind: "failed",
                    detail: "",
                    trigger: .bgProcessing,
                    wallTimeEpoch: now + TimeInterval(index),
                    errorClass: "destinationUnreachable"
                )
            )
        }
    }

    let retained = try await store.transact { tx in
        try tx.unprojectedJournal(limit: 10_000)
    }
    #expect(retained.count == JournalRetention.runs)
    #expect(retained.contains { $0.runID.rawValue == "burst-1199" })
    #expect(!retained.contains { $0.runID.rawValue == "burst-0" })
}

@Test func diagnosticWindowKeepsEveryRunInLastDayEvenAboveThirty() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-diagnostic-window-\(UUID().uuidString).sqlite")
    let now: TimeInterval = 2_000_000
    do {
        let store = try SQLiteStateStore(path: url.path)
        for index in 0..<45 {
            let inWindow = index >= 5
            try await store.transact { tx in
                try tx.appendJournal(
                    RunEvent(
                        runID: RunID(rawValue: "run-\(index)"),
                        outcomeKind: index == 44 ? "failed" : "success",
                        detail: "",
                        trigger: .launch,
                        wallTimeEpoch: inWindow ? now - TimeInterval(index) : now - 90_000,
                        errorClass: index == 44 ? "network" : nil
                    )
                )
            }
        }
    }

    let read = SQLiteDiagnosticReader.read(
        path: url.path,
        maxRuns: 30,
        windowSeconds: 86_400,
        nowEpoch: now
    )
    #expect(read.events.count == 40)
    #expect(read.events.first?.runID.rawValue == "run-5")
    #expect(read.events.last?.errorClass == "network")

    let generatedAt = Date(timeIntervalSince1970: now).ISO8601Format()
    let bundle = try BundleAssembler().assemble(
        header: DiagnosticHeader(
            appVersion: "test",
            osVersion: "test",
            deviceModel: "test",
            localeIdentifier: "en_US_POSIX",
            utcOffsetMinutes: 0,
            generatedAt: generatedAt
        ),
        events: read.events
    )
    let object = try #require(
        JSONSerialization.jsonObject(with: bundle) as? [String: Any]
    )
    let runs = try #require(object["runs"] as? [[String: Any]])
    #expect(runs.count == 40)
    #expect(runs.last?["errorClass"] as? String == "network")
}

@Test func diagnosticReaderSkipsMalformedRowsAndStillBuildsBundle() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-diagnostic-salvage-\(UUID().uuidString).sqlite")
    do {
        let store = try SQLiteStateStore(path: url.path)
        try await store.transact { tx in
            try tx.appendJournal(
                RunEvent(
                    runID: RunID(rawValue: "good"),
                    outcomeKind: "success",
                    detail: "",
                    trigger: .manual
                )
            )
            try tx.appendJournal(
                RunEvent(
                    runID: RunID(rawValue: "bad-trigger"),
                    outcomeKind: "failed",
                    detail: "",
                    trigger: .launch
                )
            )
        }
    }
    var bytes = try Data(contentsOf: url)
    let valid = Data("launch".utf8)
    let invalid = Data("bogus!".utf8)
    let range = try #require(bytes.range(of: valid))
    bytes.replaceSubrange(range, with: invalid)
    try bytes.write(to: url)

    let read = SQLiteDiagnosticReader.read(path: url.path)
    #expect(read.events.map(\.runID.rawValue) == ["good"])
    #expect(read.skippedRows == 1)
    #expect(read.degraded.contains("journal_rows_skipped=1"))
    let bundle = try BundleAssembler().assemble(
        header: DiagnosticHeader(
            appVersion: "1",
            osVersion: "1",
            deviceModel: "test",
            localeIdentifier: "en_US",
            utcOffsetMinutes: 0,
            generatedAt: "2024-01-01T00:00:00Z",
            degraded: read.degraded
        ),
        events: read.events
    )
    #expect(String(decoding: bundle, as: UTF8.self).contains("journal_rows_skipped=1"))
}

@Test func diagnosticReaderDegradesInsteadOfThrowingForUnreadableDatabase() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-diagnostic-broken-\(UUID().uuidString).sqlite")
    try Data("not a sqlite database".utf8).write(to: url)
    let read = SQLiteDiagnosticReader.read(path: url.path)
    #expect(read.events.isEmpty)
    #expect(read.degraded.contains("sqlite_integrity_check_failed"))
    #expect(read.degraded.contains("journal_unreadable"))
    let bundle = try BundleAssembler().assemble(
        header: DiagnosticHeader(
            appVersion: "test",
            osVersion: "test",
            deviceModel: "test",
            localeIdentifier: "en_US_POSIX",
            utcOffsetMinutes: 0,
            generatedAt: "2024-01-01T00:00:00Z",
            degraded: read.degraded
        ),
        events: read.events
    )
    #expect(!bundle.isEmpty)
    #expect(String(decoding: bundle, as: UTF8.self).contains("journal_unreadable"))
}

@Test func redactionManifestKeysAreUnique() {
    #expect(Set(Allowlist.manifest.map(\.key)).count == Allowlist.manifest.count)
    #expect(!Allowlist.permitted("metric", in: .bundle))
    #expect(Allowlist.permitted("outcome", in: .bundle))
}

@Test func haeEncoderDropsUuidAndRefusesTombstones() throws {
    let sample = heartSample("00000000-0000-0000-0000-000000000001")
    let json = try HAEWire.encode(
        samples: [sample],
        tombstones: [],
        metric: MetricID(rawValue: "heartRate"),
        acknowledgingLoss: HAELossAccepted()
    )
    let text = String(decoding: json, as: UTF8.self)
    #expect(!text.contains("00000000-0000-0000-0000-000000000001"))
    #expect(text.contains("\"date\":\"2024-01-01 00:00:00 +0000\""))
    #expect(text.contains("\"units\":\"bpm\""))
    #expect(throws: HAEError.tombstonesNotRepresentable) {
        _ = try HAEWire.encode(
            samples: [sample],
            tombstones: [TombstoneRecord(key: sample.key, metric: sample.metric)],
            metric: sample.metric,
            acknowledgingLoss: HAELossAccepted()
        )
    }
    #expect(throws: HAEError.unknownMetric) {
        _ = try HAEWire.encode(
            samples: [],
            tombstones: [],
            metric: MetricID(rawValue: "notAMetric"),
            acknowledgingLoss: HAELossAccepted()
        )
    }
}

@Test func haeCompatibilityCannotArmHonestySurfacesOrDisableNativeOutput() {
    #expect(
        ExportProfile.haeCompatibility.label
            == "compatibility export — correctness claims do not apply"
    )
    #expect(!ExportProfile.haeCompatibility.eligibleForHonestySurfaces)
    #expect(ExportProfile.native.eligibleForHonestySurfaces)
    #expect(
        ExportProfileSelection.enabled(requested: [.haeCompatibility])
            == [.native, .haeCompatibility]
    )
}

@Test func successRequiresAckedAtLeastRead() {
    let short = RunTally(read: 10, acked: 4, partialCause: "deferred_discretionary")
    let outcome = RunOutcome.derive(from: short)
    #expect(outcome.kind == .partial)
    #expect(outcome.partialCause == "deferred_discretionary")

    let ok = RunTally(read: 10, acked: 10)
    #expect(RunOutcome.derive(from: ok).kind == .success)
}

@Test func lockedDeviceIsNotFailed() {
    let tally = RunTally(terminalError: .deviceLocked)
    #expect(RunOutcome.derive(from: tally).kind == .blockedDeviceLocked)
}

@Test func webhookStatusOnlyIsSuccess() {
    let tally = RunTally(read: 3, acked: 3, ackEvidenceStatusOnly: true)
    let outcome = RunOutcome.derive(from: tally)
    #expect(outcome.kind == .success)
    #expect(outcome.ackEvidence == .statusOnly)
}

@Test func everyClosedRunOutcomeIsReachableFromATally() {
    let cases: [(RunTally, RunOutcome.Kind)] = [
        (RunTally(read: 2, acked: 2), .success),
        (RunTally(nothingDue: true), .successNothingDue),
        (RunTally(read: 4, acked: 1, partialCause: "receipt_short"), .partial),
        (RunTally(read: 4, acked: 0, unconfirmed: 4), .unknownAck),
        (RunTally(failed: 1, terminalError: .destinationUnreachable), .failed),
        (RunTally(terminalError: .budgetExhausted), .abandonedNoBudget),
        (RunTally(terminalError: .cancelledBySystem), .cancelledBySystem),
        (RunTally(terminalError: .deviceLocked), .blockedDeviceLocked),
        (RunTally(terminalError: .localNetworkDenied), .localNetworkDenied),
        (RunTally(terminalError: .lowPowerMode), .blockedLowPower),
        (RunTally(terminalError: .awaitingUnmetered), .blockedUnmetered),
    ]
    #expect(Set(cases.map(\.1)) == Set(RunOutcome.Kind.allCases))
    for (tally, kind) in cases {
        let outcome = RunOutcome.derive(from: tally)
        #expect(outcome.kind == kind)
        if kind == .partial {
            #expect(outcome.partialCause != nil)
            #expect(!(outcome.partialCause ?? "").isEmpty)
        }
        #expect(outcome.kind != .success || tally.acked >= tally.read)
    }
}

@Test func silentBodyDiscardNeverDerivesSuccess() {
    let discarded = RunTally(read: 5, acked: 0, ackEvidenceStatusOnly: true)
    let outcome = RunOutcome.derive(from: discarded)
    #expect(outcome.kind != .success)
    #expect(outcome.kind != .successNothingDue)
    #expect(outcome.kind == .partial)
    #expect(outcome.partialCause == "unspecified")
}

@Test func randomAckCountsNeverSucceedWhenTheDestinationReadsFewerThanItSent() {
    var seed: UInt64 = 0xC0FFEE
    func next(_ bound: Int) -> Int {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1
        return Int(seed % UInt64(bound))
    }
    for _ in 0..<10_000 {
        let read = next(32)
        let acked = next(read + 1)
        let unconfirmed = next(8)
        let tally = RunTally(read: read, acked: acked, unconfirmed: unconfirmed)
        let outcome = RunOutcome.derive(from: tally)
        if acked < read {
            #expect(outcome.kind != .success)
            #expect(outcome.kind != .successNothingDue)
        }
        if outcome.kind == .partial {
            #expect(outcome.partialCause == "unspecified")
        }
    }
}

@Test func exportRunMapsLocalNetworkDeniedAndSilentDiscardToClosedOutcomes() async throws {
    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-r21-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

    let denied = ExportRun(
        source: CountingSource(),
        destination: .testing(ThrowingSink(error: .localNetworkDenied)),
        store: MemoryStateStore(),
        metric: MetricCatalog.heartRate.id,
        scratchDirectory: dest.appendingPathComponent("denied"),
        envelope: testEnvelope()
    )
    let deniedOutcome = try await denied.run()
    #expect(deniedOutcome.kind == .localNetworkDenied)

    let discarded = ExportRun(
        source: CountingSource(),
        destination: .testing(SilentDiscardSink()),
        store: MemoryStateStore(),
        metric: MetricCatalog.heartRate.id,
        scratchDirectory: dest.appendingPathComponent("discard"),
        envelope: testEnvelope()
    )
    let discardedOutcome = try await discarded.run()
    #expect(discardedOutcome.kind == .partial)
    #expect(discardedOutcome.kind != .success)
}

@Test func p16DefaultLocalFileExportMakesNoAttributableNetworkDials() async throws {
    let recorder = EgressAttemptLog.Recorder()
    try await EgressAttemptLog.$recorder.withValue(recorder) {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohe-r52-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let run = ExportRun(
            source: CountingSource(),
            destination: .testing(LocalFileSink(directory: dest)),
            store: MemoryStateStore(),
            metric: MetricCatalog.heartRate.id,
            scratchDirectory: dest.appendingPathComponent("scratch"),
            envelope: testEnvelope()
        )
        _ = try await run.run()
        #expect(recorder.snapshot().isEmpty)
    }
}

@Test func urlSessionTransportRecordsTheHostBeforeAnyBytesMove() async {
    let recorder = EgressAttemptLog.Recorder()
    await EgressAttemptLog.$recorder.withValue(recorder) {
        let body = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohe-r52-body-\(UUID().uuidString)")
        try? Data().write(to: body)
        let transport = URLSessionHTTPTransport()
        do {
            _ = try await transport.execute(
                OutboundHTTPRequest(
                    method: "POST",
                    url: URL(string: "https://127.0.0.1:1/r52")!,
                    headers: [:],
                    bodyFile: body
                )
            )
        } catch {
            _ = error
        }
        #expect(recorder.snapshot() == [EgressAttempt(kind: .http, host: "127.0.0.1")])
    }
}

@Test func networkActivityLedgerKeepsHostsCountsBytesAndSelfReportedCaveat() throws {
    final class Epoch: @unchecked Sendable {
        var value: TimeInterval = 1_000
    }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-ux49-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let epoch = Epoch()
    let store = EgressAttemptLog.PersistentStore(url: url, nowEpoch: { epoch.value })
    EgressAttemptLog.attachPersistent(store)
    defer { EgressAttemptLog.wipePersistent() }

    EgressAttemptLog.record(kind: .http, host: "ha.example", bytes: 40)
    epoch.value = 1_100
    EgressAttemptLog.record(kind: .http, host: "ha.example", bytes: 60)
    EgressAttemptLog.record(kind: .byteStream, host: "broker.example", bytes: 12)
    EgressAttemptLog.record(kind: .discovery, host: "_ohe-companion._tcp")

    let rows = EgressAttemptLog.persistentSnapshot()
    #expect(rows.map(\.host) == ["_ohe-companion._tcp", "broker.example", "ha.example"])
    let ha = try #require(rows.first { $0.host == "ha.example" })
    #expect(ha.count == 2)
    #expect(ha.bytes == 100)
    #expect(ha.firstSeenEpoch == 1_000)
    #expect(ha.lastSeenEpoch == 1_100)
    let caveat = EgressAttemptLog.selfReportedCaveat(sourceCommit: "abc1234")
    #expect(caveat.contains("own network use"))
    #expect(caveat.contains("abc1234"))
    #expect(caveat.contains("proxy"))

    let reloaded = EgressAttemptLog.PersistentStore(url: url, nowEpoch: { 2_000 }).snapshot()
    #expect(reloaded.map(\.host) == rows.map(\.host))
}

@Test func buildProvenanceNamesVersionCommitAndSourceLink() {
    #expect(BuildIdentity.versionLine(version: "0.1.0", commit: "deadbeef") == "Version 0.1.0 · deadbeef")
    #expect(
        BuildIdentity.sourceLink(commit: "c0ffee1234567890")
            == "https://github.com/colinedwardwood/open-health-export/commit/c0ffee1234567890"
    )
    #expect(BuildIdentity.sourceLink(commit: "unspecified") == nil)
}

@Test func hkStatisticsExceptionListIsNonEmpty() {
    #expect(MetricCatalog.hkStatisticsExceptions.contains(MetricCatalog.stepCount.id))
}

@Test func homeAssistantMappingOmitsGuessedDeviceClassesAndForbidsSilentStatistics() throws {
    let measurementForbidden: Set<String> = [
        "date", "enum", "energy", "gas", "monetary", "timestamp", "volume", "water",
    ]
    #expect(MetricCatalog.all.count == 38)
    #expect(MetricCatalog.height.haUnit == "cm")
    #expect(MetricCatalog.height.haDeviceClass == "distance")
    #expect(MetricCatalog.bodyFatPercentage.haDeviceClass == nil)
    #expect(MetricCatalog.bodyMassIndex.haUnit == nil)
    #expect(MetricCatalog.bloodGlucose.wireUnit == "mg/dL")
    #expect(MetricCatalog.bloodGlucose.haDeviceClass == "blood_glucose_concentration")
    #expect(MetricCatalog.vo2Max.sensitivity == .sensitive)
    for declaration in MetricCatalog.all {
        if let deviceClass = declaration.haDeviceClass, measurementForbidden.contains(deviceClass) {
            #expect(declaration.haStateClass != "measurement")
        }
        if declaration.haDeviceClass == "enum" {
            #expect(declaration.haStateClass == nil)
        }
    }
    #expect(MetricCatalog.stepCount.haUnit == "steps")
    #expect(MetricCatalog.stepCount.haDeviceClass == nil)
    #expect(MetricCatalog.stepCount.haStateClass == "total_increasing")
    #expect(MetricCatalog.stepCount.haRequiresAggregate)
    #expect(MetricCatalog.heartRate.haDeviceClass == nil)
    #expect(MetricCatalog.heartRate.haStateClass == "measurement")
    #expect(MetricCatalog.activeEnergy.haDeviceClass == nil)
    #expect(MetricCatalog.activeEnergy.haStateClass == "total_increasing")
    #expect(MetricCatalog.basalEnergy.haDeviceClass == nil)
    #expect(MetricCatalog.oxygenSaturation.haDeviceClass == nil)
    #expect(MetricCatalog.bodyMass.sensitivity == .sensitive)
    let json = try HADiscovery.encodeDeviceConfig(
        exporterId: "6b1c2d3e",
        metrics: [MetricCatalog.stepCount.id, MetricCatalog.heartRate.id]
    )
    let text = String(decoding: json, as: UTF8.self)
    #expect(!text.contains("\"qty\""))
    #expect(!text.contains("\"uuid\""))
    #expect(!text.contains("\"device_class\""))
    #expect(text.contains("\"state_class\":\"total_increasing\""))
    #expect(text.contains("\"state_class\":\"measurement\""))
    #expect(text.contains("\"unit_of_measurement\":\"steps\""))
    #expect(HADiscovery.retainAllowed(
        topic: try HADiscovery.deviceConfigTopic(exporterId: "6b1c2d3e"),
        payload: json
    ))
    #expect(!HADiscovery.retainAllowed(topic: "ohe/health", payload: json))
    let state = try HAState.encode(
        HAStatePoint(
            value: 72,
            timeZoneIdentifier: "UTC",
            sampleCount: 4,
            state: "open",
            computation: "mean"
        )
    )
    let stateText = String(decoding: state, as: UTF8.self)
    #expect(stateText.contains("\"value\":72"))
    #expect(!stateText.contains("uuid"))
    #expect(!stateText.contains("qty"))
    let stateTopic = try HAState.topic(
        exporterId: "6b1c2d3e",
        wireId: "heart_rate",
        statistic: "mean",
        granularity: "PT1H"
    )
    #expect(!HADiscovery.retainAllowed(topic: stateTopic, payload: state))
}

@Test func homeAssistantDiscoveryContractIsGeneratedForEveryCatalogueMetric() throws {
    #expect(Set(MetricCatalog.all.map(\.id)).count == MetricCatalog.all.count)
    #expect(Set(MetricCatalog.all.map(\.wireId)).count == MetricCatalog.all.count)
    #expect(Set(MetricCatalog.all.map(\.hkIdentifier)).count == MetricCatalog.all.count)

    let data = try HADiscovery.encodeDeviceConfig(
        exporterId: "device-1234",
        metrics: MetricCatalog.all.map(\.id)
    )
    let root = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let components = try #require(root["cmps"] as? [String: Any])
    #expect(components.count == MetricCatalog.all.count)

    for declaration in MetricCatalog.all {
        let statistic = declaration.cumulative ? "sum" : "mean"
        let granularity = declaration.cumulative ? "P1D" : "PT1H"
        let key = "\(declaration.wireId)_\(statistic)_\(granularity.lowercased())"
        let component = try #require(components[key] as? [String: Any])
        #expect(component["p"] as? String == "sensor")
        #expect(
            component["state_topic"] as? String
                == "ohe/device-1234/v1/state/\(declaration.wireId)/\(statistic)/\(granularity)"
        )
        #expect(component["availability_topic"] as? String == "ohe/device-1234/v1/status")
        #expect(component["unit_of_measurement"] as? String == declaration.haUnit)
        #expect(component["device_class"] as? String == declaration.haDeviceClass)
        #expect(component["state_class"] as? String == declaration.haStateClass)
    }
}

@Test func homeAssistantDiscoveryOmitsCategoryAndWorkoutFamilies() throws {
    let data = try HADiscovery.encodeDeviceConfig(
        exporterId: "device-1234",
        metrics: [
            MetricCatalog.stepCount.id,
            MetricCatalog.sleepAnalysis.id,
            MetricCatalog.workout.id,
        ]
    )
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let components = try #require(root["cmps"] as? [String: Any])
    #expect(components.count == 1)
    #expect(components.keys.contains { $0.hasPrefix("step_count_") })
    #expect(!components.keys.contains { $0.contains("sleep") })
    #expect(!components.keys.contains { $0.contains("workout") })
}

@Test func injectedTzDatabaseIdentityIsCommitted2024a() throws {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("spec/v1.0.0/fixtures/tz-database-version.txt")
    let version = try String(contentsOf: url, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(version == "2024a")
    let utc = TemporalContext(
        timeZoneIdentifier: "UTC",
        localeIdentifier: "en_US_POSIX",
        tzDatabaseVersion: version
    )
    let fixed = TemporalContext(
        timeZoneIdentifier: "Etc/GMT-5",
        localeIdentifier: "en_US_POSIX",
        tzDatabaseVersion: version
    )
    let date = Date(timeIntervalSince1970: 1_704_067_200)
    #expect(DayBucket.containing(date, context: utc) == DayBucket(year: 2024, month: 1, day: 1))
    let utcBounds = try #require(BucketKey.boundsP1D(day: "2024-01-01", context: utc))
    let fixedBounds = try #require(BucketKey.boundsP1D(day: "2024-01-01", context: fixed))
    #expect(utcBounds.bucketDurationSeconds == 24 * 60 * 60)
    #expect(fixedBounds.bucketDurationSeconds == 24 * 60 * 60)
    #expect(utcBounds.bucketStart == "2024-01-01T00:00:00.000Z")
    #expect(utcBounds.bucketEnd == "2024-01-02T00:00:00.000Z")
}

@Test func dayBucketIsDeterministicUnderFrozenClock() {
    let date = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 00:00 UTC
    let context = TemporalContext(
        timeZoneIdentifier: "UTC",
        localeIdentifier: "en_US_POSIX",
        tzDatabaseVersion: "2024a"
    )
    let bucket = DayBucket.containing(date, context: context)
    #expect(bucket == DayBucket(year: 2024, month: 1, day: 1))
}

@Test func dailyBucketBoundsCoverSpringAndFallDSTExactly() throws {
    let context = TemporalContext(
        timeZoneIdentifier: "America/New_York",
        localeIdentifier: "en_US_POSIX",
        tzDatabaseVersion: "fixture-2024"
    )
    let spring = try #require(BucketKey.boundsP1D(day: "2024-03-10", context: context))
    #expect(spring.bucketDurationSeconds == 23 * 60 * 60)
    #expect(spring.bucketStart == "2024-03-10T05:00:00.000Z")
    #expect(spring.bucketEnd == "2024-03-11T04:00:00.000Z")

    let fall = try #require(BucketKey.boundsP1D(day: "2024-11-03", context: context))
    #expect(fall.bucketDurationSeconds == 25 * 60 * 60)
    #expect(fall.bucketStart == "2024-11-03T04:00:00.000Z")
    #expect(fall.bucketEnd == "2024-11-04T05:00:00.000Z")
}

@Test func machineBucketOutputIgnoresHostileDisplayLocale() throws {
    let english = TemporalContext(
        timeZoneIdentifier: "Asia/Kathmandu",
        localeIdentifier: "en_US_POSIX",
        tzDatabaseVersion: "fixture-2024"
    )
    let arabic = TemporalContext(
        timeZoneIdentifier: "Asia/Kathmandu",
        localeIdentifier: "ar_EG",
        tzDatabaseVersion: "fixture-2024"
    )
    #expect(
        BucketKey.boundsP1D(day: "2024-06-01", context: english)
            == BucketKey.boundsP1D(day: "2024-06-01", context: arabic)
    )
}

@Test func nativeWireEncodingIsByteIdenticalAcrossOneHundredRuns() throws {
    let payload = try NativeWire.encode(
        samples: [heartSample("00000000-0000-0000-0000-000000000084")],
        tombstones: [],
        metric: MetricCatalog.heartRate.id,
        batchID: BatchID(rawValue: "00000000-0000-4000-8000-000000000084"),
        envelope: testEnvelope()
    )
    for _ in 0..<100 {
        #expect(
            try NativeWire.encode(
                samples: [heartSample("00000000-0000-0000-0000-000000000084")],
                tombstones: [],
                metric: MetricCatalog.heartRate.id,
                batchID: BatchID(rawValue: "00000000-0000-4000-8000-000000000084"),
                envelope: testEnvelope()
            ) == payload
        )
    }
}

@Test func memoryStoreCannotAdvanceCursorWithoutCommitBatch() async throws {
    let store = MemoryStateStore()
    let page = SamplePage(
        samples: [],
        tombstones: [],
        metric: MetricID(rawValue: "heartRate"),
        anchorBlob: Data([1]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    try await store.transact { tx in
        try tx.commitBatch(
            PendingBatch(id: BatchID(rawValue: "b1"), payloadURL: "file://tmp"),
            advancing: CursorAdvance(page: page, epoch: 1)
        )
    }
    #expect(store.transaction.cursors[MetricID(rawValue: "heartRate")]?.epoch == 1)
    #expect(try store.transaction.pendingBatches().map(\.id.rawValue) == ["b1"])
}

@Test func sqliteJournalRoundTrip() async throws {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-test-\(UUID().uuidString).sqlite")
        .path
    let store = try SQLiteStateStore(path: path)
    try await store.transact { tx in
        try tx.appendJournal(RunEvent(runID: RunID(rawValue: "r1"), outcomeKind: "success", detail: ""))
    }
}

@Test func nativeWireIsStableForFixedRecord() throws {
    let sample = SampleRecord(
        key: RecordKey(uuid: "00000000-0000-0000-0000-000000000001"),
        metric: MetricID(rawValue: "heartRate"),
        start: "2024-01-01T00:00:00Z",
        end: "2024-01-01T00:00:00Z",
        timeZoneOffsetMinutes: 0,
        timeZoneSource: .unknown,
        value: 60,
        unit: CanonicalUnit(symbol: "count/min"),
        observedAt: "2024-01-01T00:00:00Z"
    )
    let envelope = testEnvelope()
    let line = try NativeWire.encode(sample, envelope: envelope)
    #expect(line.contains("\"uuid\":\"00000000-0000-0000-0000-000000000001\""))
    #expect(line.contains("\"kind\":\"sample.quantity\""))
    #expect(line.contains("\"metricId\":\"heart_rate\""))
    #expect(line.contains("\"spec\"") == false)
    let batch = try NativeWire.encode(
        samples: [sample],
        tombstones: [
            TombstoneRecord(
                key: RecordKey(uuid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"),
                metric: MetricID(rawValue: "heartRate")
            )
        ],
        metric: MetricID(rawValue: "heartRate"),
        batchID: BatchID(rawValue: "0192f3c1-0000-0000-0000-000000000001"),
        envelope: envelope
    )
    let text = String(decoding: batch, as: UTF8.self)
    let ndjson = text.split(whereSeparator: \.isNewline).map(String.init)
    #expect(ndjson.count == 4)
    #expect(ndjson[0].contains("\"kind\":\"batch.header\""))
    #expect(ndjson[0].contains("\"spec\":\"ohe.wire/1\""))
    #expect(ndjson[1].contains("\"kind\":\"sample.quantity\""))
    #expect(ndjson[2].contains("\"kind\":\"tombstone\""))
    #expect(ndjson[2].contains("\"bestEffort\":true"))
    #expect(ndjson[3].contains("\"kind\":\"batch.footer\""))
    #expect(ndjson[3].contains("\"contentDigest\":\"sha256:"))
    let body = ndjson[1] + "\n" + ndjson[2] + "\n"
    #expect(ndjson[3].contains(SHA256.hex(Data(body.utf8))))
}

@Test func sha256MatchesFIPSVectors() {
    #expect(SHA256.hex(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    #expect(SHA256.hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

@Test func anchorTokenEnvelopeRejectsGarbage() {
    #expect(throws: AnchorTokenError.corrupt) {
        _ = try AnchorToken.fromEnvelope(Data("nope".utf8))
    }
    let token = AnchorToken(format: 1, bytes: Data([1, 2, 3]))
    let restored = try? AnchorToken.fromEnvelope(token.envelope())
    #expect(restored?.bytes == Data([1, 2, 3]))
    #expect(restored?.format == 1)
}

@Test func watchdogEscalatesWhenLastSuccessIsOld() {
    let policy = StalenessPolicy(defaultInterval: 3600)
    let now = Date(timeIntervalSince1970: 10_000)
    let last = Date(timeIntervalSince1970: 100)
    #expect(policy.shouldEscalate(lastSuccess: last, now: now))
    #expect(!policy.shouldEscalate(lastSuccess: now, now: now))
    #expect(!StalenessPolicy().shouldEscalate(lastSuccess: nil, now: now))
}

@Test func destinationSnapshotRoundTripsWithoutSqlite() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-snap-\(UUID().uuidString)")
        .appendingPathComponent("status.json")
    let snapshot = DestinationStatusSnapshot(
        destinationID: "local-file",
        enabled: true,
        lastOutcome: "success",
        lastSuccessEpoch: 1_000,
        writtenAtEpoch: 1_001
    )
    try DestinationSnapshotFile.write(snapshot, to: url)
    #expect(try DestinationSnapshotFile.read(from: url) == snapshot)
    let lastSuccess = Date(timeIntervalSince1970: snapshot.lastSuccessEpoch ?? 0)
    #expect(
        StalenessPolicy(defaultInterval: 60).shouldEscalate(
            lastSuccess: lastSuccess,
            now: Date(timeIntervalSince1970: 1_100)
        )
    )
}

@Test func destinationSnapshotReadsLegacySchemaAndInfersState() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-snap-legacy-\(UUID().uuidString).json")
    try Data(
        """
        {"destinationID":"companion","enabled":true,"lastOutcome":"unknown_ack","lastSuccessEpoch":10,"writtenAtEpoch":20}
        """.utf8
    ).write(to: url)
    let snapshot = try DestinationSnapshotFile.read(from: url)
    #expect(snapshot.schemaVersion == 0)
    #expect(snapshot.destinationLabel == "companion")
    #expect(snapshot.state == .sentUnconfirmed)
}

@Test func widgetTimelineTransitionsWithoutAnotherAppWake() {
    let snapshot = DestinationStatusSnapshot(
        destinationID: "home-assistant",
        destinationLabel: "Home Assistant",
        enabled: true,
        state: .healthy,
        lastOutcome: "success",
        lastSuccessEpoch: 1_000,
        staleThresholdSeconds: 100,
        overdueThresholdSeconds: 200,
        writtenAtEpoch: 1_000
    )
    let entries = DestinationTimelinePlanner.entries(
        snapshots: [snapshot],
        nowEpoch: 1_050
    )
    #expect(entries.map(\.dateEpoch) == [1_050, 1_100, 1_200, 87_600, 174_000])
    #expect(snapshot.state(at: 1_050) == .healthy)
    #expect(snapshot.state(at: 1_100) == .stale)
    #expect(snapshot.state(at: 1_200) == .overdue)
}

@Test func widgetStatusRouteRoundTripsDestinationAndRejectsOtherURLs() {
    let route = WidgetStatusRoute(destinationID: "archive folder/primary")
    #expect(
        WidgetStatusRoute(url: route.url)
            == WidgetStatusRoute(destinationID: "archive folder/primary")
    )
    #expect(WidgetStatusRoute(url: URL(string: "https://example.com/status")!) == nil)
    #expect(WidgetStatusRoute(url: URL(string: "openhealthexporter://other")!) == nil)
    #expect(ExportNowRoute(url: URL(string: "openhealthexporter://export-now")!) != nil)
    #expect(ExportNowRoute(url: URL(string: "openhealthexporter://status")!) == nil)
    #expect(ExportNowRoute().url.host == "export-now")
}

@Test func ux38ControlCentreExportNowUsesWidgetControlTrigger() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let control = try String(
        contentsOf: root.appendingPathComponent("Apps/StatusWidget/ExportNowControl.swift"),
        encoding: .utf8
    )
    #expect(control.contains("struct ExportNowControl: ControlWidget"))
    #expect(control.contains("OpenURLIntent(ExportNowRoute().url)"))
    #expect(control.contains("Label(\"Export now\""))
    let bundle = try String(
        contentsOf: root.appendingPathComponent("Apps/StatusWidget/StatusWidgetBundle.swift"),
        encoding: .utf8
    )
    #expect(bundle.contains("ExportNowControl()"))
    let view = try String(
        contentsOf: root.appendingPathComponent("Apps/Exporter-iOS/HarnessView.swift"),
        encoding: .utf8
    )
    #expect(view.contains("ExportNowRoute(url: url)"))
    #expect(view.contains("trigger: .widgetControl"))
    let intents = try String(
        contentsOf: root.appendingPathComponent(
            "Apps/Exporter-iOS/LastSuccessfulExportIntent.swift"
        ),
        encoding: .utf8
    )
    #expect(intents.contains("struct ExportTypeWindowIntent"))
    #expect(intents.contains("ReturnsValue<ShortcutExportKind>"))
    #expect(intents.contains("ohe.exportWindowHours"))
    #expect(intents.contains("\"Export now with \\(.applicationName)\""))
}

@Test func failureNotificationAndStatusRowReachFivePartErrorWithinTwoTaps() {
    let failed = DestinationStatusSnapshot(
        destinationID: "home-assistant",
        destinationLabel: "Home Assistant",
        enabled: true,
        lastOutcome: "failed",
        lastSuccessEpoch: 1,
        errorClass: ErrorClass.destinationUnreachable.rawValue,
        writtenAtEpoch: 2
    )
    let overdue = DestinationStatusSnapshot(
        destinationID: "home-assistant",
        destinationLabel: "Home Assistant",
        enabled: true,
        lastOutcome: "success",
        lastSuccessEpoch: 1,
        staleThresholdSeconds: 10,
        overdueThresholdSeconds: 20,
        writtenAtEpoch: 2
    )
    let healthy = DestinationStatusSnapshot(
        destinationID: "home-assistant",
        destinationLabel: "Home Assistant",
        enabled: true,
        lastOutcome: "success",
        lastSuccessEpoch: 100,
        errorClass: ErrorClass.none.rawValue,
        writtenAtEpoch: 100
    )
    #expect(UserFacingErrorPresentation.archetype(for: failed, nowEpoch: 3) == .hostUnresolvable)
    #expect(UserFacingErrorPresentation.object(for: failed, nowEpoch: 3)?.lines[0].hasPrefix("①") == true)
    #expect(UserFacingErrorPresentation.object(for: failed, nowEpoch: 3)?.lines[3].hasPrefix("④") == true)
    #expect(UserFacingErrorPresentation.archetype(for: overdue, nowEpoch: 30) == .backgroundNeverRan)
    #expect(UserFacingErrorPresentation.object(for: healthy, nowEpoch: 100) == nil)

    let notice = UserNotice(
        kind: .exportFailed,
        destinationID: "home-assistant",
        destination: "Home Assistant",
        errorClass: ErrorClass.destinationUnreachable.rawValue
    )
    let url = FailureNotificationPayload.url(for: notice)!
    #expect(UserFacingErrorRoute(url: url)?.destinationID == "home-assistant")
    #expect(UserFacingErrorRoute(url: url)?.archetype == .hostUnresolvable)
    let info = FailureNotificationPayload.userInfo(for: notice)
    #expect(FailureNotificationPayload.url(from: info) == url)
    let overdueNotice = UserNotice(
        kind: .exportOverdue,
        destinationID: "home-assistant",
        destination: "Home Assistant"
    )
    #expect(
        UserFacingErrorRoute(url: FailureNotificationPayload.url(for: overdueNotice)!)?.archetype
            == .backgroundNeverRan
    )
    #expect(
        FailureNotificationPayload.url(
            for: UserNotice(kind: .destinationEnabled, destination: "Home Assistant")
        ) == nil
    )
}

@Test func widgetTimelineDoesNotInventThresholdsBeforeR71() {
    let snapshot = DestinationStatusSnapshot(
        destinationID: "manual",
        enabled: true,
        state: .manualOnly,
        writtenAtEpoch: 1_000
    )
    #expect(
        DestinationTimelinePlanner.entries(snapshots: [snapshot], nowEpoch: 2_000)
            .map(\.dateEpoch) == [2_000]
    )
}

@Test func widgetSnapshotSecurityEventsPersistUntilExplicitAcknowledgement() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-security-snapshot-\(UUID().uuidString).json")
    try DestinationSnapshotFile.write(
        DestinationStatusSnapshot(
            destinationID: "local-file",
            enabled: true,
            state: .healthy,
            unacknowledgedSecurityEventCount: 1,
            writtenAtEpoch: 1
        ),
        to: url
    )
    try DestinationSnapshotFile.recordSecurityEvents(
        2,
        destinationID: "local-file",
        writtenAtEpoch: 2,
        at: url
    )
    #expect(
        try DestinationSnapshotFile.read(from: url).unacknowledgedSecurityEventCount == 3
    )
    try DestinationSnapshotFile.acknowledgeSecurityEvents(writtenAtEpoch: 3, at: url)
    let acknowledged = try DestinationSnapshotFile.read(from: url)
    #expect(acknowledged.unacknowledgedSecurityEventCount == 0)
    #expect(acknowledged.writtenAtEpoch == 3)
}

@Test func widgetSnapshotSecurityEventsCreateTheFileWhenMissing() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-security-create-\(UUID().uuidString).json")
    try DestinationSnapshotFile.recordSecurityEvents(
        1,
        destinationID: "local-file",
        destinationLabel: "This iPhone",
        writtenAtEpoch: 4,
        at: url
    )
    let created = try DestinationSnapshotFile.read(from: url)
    #expect(created.destinationID == "local-file")
    #expect(created.destinationLabel == "This iPhone")
    #expect(created.unacknowledgedSecurityEventCount == 1)
    #expect(created.state == .noExportsYet)
}

@Test func destinationChangeBannerStaysUntilAcknowledgement() {
    let quiet = DestinationStatusSnapshot(
        destinationID: "https",
        destinationLabel: "nas.example.com",
        enabled: true,
        writtenAtEpoch: 1
    )
    #expect(!DestinationChangeBanner.isVisible([quiet]))
    let changed = DestinationStatusSnapshot(
        destinationID: "https",
        destinationLabel: "nas.example.com",
        enabled: true,
        unacknowledgedSecurityEventCount: 2,
        writtenAtEpoch: 1
    )
    #expect(DestinationChangeBanner.isVisible([changed]))
    #expect(DestinationChangeBanner.detail([changed]).contains("nas.example.com"))
}

@Test func exportRunWritesWidgetSnapshotAfterCommit() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0x51]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-snap-run-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    let snapshotURL = dest.appendingPathComponent("widget-status.json")
    let externalStatusURL = dest.appendingPathComponent("status.json")
    let ledgerSealURL = dest.appendingPathComponent("ledger-head-seal.json")
    let ledgerSeal = HashLedgerSeal(secret: "test-device")
    let store = MemoryStateStore()
    try DestinationSnapshotFile.write(
        DestinationStatusSnapshot(
            destinationID: "local-file",
            enabled: true,
            state: .noExportsYet,
            unacknowledgedSecurityEventCount: 2,
            writtenAtEpoch: 1
        ),
        to: snapshotURL
    )
    let run = ExportRun(
        source: FixtureSource(pages: [page]),
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch"),
        envelope: testEnvelope(),
        clock: FrozenClock(instant: Date(timeIntervalSince1970: 42)),
        trigger: .appForeground,
        snapshotURL: snapshotURL,
        externalStatusURL: externalStatusURL,
        ledgerHeadSeal: ledgerSeal,
        ledgerSealURL: ledgerSealURL
    )
    #expect(try await run.run().kind == .success)
    let snapshot = try DestinationSnapshotFile.read(from: snapshotURL)
    #expect(snapshot.lastOutcome == "success")
    #expect(snapshot.lastSuccessEpoch == 42)
    #expect(snapshot.lastConfirmedAckEpoch == 42)
    #expect(snapshot.attribution == "execution")
    #expect(snapshot.attributionConfidence == "evidenced")
    #expect(snapshot.errorClass == "none")
    #expect(snapshot.unacknowledgedSecurityEventCount == 2)
    #expect(snapshot.writtenAtEpoch == 42)
    #expect(snapshot.overdueThresholdSeconds == FreshnessTarget.alarmFloor)
    #expect(snapshot.staleThresholdSeconds == FreshnessTarget.staleFloor)
    #expect(snapshot.queueOccupancy == QueueOccupancy.green.snapshotToken)
    let external = try ExternalStatusRecordFile.read(from: externalStatusURL)
    #expect(external.schemaVersion == 1)
    #expect(external.destinationID == "local-file")
    #expect(external.runSeq == 1)
    #expect(external.outcome == "success")
    #expect(external.lastSuccessAt == testEnvelope().emittedAt)
    #expect(external.lastConfirmedAckAt == testEnvelope().emittedAt)
    #expect(external.samplesRead == 2)
    #expect(external.samplesSent == 2)
    #expect(external.samplesAcked == 2)
    #expect(external.samplesRejected == 0)
    #expect(try store.transaction.loadJournal().last?.trigger == .appForeground)
    let ledger = try await store.transact { try $0.loadLedger() }
    #expect(
        await LedgerHeadSealRecordFile.verify(
            entries: ledger,
            seal: ledgerSeal,
            url: ledgerSealURL
        ) == .valid(head: ledger.last?.entryHash ?? LedgerChain.genesisHash, count: ledger.count)
    )
}

@Test func destinationMonitoringStatusIsTypedAndComputesAgeAndTimelineState() {
    let status = DestinationMonitoringStatus(
        snapshot: DestinationStatusSnapshot(
            destinationID: "archive",
            destinationLabel: "Archive folder",
            enabled: true,
            state: .healthy,
            lastOutcome: "success",
            lastSuccessEpoch: 100,
            lastConfirmedAckEpoch: 100,
            attribution: "execution",
            attributionConfidence: "evidenced",
            errorClass: "none",
            staleThresholdSeconds: 50,
            writtenAtEpoch: 100
        ),
        nowEpoch: 160
    )
    #expect(status.destinationID == "archive")
    #expect(status.label == "Archive folder")
    #expect(status.ageSeconds == 60)
    #expect(status.state == "stale")
    #expect(status.lastOutcome == "success")
    #expect(status.attribution == "execution")
    #expect(status.errorClass == nil)
    #expect(status.failureReason == nil)

    let failed = DestinationMonitoringStatus(
        snapshot: DestinationStatusSnapshot(
            destinationID: "archive",
            destinationLabel: "Archive folder",
            enabled: true,
            state: .failing,
            lastOutcome: "failed",
            lastSuccessEpoch: 100,
            errorClass: ErrorClass.destinationUnreachable.rawValue,
            writtenAtEpoch: 160
        ),
        nowEpoch: 160
    )
    #expect(failed.errorClass == ErrorClass.destinationUnreachable.rawValue)
    #expect(
        failed.failureReason
            == ErrorClassManifest.record(for: .destinationUnreachable).userFacingCopy
    )
}

@Test func ux34EveryDestinationStateAgreesAcrossStatusWidgetIntentAndEscalation() throws {
    let now: TimeInterval = 2_000
    for state in DestinationDisplayState.allCases {
        let snapshot = DestinationStatusSnapshot(
            destinationID: "destination",
            destinationLabel: "Archive folder",
            enabled: true,
            state: state,
            writtenAtEpoch: 1_000
        )
        let effective = snapshot.state(at: now)
        let status = DestinationMonitoringStatus(snapshot: snapshot, nowEpoch: now)
        let line = DestinationStatusLine.render(snapshot, nowEpoch: now) { _ in "earlier" }
        let timeline = DestinationTimelinePlanner.entries(
            snapshots: [snapshot],
            nowEpoch: now
        )
        let widgetSnapshot = try #require(timeline.first?.snapshots.first)
        let escalation = Escalation.plan(
            snapshot: snapshot,
            now: Date(timeIntervalSince1970: now),
            notificationsAuthorized: true
        )

        #expect(status.state == effective.rawValue, "intent disagreed for \(state.rawValue)")
        #expect(line.contains(effective.rawValue), "status line disagreed for \(state.rawValue)")
        #expect(
            widgetSnapshot.state(at: now) == effective,
            "widget disagreed for \(state.rawValue)"
        )
        #expect(
            escalation.overdue == (effective == .overdue),
            "notification escalation disagreed for \(state.rawValue)"
        )
    }
}

@Test func ux41DisplayStatesStayDistinguishableByGlyphAndLabelWithoutHue() {
    let states = DestinationDisplayState.allCases
    #expect(states.count == 15)
    let glyphs = states.map(\.glyph)
    let labels = states.map(\.label)
    #expect(Set(glyphs).count == glyphs.count)
    #expect(Set(labels).count == labels.count)
    #expect(states.allSatisfy { !$0.glyph.isEmpty && !$0.label.isEmpty })
    #expect(Set(states.map(\.severity)).isSubset(of: Set(0 ... 4)))
}

@Test func ux41WidgetChromeKeepsGlyphAndLabelIdentityWhenHueIsStripped() throws {
    #expect(WidgetStatusRenderingMode.accented.stripsHue)
    #expect(WidgetStatusRenderingMode.vibrant.stripsHue)
    #expect(!WidgetStatusRenderingMode.fullColor.stripsHue)
    for mode in WidgetStatusRenderingMode.allCases {
        let identities = DestinationDisplayState.allCases.map {
            WidgetStatusChrome.identity(for: $0, mode: mode)
        }
        #expect(Set(identities).count == identities.count, "\(mode.rawValue) collapsed a state")
    }
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let widget = try String(
        contentsOf: root.appendingPathComponent("Apps/StatusWidget/StatusWidget.swift"),
        encoding: .utf8
    )
    #expect(widget.contains("@Environment(\\.widgetRenderingMode)"))
    #expect(widget.contains("WidgetStatusRenderingMode"))
    #expect(widget.contains(".widgetAccentable("))
    #expect(widget.contains(".symbolRenderingMode(mode.stripsHue ? .monochrome"))
    #expect(!widget.contains("Color.red"))
    #expect(!widget.contains(".foregroundStyle(.red"))
    #expect(!widget.contains(".foregroundStyle(.green"))
}

@Test func sec28LockedWidgetRedactsDestinationFacts() throws {
    #expect(WidgetLockRedaction.copy == "Locked")
    #expect(WidgetLockRedaction.glyph == "lock.fill")
    #expect(!DestinationDisplayState.allCases.map(\.label).contains(WidgetLockRedaction.copy))
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let widget = try String(
        contentsOf: root.appendingPathComponent("Apps/StatusWidget/StatusWidget.swift"),
        encoding: .utf8
    )
    #expect(widget.contains("@Environment(\\.redactionReasons)"))
    #expect(widget.contains("redactionReasons.contains(.privacy)"))
    #expect(widget.contains(".privacySensitive()"))
    let locked = widgetLockedViewSource(widget)
    #expect(locked.contains("WidgetLockRedaction.copy"))
    #expect(locked.contains("WidgetLockRedaction.glyph"))
    #expect(!locked.contains("destinationLabel"))
    #expect(!locked.contains("lastSuccessEpoch"))
    #expect(!locked.contains("compactFailure"))
}

private func widgetLockedViewSource(_ widget: String) -> String {
    let start = widget.range(of: "private var locked:")!
    let end = widget.range(of: "private var small:", range: start.upperBound..<widget.endIndex)!
    return String(widget[start.lowerBound..<end.lowerBound])
}

@Test func externalStatusKeepsLastSuccessAcrossFailuresAndAdvancesSequence() {
    let successTally = RunTally(read: 3, committed: 3, acked: 3)
    let success = ExternalStatusRecord.next(
        prior: nil,
        exporterInstanceID: "device",
        destinationID: "archive",
        runAt: "1970-01-01T00:01:40Z",
        runAtEpoch: 100,
        outcome: RunOutcome.derive(from: successTally),
        tally: successTally,
        trigger: .manual
    )
    let failureTally = RunTally(
        failed: 1,
        terminalError: .destinationUnreachable
    )
    let failed = ExternalStatusRecord.next(
        prior: success,
        exporterInstanceID: "device",
        destinationID: "archive",
        runAt: "1970-01-01T00:03:40Z",
        runAtEpoch: 220,
        outcome: RunOutcome.derive(from: failureTally),
        tally: failureTally,
        trigger: .bgAppRefresh
    )
    #expect(failed.runSeq == 2)
    #expect(failed.lastSuccessAt == success.lastSuccessAt)
    #expect(failed.lastConfirmedAckAt == success.lastConfirmedAckAt)
    #expect(failed.ageSeconds == 120)
    #expect(failed.attribution == "scheduling")
    #expect(failed.errorClass == "destinationUnreachable")
}

@Test func freshnessTargetRequiresFourteenDaysAndOneHundredObservations() {
    let start = Date(timeIntervalSince1970: 0)
    let tooShort = (0..<100).map { index in
        FreshnessObservation(
            observedAt: start.addingTimeInterval(Double(index) * 60),
            latency: Double(index + 1)
        )
    }
    #expect(FreshnessTarget.localP95(observations: tooShort) == nil)

    let qualifying = (0..<100).map { index in
        FreshnessObservation(
            observedAt: start.addingTimeInterval(
                Double(index) * FreshnessTarget.minimumSpan / 99
            ),
            latency: Double(index + 1)
        )
    }
    #expect(FreshnessTarget.localP95(observations: qualifying) == 95)
    #expect(FreshnessTarget.alarmThreshold(p95: 95) == FreshnessTarget.alarmFloor)
    #expect(
        FreshnessTarget.alarmThreshold(p95: 100 * 60 * 60)
            == FreshnessTarget.alarmCap
    )
}

@Test func retryPolicyUsesFullJitterAndOpensAfterFiveFailures() {
    let now = Date(timeIntervalSince1970: 1_000)
    var snapshot = BreakerSnapshot()
    for failure in 1...5 {
        snapshot = RetryPolicy.record(
            .failed(.transientNetwork),
            snapshot: snapshot,
            now: now,
            jitter: 0.5
        )
        #expect(snapshot.consecutiveFailures == failure)
    }
    #expect(snapshot.state == .open)
    // n=5: uniform(0, min(6h, 15*2^5)); injected midpoint is 240 seconds.
    #expect(snapshot.nextEarliestAttempt == now.addingTimeInterval(240))
    #expect(!RetryPolicy.mayAttempt(snapshot: snapshot, now: now, foreground: false))
    #expect(RetryPolicy.mayAttempt(snapshot: snapshot, now: now, foreground: true))
    #expect(RetryPolicy.beginProbe(snapshot: snapshot, now: now, foreground: true).state == .halfOpen)
}

@Test func retryPolicyHandlesUnknownAckImmediateBlocksAndRetryAfter() {
    let now = Date(timeIntervalSince1970: 2_000)
    var unknown = BreakerSnapshot()
    for _ in 0..<3 {
        unknown = RetryPolicy.record(.unknownAck, snapshot: unknown, now: now, jitter: 0)
    }
    #expect(unknown.state == .open)
    #expect(unknown.consecutiveUnknownAcks == 3)

    let auth = RetryPolicy.record(
        .failed(.auth),
        snapshot: BreakerSnapshot(),
        now: now,
        jitter: 0
    )
    #expect(auth.state == .blockedNeedsUser)
    #expect(!RetryPolicy.mayAttempt(snapshot: auth, now: now.addingTimeInterval(1_000_000), foreground: true))

    let pin = RetryPolicy.record(
        .failed(.pinChangeHalt),
        snapshot: BreakerSnapshot(),
        now: now,
        jitter: 0
    )
    #expect(pin.state == .halted)

    let server = RetryPolicy.record(
        .failed(.transientServer, retryAfter: 100_000),
        snapshot: BreakerSnapshot(),
        now: now,
        jitter: 0
    )
    #expect(server.nextEarliestAttempt == now.addingTimeInterval(RetryPolicy.maximumRetryAfter))
}

@Test func ux21DeferredOutcomesSkipTheFailureBreakerAndStillAgeIntoStale() {
    let now = Date(timeIntervalSince1970: 4_000)
    let prior = BreakerSnapshot(consecutiveFailures: 4)
    let locked = RetryPolicy.record(
        .failed(.storeLocked),
        snapshot: prior,
        now: now,
        jitter: 0
    )
    #expect(locked.consecutiveFailures == 4)
    #expect(locked.state == .closed)

    let unmetered = RetryPolicy.record(
        .failed(.awaitingUnmetered),
        snapshot: prior,
        now: now,
        jitter: 0
    )
    #expect(unmetered.consecutiveFailures == 4)
    #expect(unmetered.state == .closed)

    let snapshot = DestinationStatusSnapshot(
        destinationID: "archive",
        destinationLabel: "Archive folder",
        enabled: true,
        lastOutcome: "blockedDeviceLocked",
        lastSuccessEpoch: 100,
        errorClass: ErrorClass.deviceLocked.rawValue,
        staleThresholdSeconds: 60,
        overdueThresholdSeconds: 200,
        writtenAtEpoch: 160
    )
    #expect(snapshot.state == .deferred)
    let line = DestinationStatusLine.render(snapshot, nowEpoch: 120) { _ in "earlier" }
    #expect(line.contains("deferred"))
    #expect(line.contains("non-actionable"))
    #expect(!line.contains("failing"))
    #expect(snapshot.state(at: 170) == .stale)
    #expect(snapshot.state(at: 310) == .overdue)
    let notYetOverdue = Escalation.plan(
        snapshot: snapshot,
        now: Date(timeIntervalSince1970: 120),
        notificationsAuthorized: true
    )
    #expect(!notYetOverdue.overdue)
    let aged = Escalation.plan(
        snapshot: snapshot,
        now: Date(timeIntervalSince1970: 310),
        notificationsAuthorized: true
    )
    #expect(aged.overdue)
}

@Test func retryPolicyPersistentBreakerProbesAtMostEverySixHours() {
    let opened = Date(timeIntervalSince1970: 3_000)
    let snapshot = BreakerSnapshot(
        state: .open,
        consecutiveFailures: 5,
        openedAt: opened,
        nextEarliestAttempt: opened
    )
    let weekLater = opened.addingTimeInterval(RetryPolicy.persistentAfter)
    let aged = RetryPolicy.age(snapshot: snapshot, now: weekLater)
    #expect(aged.state == .failingPersistently)
    #expect(aged.nextEarliestAttempt == weekLater.addingTimeInterval(RetryPolicy.maximumDelay))
}

@Test func pipelineExposesExceptionList() {
    #expect(!Pipeline().hkStatisticsExceptions.isEmpty)
}

func heartSample(_ uuid: String, start: String = "2024-01-01T00:00:00Z") -> SampleRecord {
    SampleRecord(
        key: RecordKey(uuid: uuid),
        metric: MetricID(rawValue: "heartRate"),
        start: start,
        end: start,
        timeZoneOffsetMinutes: 0,
        timeZoneSource: .unknown,
        value: 60,
        unit: CanonicalUnit(symbol: "count/min"),
        observedAt: "2024-01-01T00:00:00Z"
    )
}

func testEnvelope() -> WireEnvelope {
    WireEnvelope(
        exporterId: "00000000-0000-0000-0000-00000000000e",
        seq: 1,
        emittedAt: "2024-01-01T00:00:00Z",
        observedAt: "2024-01-01T00:00:00Z"
    )
}

func statisticsRecord(
    metric: MetricID = MetricCatalog.stepCount.id,
    day: String = "2024-01-01",
    value: Double = 123
) -> AggregateRecord {
    let bounds = BucketKey.boundsP1D(day: day, context: .utc)!
    let declaration = MetricCatalog.declaration(for: metric)!
    return AggregateRecord(
        bucketKey: BucketKey.render(
            metricWireId: declaration.wireId,
            statistic: AggregateStatistic.sum.rawValue,
            granularity: "P1D",
            bucketStart: bounds.bucketStart,
            timeZoneIdentifier: "UTC",
            sourceScope: AggregateSourceScope.all.rawValue
        ),
        metric: metric,
        statistic: .sum,
        computation: .healthKitStatisticsCollectionQuery,
        sourceScope: .all,
        granularity: "P1D",
        bucketStart: bounds.bucketStart,
        bucketEnd: bounds.bucketEnd,
        bucketDurationSeconds: bounds.bucketDurationSeconds,
        timeZoneIdentifier: "UTC",
        localStart: bounds.localStart,
        value: value,
        unit: declaration.canonicalUnit,
        sampleCount: 0,
        state: .open,
        emitSeq: 1,
        computedAt: "ignored",
        observedAt: "ignored"
    )
}

@Test func retroactiveDirtyDayDrainsOnLaterEmptyDeltaRun() async throws {
    let metric = MetricCatalog.stepCount.id
    let retroactive = SampleRecord(
        key: RecordKey(uuid: "a1000000-0000-4000-8000-000000000001"),
        metric: metric,
        start: "2024-01-01T12:00:00Z",
        end: "2024-01-01T12:00:00Z",
        timeZoneOffsetMinutes: 0,
        timeZoneSource: .unknown,
        value: 123,
        unit: CanonicalUnit(symbol: "count"),
        observedAt: "2024-02-01T00:00:00Z"
    )
    let page = SamplePage(
        samples: [retroactive],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0xA1]),
        observedThrough: Date(timeIntervalSince1970: 1_706_745_600)
    )
    let source = FixtureSource(pages: [page])
    let store = MemoryStateStore()
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-retroactive-dirty-\(UUID().uuidString)")
    let destinationURL = root.appendingPathComponent("destination")
    try FileManager.default.createDirectory(
        at: destinationURL,
        withIntermediateDirectories: true
    )
    let first = ExportRun(
        source: source,
        destination: .testing(LocalFileSink(directory: destinationURL)),
        store: store,
        metric: metric,
        scratchDirectory: root.appendingPathComponent("scratch-first"),
        envelope: testEnvelope(),
        statistics: nil
    )
    #expect(try await first.run().kind == .success)
    #expect(try store.transaction.dirtyDays(metric: metric) == ["2024-01-01"])

    let second = ExportRun(
        source: source,
        destination: .testing(LocalFileSink(directory: destinationURL)),
        store: store,
        metric: metric,
        scratchDirectory: root.appendingPathComponent("scratch-second"),
        envelope: testEnvelope(),
        statistics: FixtureStatistics(
            byDay: ["2024-01-01": statisticsRecord(metric: metric)]
        )
    )
    #expect(try await second.run().kind == .success)
    #expect(try store.transaction.dirtyDays(metric: metric).isEmpty)

    let delivered = try FileManager.default.contentsOfDirectory(
        at: destinationURL,
        includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "ndjson" }
    #expect(delivered.count == 2)
    let payloads = try delivered.map { try String(contentsOf: $0, encoding: .utf8) }
    let aggregatePayload = try #require(payloads.first { $0.contains("\"kind\":\"aggregate\"") })
    #expect(aggregatePayload.contains("\"completeThrough\":"))
    #expect(aggregatePayload.contains("\"bucketStart\":\"2024-01-01T00:00:00.000Z\""))
}

@Test func persistedDiscreteDirtyDayRefetchesFullDayBeforeFold() async throws {
    let metric = MetricCatalog.heartRate.id
    let sample = heartSample("a2000000-0000-4000-8000-000000000001")
    let store = MemoryStateStore()
    try store.transaction.markDirty(metric: metric, day: "2024-01-01")
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-dirty-refetch-\(UUID().uuidString)")
    let destinationURL = root.appendingPathComponent("destination")
    try FileManager.default.createDirectory(
        at: destinationURL,
        withIntermediateDirectories: true
    )
    let run = ExportRun(
        source: FixtureSource(pages: []),
        destination: .testing(LocalFileSink(directory: destinationURL)),
        store: store,
        metric: metric,
        scratchDirectory: root.appendingPathComponent("scratch"),
        envelope: testEnvelope(),
        observations: FixtureDays(byDay: ["2024-01-01": [sample]])
    )
    #expect(try await run.run().kind == .success)
    #expect(try store.transaction.dirtyDays(metric: metric).isEmpty)
    let delivered = try FileManager.default.contentsOfDirectory(
        at: destinationURL,
        includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "ndjson" }
    let payload = try String(contentsOf: try #require(delivered.first), encoding: .utf8)
    #expect(payload.contains("\"kind\":\"aggregate\""))
    #expect(payload.contains("\"sampleCount\":1"))
}

/// R-69: the browser must not claim a delivery the export never made. Selection is not
/// evidence — a type can be selected and never sent — so the claim is read back from the
/// emitted index the run itself wrote.
@Test func browserReportsOnlyWhatTheExportActuallyEmitted() async throws {
    let exported = MetricCatalog.heartRate.id
    let neverRun = MetricCatalog.stepCount.id
    let store = MemoryStateStore()
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-r69-parity-\(UUID().uuidString)")
    let destinationURL = root.appendingPathComponent("destination")
    try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(try await BrowserSendState.sentThroughDay(metric: exported, store: store) == nil)

    let page = SamplePage(
        samples: [heartSample("b1000000-0000-4000-8000-000000000001")],
        tombstones: [],
        metric: exported,
        anchorBlob: Data([0x69]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let run = ExportRun(
        source: FixtureSource(pages: [page]),
        destination: .testing(LocalFileSink(directory: destinationURL)),
        store: store,
        metric: exported,
        scratchDirectory: root.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    )
    #expect(try await run.run().kind == .success)

    let day = try #require(
        await BrowserSendState.sentThroughDay(metric: exported, store: store)
    )
    let indexed = try store.transaction.loadEmittedIndex(metric: exported, day: day)
    #expect(!indexed.isEmpty)
    #expect(
        try await BrowserSendState.sentThroughDay(metric: neverRun, store: store) == nil
    )

    // The detail a person reads carries that same day, and a type never exported carries
    // no destination row rather than an empty or invented one.
    let sent = DataBrowser.detail(
        metric: exported,
        samples: [],
        destinations: [DataBrowserDestination(name: "Archive folder", sentThroughDay: day)],
        now: Date(timeIntervalSince1970: 0)
    )
    #expect(sent?.destinations.first?.sentThroughDay == day)
    let unsent = DataBrowser.detail(
        metric: neverRun,
        samples: [],
        now: Date(timeIntervalSince1970: 0)
    )
    #expect(unsent?.destinations.isEmpty == true)
}

@Test func categoryPageCommitsCensusAndEmittedIndexWithoutInventedAggregate() async throws {
    let metric = MetricID(rawValue: "sleep_analysis")
    let category = CategoryRecord(
        key: RecordKey(uuid: "a3000000-0000-4000-8000-000000000001"),
        metric: metric,
        healthKitIdentifier: "HKCategoryTypeIdentifierSleepAnalysis",
        start: "2024-01-01T22:00:00Z",
        end: "2024-01-02T06:00:00Z",
        timeZoneOffsetMinutes: 0,
        timeZoneSource: .unknown,
        categoryValue: 3,
        categoryName: "asleepDeep",
        durationSeconds: 28_800,
        observedAt: "2024-01-02T08:00:00Z"
    )
    let page = SamplePage(
        samples: [],
        categories: [category],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0xA3]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let store = MemoryStateStore()
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-category-page-\(UUID().uuidString)")
    let destinationURL = root.appendingPathComponent("destination")
    try FileManager.default.createDirectory(
        at: destinationURL,
        withIntermediateDirectories: true
    )
    let run = ExportRun(
        source: FixtureSource(pages: [page]),
        destination: .testing(LocalFileSink(directory: destinationURL)),
        store: store,
        metric: metric,
        scratchDirectory: root.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    )
    #expect(try await run.run().kind == .success)
    #expect(try store.transaction.loadCensus(metric: metric, day: "2024-01-01")?.sampleCount == 1)
    #expect(try store.transaction.loadEmittedIndex(uuid: category.key.uuid) != nil)
    #expect(try store.transaction.dirtyDays(metric: metric).isEmpty)
    let payloadURL = try #require(
        FileManager.default.contentsOfDirectory(
            at: destinationURL,
            includingPropertiesForKeys: nil
        ).first { $0.pathExtension == "ndjson" }
    )
    let payload = try String(contentsOf: payloadURL, encoding: .utf8)
    #expect(payload.contains("\"kind\":\"sample.category\""))
    #expect(!payload.contains("\"kind\":\"aggregate\""))
}

@Test func writeAheadCursorPreventsRereadAfterCommit() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0xAA]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let source = FixtureSource(pages: [page])
    let store = MemoryStateStore()
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-scratch-\(UUID().uuidString)")
    let dest = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-dest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    let sink = LocalFileSink(directory: dest)
    let run = ExportRun(
        source: source,
        destination: .testing(sink),
        store: store,
        metric: metric,
        scratchDirectory: scratch,
        envelope: testEnvelope()
    )

    let first = try await run.run()
    #expect(first.kind == .success)
    #expect(try store.transaction.loadCursor(metric: metric)?.anchorBlob == Data([0xAA]))
    #expect(store.transaction.cursors[metric]?.anchorBlob.prefix(4) == Data("OHEC".utf8))
    let checkpoint = try CheckpointEnvelope.decoded(
        try #require(store.transaction.cursors[metric]?.anchorBlob)
    )
    #expect(checkpoint.tzDatabaseVersion == TemporalContext.utc.tzDatabaseVersion)
    #expect(try store.transaction.pendingBatches().isEmpty)
    #expect(store.transaction.ledger.count == 3)
    let phases = store.transaction.ledger.map(\.outcomeKind)
    #expect(phases[0].split(separator: ":").last == "attempt")
    #expect(phases[1].split(separator: ":").last == "acknowledged")
    #expect(phases[2] == "run:success")
    #expect(phases[0].split(separator: ":").first == phases[1].split(separator: ":").first)
    let census = try store.transaction.loadCensus(metric: metric, day: "2024-01-01")
    #expect(census?.sampleCount == 1)
    #expect(try store.transaction.dirtyDays(metric: metric).isEmpty)
    let delivered = try FileManager.default.contentsOfDirectory(
        at: dest,
        includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "ndjson" }
    let payloadText = try String(contentsOf: delivered[0], encoding: .utf8)
    #expect(payloadText.contains("\"kind\":\"aggregate\""))
    let indexed = try store.transaction.loadEmittedIndex(
        uuid: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    )
    #expect(indexed?.day == "2024-01-01")
    let headerLine = try #require(payloadText.split(whereSeparator: \.isNewline).first)
    let header = try #require(
        JSONSerialization.jsonObject(with: Data(headerLine.utf8)) as? [String: Any]
    )
    #expect(indexed?.batchID.rawValue == header["batchId"] as? String)

    let second = try await run.run()
    #expect(second.kind == .successNothingDue)
    #expect(store.transaction.ledger.count == 4)
    #expect(store.transaction.ledger.last?.outcomeKind == "run:successNothingDue")
}

#if DEBUG
private enum InjectedExportFault: Error {
    case stop
}

private struct OneExportFault: ExportFaultInjector {
    var location: ExportFaultLocation

    func hit(_ location: ExportFaultLocation) throws {
        if location == self.location {
            throw InjectedExportFault.stop
        }
    }
}

@Test func p4NoDuplicationAfterKillResumeAtEveryDeliverySeam() async throws {
    try await replayP4KillResumeCounterexample(
        seed: 83,
        faultSchedule: ExportFaultLocation.allCases
    )
}

@Test func interruptedExportSealsAsCancelledBySystemOnNextLaunch() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("26000000-0000-4000-8000-000000000026")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0x26]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-ux26-\(UUID().uuidString)")
    let destinationURL = root.appendingPathComponent("destination")
    try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
    let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
    var run = ExportRun(
        source: FixtureSource(pages: [page]),
        destination: .testing(LocalFileSink(directory: destinationURL)),
        store: store,
        metric: metric,
        scratchDirectory: root.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    )
    run.faults = OneExportFault(location: .afterRead)
    await #expect(throws: InjectedExportFault.stop) {
        _ = try await run.run()
    }
    let open = try await store.transact { try $0.loadOpenRuns() }
    #expect(open.count == 1)
    #expect(open[0].phase == "reading")
    #expect(open[0].samplesRead == 1)
    #expect(open[0].samplesCommitted == 0)

    let sealed = try await InterruptedRunRecovery.seal(store: store, nowEpoch: 1_704_100_440)
    #expect(sealed.count == 1)
    #expect(try await store.transact { try $0.loadOpenRuns() }.isEmpty)
    let event = try #require(try await store.transact { try $0.loadJournal().last })
    #expect(event.outcomeKind == RunOutcome.Kind.cancelledBySystem.rawValue)
    #expect(event.detail == "os_termination")
    #expect(event.errorClass == ErrorClass.cancelledBySystem.rawValue)
    #expect(event.samplesRead == 1)
    #expect(RunHistoryDetail.listLine(event).hasPrefix("Interrupted"))
    #expect(try await InterruptedRunRecovery.seal(store: store, nowEpoch: 1_704_100_441).isEmpty)
}

@Test func completedExportClosesTheOpenRunLease() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("26000000-0000-4000-8000-000000000027")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0x27]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-ux26-ok-\(UUID().uuidString)")
    let destinationURL = root.appendingPathComponent("destination")
    try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
    let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
    let run = ExportRun(
        source: FixtureSource(pages: [page]),
        destination: .testing(LocalFileSink(directory: destinationURL)),
        store: store,
        metric: metric,
        scratchDirectory: root.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    )
    let outcome = try await run.run()
    #expect(outcome.kind == .success)
    #expect(try await store.transact { try $0.loadOpenRuns() }.isEmpty)
}

/// C-04 / AR-12: force-quit after the destination write and before ack leaves
/// the batch in our SQLite pending table. Relaunch reconstructs from that
/// store. CorrectnessEngine never consults URLSession for queue membership.
@Test func forceQuitMidTransferReconstructsQueueFromSQLiteNotURLSession() async throws {
    let uuid = "c0400000-0000-4000-8000-000000000004"
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample(uuid)],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0xC0]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-c04-\(UUID().uuidString)")
    let sqlitePath = root.appendingPathComponent("state.sqlite").path
    let destinationURL = root.appendingPathComponent("destination")
    try FileManager.default.createDirectory(
        at: destinationURL,
        withIntermediateDirectories: true
    )
    let pendingID: BatchID
    do {
        let store = try SQLiteStateStore(path: sqlitePath)
        var run = ExportRun(
            source: FixtureSource(pages: [page]),
            destination: .testing(LocalFileSink(directory: destinationURL)),
            store: store,
            metric: metric,
            scratchDirectory: root.appendingPathComponent("scratch"),
            envelope: testEnvelope()
        )
        run.faults = OneExportFault(location: .afterDestinationWriteBeforeAck)
        await #expect(throws: InjectedExportFault.stop) {
            _ = try await run.run()
        }
        let pending = try await store.transact { try $0.pendingBatches() }
        #expect(pending.count == 1)
        pendingID = try #require(pending.first?.id)
    }

    let reopened = try SQLiteStateStore(path: sqlitePath)
    let restored = try await reopened.transact { try $0.pendingBatches() }
    #expect(restored.map(\.id) == [pendingID])

    _ = try await PendingDeliveryRunner(
        destination: .testing(LocalFileSink(directory: destinationURL)),
        store: reopened
    ).runOnce()
    #expect(try await reopened.transact { try $0.pendingBatches() }.isEmpty)

    let engineRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/CorrectnessEngine")
    let engineFiles = try FileManager.default.contentsOfDirectory(
        at: engineRoot,
        includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "swift" }
    for file in engineFiles {
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(
            !text.contains("URLSession"),
            "\(file.lastPathComponent) must not reconstruct the queue from URLSession"
        )
    }
}

func replayP4KillResumeCounterexample(
    seed: UInt64,
    faultSchedule: [ExportFaultLocation]
) async throws {
    let beforeCommit: Set<ExportFaultLocation> = [.afterRead, .afterTransform, .duringAnchorPersist]
    let uuid = String(format: "f0000000-0000-4000-8000-%012llx", seed)
    for location in faultSchedule {
        let metric = MetricID(rawValue: "heartRate")
        let page = SamplePage(
            samples: [heartSample(uuid)],
            tombstones: [],
            metric: metric,
            anchorBlob: Data([0xF0]),
            observedThrough: Date(timeIntervalSince1970: 0)
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohe-fi-\(location.rawValue)-\(UUID().uuidString)")
        let destinationURL = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: true
        )
        let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
        var run = ExportRun(
            source: FixtureSource(pages: [page]),
            destination: .testing(LocalFileSink(directory: destinationURL)),
            store: store,
            metric: metric,
            scratchDirectory: root.appendingPathComponent("scratch"),
            envelope: testEnvelope()
        )
        run.faults = OneExportFault(location: location)

        await #expect(throws: InjectedExportFault.stop) {
            _ = try await run.run()
        }
        let cursor = try await store.transact { try $0.loadCursor(metric: metric) }
        let pending = try await store.transact { try $0.pendingBatches() }
        if beforeCommit.contains(location) {
            #expect(cursor == nil, "cursor advanced at \(location.rawValue)")
            #expect(pending.isEmpty, "batch survived rollback at \(location.rawValue)")
            #expect(
                try await store.transact {
                    try $0.loadEmittedIndex(uuid: uuid)
                } == nil,
                "emitted_index survived rollback at \(location.rawValue)"
            )
        } else {
            #expect(cursor?.anchorBlob == Data([0xF0]))
            #expect(pending.count == 1, "batch was not replayable at \(location.rawValue)")
            #expect(
                try await store.transact {
                    try $0.loadEmittedIndex(uuid: uuid)
                } != nil,
                "emitted_index missing after commit at \(location.rawValue)"
            )
        }

        if beforeCommit.contains(location) {
            let resumed = ExportRun(
                source: FixtureSource(pages: [page]),
                destination: .testing(LocalFileSink(directory: destinationURL)),
                store: store,
                metric: metric,
                scratchDirectory: root.appendingPathComponent("scratch-resumed"),
                envelope: testEnvelope()
            )
            let outcome = try await resumed.run()
            #expect(outcome.kind == .success, "resume failed at \(location.rawValue)")
        } else {
            let replay = PendingDeliveryRunner(
                destination: .testing(LocalFileSink(directory: destinationURL)),
                store: store
            )
            _ = try await replay.runOnce()
            #expect(try await store.transact { try $0.pendingBatches() }.isEmpty)
        }
        let delivered = try FileManager.default.contentsOfDirectory(
            at: destinationURL,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "ndjson" }
        #expect(
            delivered.count == 1,
            "kill/resume delivery multiplicity was \(delivered.count) at \(location.rawValue)"
        )
    }
}

private struct ProcessExitFault: ExportFaultInjector {
    func hit(_ location: ExportFaultLocation) throws {
        guard let raw = getenv("OHE_PROCESS_EXIT_SEAM"),
              String(cString: raw) == location.rawValue
        else {
            return
        }
        _exit(9)
    }
}

private func runUntilProcessExitSeam() async throws {
    guard let rawRoot = getenv("OHE_PROCESS_EXIT_ROOT"),
          let rawSeed = getenv("OHE_PROCESS_EXIT_SEED"),
          let seed = Int(String(cString: rawSeed))
    else {
        _exit(2)
    }
    let uuid = String(format: "e0000000-0000-4000-8000-%012x", seed)
    let root = URL(fileURLWithPath: String(cString: rawRoot), isDirectory: true)
    let destinationURL = root.appendingPathComponent("destination")
    try FileManager.default.createDirectory(
        at: destinationURL,
        withIntermediateDirectories: true
    )
    let metric = MetricCatalog.heartRate.id
    let page = SamplePage(
        samples: [heartSample(uuid)],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0xE0]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    var run = ExportRun(
        source: FixtureSource(pages: [page]),
        destination: .testing(LocalFileSink(directory: destinationURL)),
        store: try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path),
        metric: metric,
        scratchDirectory: root.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    )
    run.faults = ProcessExitFault()
    _ = try await run.run()
    _exit(3)
}

@Test func p3ProcessExitAtEverySeamResumesWithoutLoss() async throws {
    for seed in 1 ... 4 {
        for location in ExportFaultLocation.allCases {
        let uuid = String(format: "e0000000-0000-4000-8000-%012x", seed)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ohe-process-exit-\(seed)-\(location.rawValue)-\(UUID().uuidString)"
            )
        setenv("OHE_PROCESS_EXIT_ROOT", root.path, 1)
        setenv("OHE_PROCESS_EXIT_SEAM", location.rawValue, 1)
        setenv("OHE_PROCESS_EXIT_SEED", String(seed), 1)
        await #expect(processExitsWith: .exitCode(9)) {
            try await runUntilProcessExitSeam()
        }
        unsetenv("OHE_PROCESS_EXIT_ROOT")
        unsetenv("OHE_PROCESS_EXIT_SEAM")
        unsetenv("OHE_PROCESS_EXIT_SEED")

        let destinationURL = root.appendingPathComponent("destination")
        let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
        if !(try await store.transact { try $0.pendingBatches() }).isEmpty {
            let replay = PendingDeliveryRunner(
                destination: .testing(LocalFileSink(directory: destinationURL)),
                store: store
            )
            _ = try await replay.runOnce()
        }
        let metric = MetricCatalog.heartRate.id
        let page = SamplePage(
            samples: [heartSample(uuid)],
            tombstones: [],
            metric: metric,
            anchorBlob: Data([0xE0]),
            observedThrough: Date(timeIntervalSince1970: 0)
        )
        let resumed = ExportRun(
            source: FixtureSource(pages: [page]),
            destination: .testing(LocalFileSink(directory: destinationURL)),
            store: store,
            metric: metric,
            scratchDirectory: root.appendingPathComponent("resume-scratch"),
            envelope: testEnvelope()
        )
        _ = try await resumed.run()
        let delivered = try FileManager.default.contentsOfDirectory(
            at: destinationURL,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "ndjson" }
        #expect(delivered.count == 1, "seed \(seed) delivery count at \(location.rawValue)")
        var receiver = ReferenceReceiver()
        try receiver.ingest(
            ndjson: String(contentsOf: delivered[0], encoding: .utf8)
        )
        #expect(
            receiver.quantities[uuid] != nil,
            "seed \(seed) sample lost at \(location.rawValue)"
        )
        let journal = try await store.transact { try $0.loadJournal() }
        #expect(!journal.isEmpty, "journal missing after relaunch at \(location.rawValue)")
        #expect(
            [RunOutcome.Kind.success.rawValue, RunOutcome.Kind.successNothingDue.rawValue]
                .contains(journal.last?.outcomeKind ?? ""),
            "seed \(seed) relaunch outcome missing at \(location.rawValue)"
        )
        }
    }
}

@Test func p14ProcessExitDuringAnchorPersistLeavesThePriorCheckpointComplete() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-p14-process-exit-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let metric = MetricCatalog.heartRate.id
    let checkpoint = CheckpointEnvelope(
        tzDatabaseVersion: "2024a",
        epoch: 7,
        adapterAnchor: Data([0x14])
    )
    let statePath = root.appendingPathComponent("state.sqlite").path
    try SQLiteV1Fixture.write(
        path: statePath,
        metric: metric,
        checkpoint: checkpoint,
        runID: "p14-prior"
    )

    setenv("OHE_PROCESS_EXIT_ROOT", root.path, 1)
    setenv("OHE_PROCESS_EXIT_SEAM", ExportFaultLocation.duringAnchorPersist.rawValue, 1)
    setenv("OHE_PROCESS_EXIT_SEED", "14", 1)
    await #expect(processExitsWith: .exitCode(9)) {
        try await runUntilProcessExitSeam()
    }
    unsetenv("OHE_PROCESS_EXIT_ROOT")
    unsetenv("OHE_PROCESS_EXIT_SEAM")
    unsetenv("OHE_PROCESS_EXIT_SEED")

    let reopened = try SQLiteStateStore(path: statePath)
    let cursor = try await reopened.transact { try $0.loadCursor(metric: metric) }
    #expect(cursor?.epoch == 7)
    #expect(cursor?.anchorBlob == Data([0x14]))
    #expect(try await reopened.transact { try $0.pendingBatches() }.isEmpty)
}
#endif

@Test func pendingDeliveryRunnerReplaysACommittedBatchAfterRestart() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("dddddddd-dddd-dddd-dddd-dddddddddddd")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0xDD]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-replay-\(UUID().uuidString)")
    let destination = root.appendingPathComponent("destination")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let payload = root.appendingPathComponent("batch.ndjson")
    try "one\n".write(to: payload, atomically: true, encoding: .utf8)
    let secondPayload = root.appendingPathComponent("batch-2.ndjson")
    try "two\n".write(to: secondPayload, atomically: true, encoding: .utf8)
    let store = MemoryStateStore()
    try await store.transact {
        try $0.commitBatch(
            PendingBatch(
                id: BatchID(rawValue: "z-oldest"),
                payloadURL: payload.path,
                expectedRecords: 1
            ),
            advancing: CursorAdvance(page: page, epoch: 1)
        )
        try $0.commitBatch(
            PendingBatch(
                id: BatchID(rawValue: "a-newest"),
                payloadURL: secondPayload.path,
                expectedRecords: 1
            ),
            advancing: CursorAdvance(page: page, epoch: 1)
        )
    }

    let runner = PendingDeliveryRunner(
        destination: .testing(LocalFileSink(directory: destination)),
        store: store,
        clock: FrozenClock(instant: Date(timeIntervalSince1970: 123))
    )
    let receipts = try await runner.runOnce()
    #expect(receipts.map(\.accepted) == [1])
    #expect(try store.transaction.pendingBatches().map(\.id.rawValue) == ["a-newest"])
    #expect(store.transaction.ledger.count == 2)
    _ = try await runner.runOnce()
    #expect(try store.transaction.pendingBatches().isEmpty)
    #expect(store.transaction.ledger.count == 4)
}

@Test func failedPendingDeliveryStillRecordsItsOutcomeAndStaysQueued() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0xEE]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-replay-fail-\(UUID().uuidString)")
    let destination = root.appendingPathComponent("destination")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let store = MemoryStateStore()
    try await store.transact {
        try $0.commitBatch(
            PendingBatch(
                id: BatchID(rawValue: "failed-replay"),
                payloadURL: root.appendingPathComponent("missing.ndjson").path,
                expectedRecords: 1
            ),
            advancing: CursorAdvance(page: page, epoch: 1)
        )
    }
    let runner = PendingDeliveryRunner(
        destination: .testing(LocalFileSink(directory: destination)),
        store: store,
        clock: FrozenClock(instant: Date(timeIntervalSince1970: 123))
    )
    await #expect(throws: Error.self) {
        _ = try await runner.runOnce()
    }
    #expect(try store.transaction.pendingBatches().count == 1)
    #expect(store.transaction.ledger.count == 2)
    #expect(store.transaction.ledger[0].outcomeKind.hasSuffix(":attempt"))
    #expect(store.transaction.ledger[1].outcomeKind.hasSuffix(":failed"))
    #expect(store.transaction.ledger.allSatisfy { $0.wallTimeEpoch == 123 })
    #expect(
        LedgerChain.verify(store.transaction.ledger)
            == .valid(head: store.transaction.ledger[1].entryHash, count: 2)
    )
}

@Test func skipCommitLeavesCursorUnmovedSoPageIsReread() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0xBB]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let source = FixtureSource(pages: [page])
    let first = try await source.page(metric: metric, afterAnchor: nil)
    #expect(first.samples.count == 1)
    let again = try await source.page(metric: metric, afterAnchor: nil)
    #expect(again.samples.count == 1)
    let afterFakeCommit = try await source.page(metric: metric, afterAnchor: Data([0xBB]))
    #expect(afterFakeCommit.samples.isEmpty)
}

@Test func localFileSinkIsIdempotentForTheSameKey() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-sink-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let payload = dir.appendingPathComponent("src.ndjson")
    try "one\n".write(to: payload, atomically: true, encoding: .utf8)
    let sink = LocalFileSink(directory: dir)
    let key = BatchID(rawValue: "same-key")
    let a = try await sink.send(fileHandle: payload.path, idempotencyKey: key)
    let b = try await sink.send(fileHandle: payload.path, idempotencyKey: key)
    #expect(a.accepted == 1)
    #expect(b.accepted == 1)
    let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "ndjson" && $0.lastPathComponent != "src.ndjson" }
    #expect(files.count == 1)
}

@Test func localFileSinkWritesJSONCSVAndHAESidecars() async throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-sidecars-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let (payload, batchID) = try writeMQTTPayload()
    let sink = LocalFileSink(directory: dir)
    _ = try await sink.send(fileHandle: payload.path, idempotencyKey: batchID)
    let encodings = dir.appendingPathComponent(
        NativeWire.outputFileName(batchID: batchID, demo: false)
    ).deletingPathExtension().appendingPathExtension("encodings")
    let names = try FileManager.default.contentsOfDirectory(atPath: encodings.path)
    #expect(names.contains("batch.json"))
    #expect(names.contains("batch.pretty.json"))
    #expect(names.contains("batch.hae.json"))
    #expect(names.contains("_meta.json"))
    #expect(names.contains { $0.hasPrefix("ohe1-quantity-") })
}

@Test func nativeWireHeaderCarriesDeclaredTzDatabaseVersion() throws {
    let envelope = WireEnvelope(
        exporterId: "exp",
        seq: 1,
        emittedAt: "2026-01-01T00:00:00Z",
        observedAt: "2026-01-01T00:00:00Z",
        tzDatabaseVersion: "2024a"
    )
    let data = try NativeWire.encode(
        samples: [heartSample("00000000-0000-0000-0000-000000000001")],
        tombstones: [],
        metric: MetricID(rawValue: "heartRate"),
        batchID: BatchID(rawValue: "0192f3c1-0000-0000-0000-00000000000b"),
        envelope: envelope
    )
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("\"tzDatabaseVersion\":\"2024a\""))
}

@Test func runHistoryListsProblemsBeforeSuccess() {
    let events = [
        RunEvent(runID: RunID(rawValue: "a"), outcomeKind: "success", detail: "", wallTimeEpoch: 1),
        RunEvent(runID: RunID(rawValue: "b"), outcomeKind: "failed", detail: "", errorClass: "network"),
        RunEvent(runID: RunID(rawValue: "c"), outcomeKind: "successNothingDue", detail: "", wallTimeEpoch: 3),
        RunEvent(runID: RunID(rawValue: "d"), outcomeKind: "unknownAck", detail: "", wallTimeEpoch: 4),
    ]
    let ranked = RunHistory.problemsFirst(events)
    #expect(ranked.map(\.outcomeKind) == ["unknownAck", "failed", "successNothingDue", "success"])
}

@Test func localFileSinkRejectsDifferentBytesForTheSameKey() async throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-sink-conflict-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let payload = dir.appendingPathComponent("src.ndjson")
    try "one\n".write(to: payload, atomically: true, encoding: .utf8)
    let sink = LocalFileSink(directory: dir)
    let key = BatchID(rawValue: "same-key")
    _ = try await sink.send(fileHandle: payload.path, idempotencyKey: key)
    try "different\n".write(to: payload, atomically: true, encoding: .utf8)
    await #expect(throws: LocalFileSinkError.idempotencyConflict) {
        _ = try await sink.send(fileHandle: payload.path, idempotencyKey: key)
    }
}

@Test func p13PriorSQLiteSchemaMigratesWithoutResettingTheCursor() async throws {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-legacy-\(UUID().uuidString).sqlite")
        .path
    let metric = MetricID(rawValue: "heartRate")
    let checkpoint = CheckpointEnvelope(
        tzDatabaseVersion: "2024a",
        epoch: 4,
        adapterAnchor: Data([0x11, 0x22])
    )
    try SQLiteV1Fixture.write(
        path: path,
        metric: metric,
        checkpoint: checkpoint,
        runID: "legacy-run"
    )
    let store = try SQLiteStateStore(path: path)
    let snap = try await store.transact { try $0.loadCursor(metric: metric) }
    #expect(snap?.epoch == 4)
    #expect(snap?.anchorBlob == Data([0x11, 0x22]))
    let journal = try await store.transact { try $0.loadJournal() }
    #expect(journal.map(\.runID.rawValue) == ["legacy-run"])
    #expect(journal.first?.outcomeKind == "success")
    #expect(journal.first?.trigger == .manual)
    #expect(journal.first?.projectedAtEpoch == nil)
}

@Test func checkpointBytesDoNotEmbedSampleIdentifiers() {
    let canary = "ffffffff-ffff-4fff-8fff-ffffffffffff"
    let envelope = CheckpointEnvelope(
        tzDatabaseVersion: "2024a",
        epoch: 1,
        adapterAnchor: Data([0x00, 0x01, 0x02])
    )
    let bytes = envelope.encoded()
    #expect(String(decoding: bytes, as: UTF8.self).contains(canary) == false)
}

@Test func sqlitePersistsCursorAndCensus() async throws {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-test-\(UUID().uuidString).sqlite")
        .path
    let store = try SQLiteStateStore(path: path)
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("cccccccc-cccc-cccc-cccc-cccccccccccc")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0xCC, 0xDD]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    try await store.transact { tx in
        try tx.commitBatch(
            PendingBatch(id: BatchID(rawValue: "b"), payloadURL: "/tmp/x", expectedRecords: 2),
            advancing: CursorAdvance(page: page, epoch: 3)
        )
        try tx.upsertCensus(CensusRow(metric: metric, day: "2024-01-01", sampleCount: 1, digest: "abc"))
        try tx.markDirty(metric: metric, day: "2024-01-01")
    }
    let snap = try await store.transact { try $0.loadCursor(metric: metric) }
    #expect(snap?.epoch == 3)
    #expect(snap?.anchorBlob == Data([0xCC, 0xDD]))
    let row = try await store.transact { try $0.loadCensus(metric: metric, day: "2024-01-01") }
    #expect(row?.sampleCount == 1)
    let dirty = try await store.transact { try $0.dirtyDays(metric: metric) }
    #expect(dirty == ["2024-01-01"])
    let pending = try await store.transact { try $0.pendingBatches() }
    #expect(pending == [
        PendingBatch(id: BatchID(rawValue: "b"), payloadURL: "/tmp/x", expectedRecords: 2)
    ])
    try await store.transact {
        try $0.recordDelivery(
            DeliveryReceipt(batchID: BatchID(rawValue: "b"), accepted: 1, statusOnly: false)
        )
    }
    #expect(try await store.transact { try $0.pendingBatches() }.count == 1)
    try await store.transact {
        try $0.recordDelivery(
            DeliveryReceipt(batchID: BatchID(rawValue: "b"), accepted: 2, statusOnly: false)
        )
    }
    #expect(try await store.transact { try $0.pendingBatches() }.isEmpty)
}

@Test func checkpointEnvelopeRoundTripsAndRejectsForwardVersions() throws {
    let envelope = CheckpointEnvelope(
        tzDatabaseVersion: "2024a",
        epoch: 9,
        adapterAnchor: Data([0xAB, 0xCD])
    )
    let restored = try CheckpointEnvelope.decoded(envelope.encoded())
    #expect(restored.tzDatabaseVersion == "2024a")
    #expect(restored.epoch == 9)
    #expect(restored.adapterAnchor == Data([0xAB, 0xCD]))
    #expect(
        envelope.encoded() == Data([
            0x4F, 0x48, 0x45, 0x43,
            0x01,
            0x00, 0x05,
            0x32, 0x30, 0x32, 0x34, 0x61,
            0x00, 0x00, 0x00, 0x09,
            0x00, 0x00, 0x00, 0x02,
            0xAB, 0xCD,
        ])
    )
    #expect(throws: CheckpointError.corrupt) {
        _ = try CheckpointEnvelope.decoded(Data("nope".utf8))
    }
    var forward = envelope.encoded()
    forward[4] = UInt8(CheckpointEnvelope.currentFormat + 1)
    #expect(throws: CheckpointError.unsupportedFormat) {
        _ = try CheckpointEnvelope.decoded(forward)
    }
}

@Test func corruptCheckpointFailsClosedWithoutResettingTheCursor() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let store = MemoryStateStore()
    store.transaction.cursors[metric] = CursorSnapshot(
        metric: metric,
        epoch: 1,
        anchorBlob: Data("torn".utf8)
    )
    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-corrupt-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    let run = ExportRun(
        source: FixtureSource(pages: []),
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    )
    await #expect(throws: CheckpointError.corrupt) {
        _ = try await run.run()
    }
    #expect(store.transaction.cursors[metric]?.anchorBlob == Data("torn".utf8))
    #expect(store.transaction.journal.last?.outcomeKind == "failed")
    #expect(store.transaction.journal.last?.detail == "anchor_undecodable")
}

/// Records whether it was asked for anything, so a test can prove a run never read.
private final class ReadCountingSource: SampleSource, @unchecked Sendable {
    let page: SamplePage
    private(set) var reads = 0

    init(page: SamplePage) { self.page = page }

    func page(metric: MetricID, afterAnchor: Data?) async throws -> SamplePage {
        reads += 1
        return page
    }
}

private func anchorHoldFixture(
    metric: MetricID,
    samples: [SampleRecord]
) throws -> (MemoryStateStore, ReadCountingSource, URL) {
    let store = MemoryStateStore()
    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-anchor-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    let page = SamplePage(
        samples: samples,
        tombstones: [],
        metric: metric,
        anchorBlob: Data([9]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    return (store, ReadCountingSource(page: page), dest)
}

@Test func exportRunChecksDestinationScopeBeforeReadingTheSource() async throws {
    let metric = MetricID(rawValue: "heart_rate")
    let page = SamplePage(
        samples: [],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([1]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let source = ReadCountingSource(page: page)
    let store = MemoryStateStore()
    let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-scope-read-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let scope = try DestinationExportScope(
        destinationID: "local-file",
        metrics: [MetricID(rawValue: "step_count")],
        startInclusive: Date(timeIntervalSince1970: 0)
    )
    let run = ExportRun(
        source: source,
        destination: .testing(LocalFileSink(directory: destination)),
        store: store,
        metric: metric,
        scratchDirectory: destination,
        envelope: testEnvelope(),
        scope: scope
    )

    await #expect(
        throws: ExportScopeViolation.metricNotSelected(
            destinationID: "local-file",
            metric: metric
        )
    ) {
        try await run.run()
    }
    #expect(source.reads == 0)
}

/// The metric has exported before, so an absent cursor is a lost anchor, not a first
/// run. Reading with no anchor would send the whole store again (QA-17).
@Test func aLostAnchorHoldsTheMetricInsteadOfReExportingEverything() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let (store, source, dest) = try anchorHoldFixture(
        metric: metric,
        samples: [heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")]
    )
    try await store.transact {
        try $0.upsertEmittedIndex(
            EmittedIndexRow(
                uuid: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
                metric: metric,
                day: "2026-09-08",
                digest: "d",
                batchID: BatchID(rawValue: "b1")
            )
        )
    }
    let run = ExportRun(
        source: source,
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    )
    let outcome = try await run.run()

    #expect(outcome.kind.rawValue == "failed")
    #expect(source.reads == 0)
    #expect(try await store.transact { try $0.pendingBatches() }.isEmpty)
    #expect(store.transaction.journal.last?.detail == "anchor_invalidated")
    let hold = try #require(store.transaction.anchorHolds[metric])
    #expect(hold.reason == .cursorLost)
    #expect(hold.lastEmittedDay == "2026-09-08")
    #expect(hold.decision == nil)

    // Still held on the next wake: the state is recoverable, not self-clearing.
    let second = try await run.run()
    #expect(second.kind.rawValue == "failed")
    #expect(source.reads == 0)
    #expect(store.transaction.journal.last?.detail == "anchor_hold")
}

/// The only way past a hold is a decision that was recorded before the run.
@Test func authorisingReExportIsWhatLetsTheHistoryGoOutAgain() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let (store, source, dest) = try anchorHoldFixture(
        metric: metric,
        samples: [heartSample("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")]
    )
    try await store.transact {
        try $0.upsertAnchorHold(
            AnchorHold(
                metric: metric,
                reason: .cursorLost,
                detectedAtEpoch: 0,
                lastEmittedDay: "2026-09-08",
                decision: .reexportAuthorized
            )
        )
    }
    let run = ExportRun(
        source: source,
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    )
    let outcome = try await run.run()

    #expect(outcome.kind.rawValue != "failed")
    #expect(source.reads == 1)
    #expect(store.transaction.anchorHolds[metric] == nil)
}

/// A run that resumed from an anchor and got the whole store back has an anchor that no
/// longer means what it says. The flood is dropped rather than queued.
@Test func aDeltaThatReturnsTheWholeStoreIsHeldInsteadOfEnqueued() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let uuids = [
        "cccccccc-cccc-cccc-cccc-cccccccccccc",
        "dddddddd-dddd-dddd-dddd-dddddddddddd",
        "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
    ]
    let (store, source, dest) = try anchorHoldFixture(
        metric: metric,
        samples: uuids.map { heartSample($0) }
    )
    try await store.transact {
        try $0.commitBatch(
            PendingBatch(
                id: BatchID(rawValue: "seed"),
                payloadURL: dest.appendingPathComponent("seed").path,
                expectedRecords: 0,
                byteCount: 0,
                metric: metric,
                createdAtEpoch: 0
            ),
            advancing: CursorAdvance(
                page: SamplePage(
                    samples: [],
                    tombstones: [],
                    metric: metric,
                    anchorBlob: Data([1]),
                    observedThrough: Date(timeIntervalSince1970: 0)
                ),
                epoch: 1
            )
        )
    }
    let run = ExportRun(
        source: source,
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch"),
        envelope: testEnvelope(),
        replaySampleLimit: 2
    )
    let outcome = try await run.run()

    #expect(outcome.kind.rawValue == "failed")
    #expect(store.transaction.journal.last?.detail == "anchor_invalidated")
    let hold = try #require(store.transaction.anchorHolds[metric])
    #expect(hold.reason == .replaySuspected)
    #expect(hold.observedSamples == 3)
    let queued = try await store.transact { try $0.pendingBatches() }
    #expect(queued.map(\.id.rawValue) == ["seed"])
}

@Test func theReplayBoundIsAboveAnyPlausibleIncrement() {
    #expect(AnchorGuard.implausibleDeltaSamples == 50_000)
    #expect(
        !AnchorGuard.replayIsSuspected(resumedFromAnchor: true, sampleCount: 50_000)
    )
    #expect(AnchorGuard.replayIsSuspected(resumedFromAnchor: true, sampleCount: 50_001))
    // A first run legitimately returns everything; it is not a replay.
    #expect(!AnchorGuard.replayIsSuspected(resumedFromAnchor: false, sampleCount: 500_000))
    #expect(!AnchorGuard.cursorIsLost(hasCursor: false, lastEmittedDay: nil))
    #expect(AnchorGuard.cursorIsLost(hasCursor: false, lastEmittedDay: "2026-09-08"))
    #expect(!AnchorGuard.cursorIsLost(hasCursor: true, lastEmittedDay: "2026-09-08"))
}

/// QA-14: the line a user reads has to answer "is it working" and, when it is not,
/// "why". A stored state cannot answer the first, because a destination that succeeded
/// and then stopped keeps saying healthy for as long as nobody recomputes it.
@Test func theDestinationLineAgesAndNamesItsReason() {
    let day: TimeInterval = 86_400
    let base = DestinationStatusSnapshot(
        destinationID: "ha",
        destinationLabel: "Home Assistant",
        enabled: true,
        lastOutcome: "success",
        lastSuccessEpoch: 1_000_000,
        errorClass: ErrorClass.none.rawValue,
        staleThresholdSeconds: day,
        overdueThresholdSeconds: 7 * day,
        writtenAtEpoch: 1_000_000
    )
    func line(_ snapshot: DestinationStatusSnapshot, at epoch: TimeInterval) -> String {
        DestinationStatusLine.render(snapshot, nowEpoch: epoch) { _ in "a moment ago" }
    }

    #expect(line(base, at: 1_000_060).contains("healthy"))
    // Same snapshot, later reading: the answer has to change without anything running.
    #expect(line(base, at: 1_000_000 + (2 * day)).contains("stale"))
    #expect(line(base, at: 1_000_000 + (8 * day)).contains("overdue"))
    // A success does not carry a reason code, so nothing is appended.
    #expect(!line(base, at: 1_000_060).contains(ErrorClass.none.rawValue))

    var failed = base
    failed.lastOutcome = "failed"
    failed.state = .failing
    failed.errorClass = ErrorClass.destinationUnreachable.rawValue
    let failedLine = line(failed, at: 1_000_060)
    #expect(failedLine.contains("failing"))
    #expect(failedLine.contains(ErrorClass.destinationUnreachable.rawValue))
    #expect(
        failedLine.contains(
            ErrorClassManifest.record(for: .destinationUnreachable).userFacingCopy
        )
    )
    #expect(failedLine.contains("last success"))
    #expect(DestinationStatusLine.compactFailure(base) == nil)
    #expect(
        DestinationStatusLine.compactFailure(failed)
            == ErrorClass.destinationUnreachable.rawValue
    )
}

@Test func queueAdmissionEvictsOldestBatchesAndRecordsGaps() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([1]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let store = MemoryStateStore()
    let policy = QueuePolicy(cap: 10, lowWatermark: 6)
    try await store.transact {
        try $0.commitBatch(
            PendingBatch(
                id: BatchID(rawValue: "old"),
                payloadURL: "/tmp/old",
                expectedRecords: 1,
                byteCount: 8,
                metric: metric,
                rangeStartDay: "2024-01-01",
                rangeEndDay: "2024-01-02"
            ),
            advancing: CursorAdvance(page: page, epoch: 1)
        )
    }
    let incoming = PendingBatch(
        id: BatchID(rawValue: "new"),
        payloadURL: "/tmp/new",
        expectedRecords: 1,
        byteCount: 8
    )
    let victims = try await store.transact { tx in
        let evicted = try QueueAdmission.makeRoom(for: incoming.byteCount, on: tx, policy: policy)
        try tx.commitBatch(incoming, advancing: CursorAdvance(page: page, epoch: 2))
        return evicted
    }
    #expect(victims.map(\.id.rawValue) == ["old"])
    #expect(try store.transaction.pendingBatches().map(\.id.rawValue) == ["new"])
    #expect(
        store.transaction.gaps.map(\.rangeDescription)
            == ["queue_eviction:2024-01-01:2024-01-02"]
    )
    #expect(store.transaction.gaps.first?.metric == metric)
    await #expect(throws: QueueAdmissionError.blocked) {
        try await store.transact { tx in
            _ = try QueueAdmission.makeRoom(
                for: 100,
                on: tx,
                policy: policy
            )
        }
    }
}

@Test func queueAdmissionSkipsPinnedReExportAndBlocksWhenOnlyPinnedRemain() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([1]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let store = MemoryStateStore()
    let policy = QueuePolicy(cap: 30, lowWatermark: 20)
    try await store.transact {
        try $0.commitBatch(
            PendingBatch(
                id: BatchID(rawValue: "pinned-reexport"),
                payloadURL: "/tmp/pinned",
                expectedRecords: 1,
                byteCount: 10,
                metric: metric,
                rangeStartDay: "2024-01-01",
                rangeEndDay: "2024-01-02",
                evictionClass: .pinned
            ),
            advancing: CursorAdvance(page: page, epoch: 1)
        )
        try $0.enqueuePending(
            PendingBatch(
                id: BatchID(rawValue: "live-delta"),
                payloadURL: "/tmp/live",
                expectedRecords: 1,
                byteCount: 18,
                metric: metric,
                rangeStartDay: "2024-01-03",
                rangeEndDay: "2024-01-03"
            )
        )
    }
    let incoming = PendingBatch(
        id: BatchID(rawValue: "newer-live"),
        payloadURL: "/tmp/newer",
        expectedRecords: 1,
        byteCount: 8
    )
    let victims = try await store.transact { tx in
        let evicted = try QueueAdmission.makeRoom(for: incoming.byteCount, on: tx, policy: policy)
        try tx.commitBatch(incoming, advancing: CursorAdvance(page: page, epoch: 2))
        return evicted
    }
    #expect(victims.map(\.id.rawValue) == ["live-delta"])
    #expect(
        try store.transaction.pendingBatches().map(\.id.rawValue)
            == ["pinned-reexport", "newer-live"]
    )
    await #expect(throws: QueueAdmissionError.blocked) {
        try await store.transact { tx in
            _ = try QueueAdmission.makeRoom(for: 21, on: tx, policy: policy)
        }
    }
    #expect(try store.transaction.pendingBatches().map(\.id.rawValue)
        == ["pinned-reexport", "newer-live"])
}

@Test func reExportPinsUntilThePinnedSubBudgetThenJoinsNormalEviction() {
    let policy = QueuePolicy(cap: 40, lowWatermark: 30)
    #expect(policy.pinnedBudget == 10)
    #expect(
        QueueAdmission.evictionClass(
            reason: "gap_reexport",
            pinnedBytes: 0,
            incomingBytes: 10,
            policy: policy
        ) == .pinned
    )
    #expect(
        QueueAdmission.evictionClass(
            reason: "gap_reexport",
            pinnedBytes: 10,
            incomingBytes: 1,
            policy: policy
        ) == .normal
    )
    #expect(
        QueueAdmission.evictionClass(
            reason: "backfill",
            pinnedBytes: 0,
            incomingBytes: 1,
            policy: policy
        ) == .normal
    )
}

@Test func queueExpiryDeletesSevenDayOldPayloadsAndRecordsTamperEvidentEvidence() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-queue-expiry-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let expiredURL = directory.appendingPathComponent("expired.ndjson")
    let freshURL = directory.appendingPathComponent("fresh.ndjson")
    let legacyURL = directory.appendingPathComponent("legacy.ndjson")
    for url in [expiredURL, freshURL, legacyURL] {
        try Data("payload".utf8).write(to: url)
    }
    let store = MemoryStateStore()
    try await store.transact { tx in
        try tx.enqueuePending(
            PendingBatch(
                id: BatchID(rawValue: "expired"),
                payloadURL: expiredURL.path,
                expectedRecords: 3,
                byteCount: 7,
                metric: MetricCatalog.heartRate.id,
                createdAtEpoch: 100
            )
        )
        try tx.enqueuePending(
            PendingBatch(
                id: BatchID(rawValue: "fresh"),
                payloadURL: freshURL.path,
                expectedRecords: 2,
                byteCount: 7,
                metric: MetricCatalog.stepCount.id,
                createdAtEpoch: 101
            )
        )
        try tx.enqueuePending(
            PendingBatch(
                id: BatchID(rawValue: "legacy"),
                payloadURL: legacyURL.path,
                expectedRecords: 1,
                byteCount: 7,
                metric: MetricCatalog.bodyMass.id
            )
        )
    }

    let result = try await store.expirePending(
        nowEpoch: 100 + QueueExpiry.timeToLive,
        destination: "local-file"
    )
    #expect(result == QueueExpiryResult(expiredBatches: 1, expiredRecords: 3, expiredBytes: 7))
    #expect(!FileManager.default.fileExists(atPath: expiredURL.path))
    #expect(FileManager.default.fileExists(atPath: freshURL.path))
    #expect(FileManager.default.fileExists(atPath: legacyURL.path))
    #expect(try store.transaction.pendingBatches().map(\.id.rawValue) == ["fresh", "legacy"])
    #expect(try store.transaction.loadGaps().last?.rangeDescription == "queue_ttl_expired")
    let ledger = try store.transaction.loadLedger()
    #expect(LedgerChain.verify(ledger) == .valid(head: ledger[0].entryHash, count: 1))
    #expect(ledger[0].outcomeKind == "queue_ttl_expired")
}

@Test func sqlitePendingBatchAndGapPersistReExportRange() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-pending-age-\(UUID().uuidString).sqlite")
    let store = try SQLiteStateStore(path: url.path)
    let pending = PendingBatch(
        id: BatchID(rawValue: "aged"),
        payloadURL: "/tmp/aged",
        expectedRecords: 1,
        byteCount: 2,
        metric: MetricCatalog.heartRate.id,
        createdAtEpoch: 123,
        rangeStartDay: "2024-01-01",
        rangeEndDay: "2024-01-02"
    )
    try await store.transact { try $0.enqueuePending(pending) }
    #expect(try await store.transact { try $0.pendingBatches() } == [pending])
    let gap = GapRecord(
        batchID: pending.id,
        rangeDescription: "queue_eviction:2024-01-01:2024-01-02",
        metric: pending.metric,
        rangeStartDay: pending.rangeStartDay,
        rangeEndDay: pending.rangeEndDay,
        expectedRecords: pending.expectedRecords
    )
    try await store.transact { try $0.evict(pending.id, recording: gap) }
    let restored = try #require(try await store.transact { try $0.loadGaps().first })
    #expect(restored.batchID == gap.batchID)
    #expect(restored.metric == gap.metric)
    #expect(restored.rangeStartDay == gap.rangeStartDay)
    #expect(restored.rangeEndDay == gap.rangeEndDay)
    #expect(restored.expectedRecords == gap.expectedRecords)
    #expect(try await store.transact { try $0.deliveredAccepted() } == 0)
}

@Test func sqlitePersistsDestinationBreakerSnapshot() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-breaker-\(UUID().uuidString).sqlite")
    let store = try SQLiteStateStore(path: url.path)
    let snapshot = BreakerSnapshot(
        state: .open,
        consecutiveFailures: 5,
        openedAt: Date(timeIntervalSince1970: 1)
    )
    try await store.transact {
        try DestinationBreaker.save(snapshot, to: $0, destinationID: "https")
    }
    let restored = try await store.transact {
        try DestinationBreaker.load(from: $0, destinationID: "https")
    }
    #expect(restored.state == .open)
    #expect(restored.consecutiveFailures == 5)
}

@Test func sqlitePersistsEmittedIndexOnCommit() async throws {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-index-\(UUID().uuidString).sqlite")
        .path
    let store = try SQLiteStateStore(path: path)
    let metric = MetricID(rawValue: "heartRate")
    let first = EmittedIndexRow(
        uuid: "11111111-1111-1111-1111-111111111111",
        metric: metric,
        day: "2024-01-01",
        digest: "aa",
        batchID: BatchID(rawValue: "b1")
    )
    let updated = EmittedIndexRow(
        uuid: first.uuid,
        metric: metric,
        day: "2024-01-02",
        digest: "bb",
        batchID: BatchID(rawValue: "b2")
    )
    try await store.transact { try $0.upsertEmittedIndex(first) }
    #expect(try await store.transact { try $0.loadEmittedIndex(uuid: first.uuid) } == first)
    try await store.transact { try $0.upsertEmittedIndex(updated) }
    #expect(try await store.transact { try $0.loadEmittedIndex(uuid: first.uuid) } == updated)
}

@Test func emittedIndexEvictsOldestDayWhenOverCapAndKeepsPinnedMetrics() async throws {
    let store = MemoryStateStore()
    let heart = MetricID(rawValue: "heartRate")
    let mass = MetricCatalog.bodyMass.id
    func page(metric: MetricID, uuid: String, start: String) -> SamplePage {
        let sample = SampleRecord(
            key: RecordKey(uuid: uuid),
            metric: metric,
            start: start,
            end: start,
            timeZoneOffsetMinutes: 0,
            timeZoneSource: .unknown,
            value: 1,
            unit: CanonicalUnit(symbol: "count"),
            observedAt: start
        )
        return SamplePage(
            samples: [sample],
            tombstones: [],
            metric: metric,
            anchorBlob: Data([1]),
            observedThrough: Date(timeIntervalSince1970: 0)
        )
    }
    try await store.transact { tx in
        try EmittedIndex.record(
            page: page(
                metric: mass,
                uuid: "00000000-0000-4000-8000-000000000099",
                start: "2023-06-01T00:00:00Z"
            ),
            batchID: BatchID(rawValue: "pinned"),
            on: tx,
            capBytes: 200,
            bytesPerRow: 40
        )
        for (offset, day) in ["2024-01-01", "2024-01-02", "2024-01-03", "2024-01-04", "2024-01-05"].enumerated() {
            try EmittedIndex.record(
                page: page(
                    metric: heart,
                    uuid: "11111111-1111-4000-8000-00000000000\(offset)",
                    start: "\(day)T00:00:00Z"
                ),
                batchID: BatchID(rawValue: "b\(offset)"),
                on: tx,
                capBytes: 200,
                bytesPerRow: 40
            )
        }
    }
    #expect(try await store.transact { try $0.emittedIndexRowCount() } == 5)
    #expect(
        try await store.transact {
            try $0.loadEmittedIndex(uuid: "11111111-1111-4000-8000-000000000000")
        } == nil
    )
    #expect(
        try await store.transact {
            try $0.loadEmittedIndex(uuid: "00000000-0000-4000-8000-000000000099")
        } != nil
    )
    #expect(try await store.transact { try $0.loadIndexHorizonDay() } == "2024-01-02")
    #expect(
        try await store.transact { try $0.loadVerifiedThroughDay(metric: heart) } == "2024-01-02"
    )
    let journal = try await store.transact { try $0.loadJournal() }
    #expect(journal.contains { $0.detail.contains(EmittedIndexPolicy.horizonJournalToken) })
}

@Test func sqliteEmittedIndexCapEvictsOldestDay() async throws {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-index-cap-\(UUID().uuidString).sqlite")
        .path
    let store = try SQLiteStateStore(path: path)
    let heart = MetricID(rawValue: "heartRate")
    try await store.transact { tx in
        for (offset, day) in ["2024-01-01", "2024-01-02", "2024-01-03", "2024-01-04", "2024-01-05", "2024-01-06"].enumerated() {
            try tx.upsertEmittedIndex(
                EmittedIndexRow(
                    uuid: "22222222-2222-4000-8000-00000000000\(offset)",
                    metric: heart,
                    day: day,
                    digest: "d\(offset)",
                    batchID: BatchID(rawValue: "c\(offset)")
                )
            )
        }
        try EmittedIndex.enforceCap(on: tx, capBytes: 200, bytesPerRow: 40)
    }
    #expect(try await store.transact { try $0.emittedIndexRowCount() } == 5)
    #expect(try await store.transact { try $0.loadIndexHorizonDay() } == "2024-01-02")
    #expect(
        try await store.transact {
            try $0.loadEmittedIndex(uuid: "22222222-2222-4000-8000-000000000000")
        } == nil
    )
}

@Test func verifiedThroughClampsToIndexHorizon() {
    #expect(
        EmittedIndexPolicy.verifiedThrough(
            completeThrough: "2024-06-01T12:00:00Z",
            horizonDay: "2024-01-15"
        ) == "2024-01-15"
    )
    #expect(
        EmittedIndexPolicy.verifiedThrough(
            completeThrough: "2024-01-01T00:00:00Z",
            horizonDay: "2024-06-01"
        ) == "2024-01-01"
    )
}

@Test func censusUndatableClampsVerifiedThroughToHorizon() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let store = MemoryStateStore()
    try await store.transact { tx in
        try tx.upsertIndexHorizonDay("2024-03-01")
        let page = SamplePage(
            samples: [],
            tombstones: [
                TombstoneRecord(
                    key: RecordKey(uuid: "deadbeef-0000-4000-8000-000000000001"),
                    metric: metric
                )
            ],
            metric: metric,
            anchorBlob: Data([1]),
            observedThrough: Date(timeIntervalSince1970: 0)
        )
        try Census.apply(page: page, to: tx, atEpoch: 1)
    }
    #expect(
        try await store.transact { try $0.loadVerifiedThroughDay(metric: metric) } == "2024-03-01"
    )
}

@Test func censusAccumulatesAcrossTwoPagesSameDay() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let store = MemoryStateStore()
    let a = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    let b = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    let page1 = SamplePage(
        samples: [heartSample(a)],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([1]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let page2 = SamplePage(
        samples: [heartSample(b)],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([2]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    try await store.transact { tx in
        try Census.apply(page: page1, to: tx)
        try EmittedIndex.record(page: page1, batchID: BatchID(rawValue: "b1"), on: tx)
        try Census.apply(page: page2, to: tx)
        try EmittedIndex.record(page: page2, batchID: BatchID(rawValue: "b2"), on: tx)
    }
    let row = try await store.transact { try $0.loadCensus(metric: metric, day: "2024-01-01") }
    #expect(row?.sampleCount == 2)
    #expect(row?.digest == Census.digestUUIDs([a, b]))
    #expect(Census.digestUUIDs([a, b]) == Census.digestUUIDs([b, a]))
}

@Test func censusApplyDecrementsOnTombstoneWhenUuidInEmittedIndex() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let store = MemoryStateStore()
    let uuid = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    let page = SamplePage(
        samples: [heartSample(uuid)],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([1]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let deletion = SamplePage(
        samples: [],
        tombstones: [TombstoneRecord(key: RecordKey(uuid: uuid), metric: metric)],
        metric: metric,
        anchorBlob: Data([2]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    try await store.transact { tx in
        try Census.apply(page: page, to: tx)
        try EmittedIndex.record(page: page, batchID: BatchID(rawValue: "b1"), on: tx)
        try Census.apply(page: deletion, to: tx)
    }
    let row = try await store.transact { try $0.loadCensus(metric: metric, day: "2024-01-01") }
    #expect(row?.sampleCount == 0)
    #expect(row?.digest == "0")
    #expect(try await store.transact { try $0.loadEmittedIndex(uuid: uuid) } == nil)
    #expect(try await store.transact { try $0.dirtyDays(metric: metric) } == ["2024-01-01"])
}

@Test func deleteOnlyAnchoredPageCommitsAndDeliversATombstone() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let uuid = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    let page = SamplePage(
        samples: [],
        tombstones: [
            TombstoneRecord(key: RecordKey(uuid: uuid), metric: metric),
        ],
        metric: metric,
        anchorBlob: Data([0xD1]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-delete-only-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: destination) }
    try FileManager.default.createDirectory(
        at: destination,
        withIntermediateDirectories: true
    )
    let store = MemoryStateStore()
    let outcome = try await ExportRun(
        source: FixtureSource(pages: [page]),
        destination: .testing(LocalFileSink(directory: destination)),
        store: store,
        metric: metric,
        scratchDirectory: destination.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    ).run()

    #expect(outcome.kind == .success)
    #expect(try store.transaction.loadCursor(metric: metric)?.anchorBlob == Data([0xD1]))
    #expect(try store.transaction.pendingBatches().isEmpty)
    let payload = try FileManager.default.contentsOfDirectory(
        at: destination,
        includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "ndjson" }
    .map { try String(contentsOf: $0, encoding: .utf8) }
    .joined()
    #expect(payload.contains(uuid))
    #expect(payload.contains("\"kind\":\"tombstone\""))
}

@Test func censusTombstoneWithoutEmittedIndexJournalsUndatable() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let store = MemoryStateStore()
    let page = SamplePage(
        samples: [],
        tombstones: [
            TombstoneRecord(
                key: RecordKey(uuid: "deadbeef-dead-beef-dead-beefdeadbeef"),
                metric: metric
            )
        ],
        metric: metric,
        anchorBlob: Data([1]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    _ = try await store.transact { tx in
        try Census.apply(page: page, to: tx)
    }
    #expect(store.transaction.journal.contains { event in
        DeletionUndatable.parse(event.detail)?.uuid
            == "deadbeef-dead-beef-dead-beefdeadbeef"
    })
    #expect(try await store.transact { try $0.loadCensus(metric: metric, day: "2024-01-01") } == nil)
}

@Test func deletionUndatableSweepRebuildsCensusFromObservations() async throws {
    let metric = MetricCatalog.heartRate.id
    let kept = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    let lost = "deadbeef-dead-beef-dead-beefdeadbeef"
    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-undatable-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dest) }
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    let store = MemoryStateStore()
    let keptSample = heartSample(kept)
    try await store.transact { tx in
        try tx.commitBatch(
            PendingBatch(
                id: BatchID(rawValue: "prior"),
                payloadURL: dest.appendingPathComponent("prior.ndjson").path,
                expectedRecords: 1
            ),
            advancing: CursorAdvance(
                page: SamplePage(
                    samples: [keptSample],
                    tombstones: [],
                    metric: metric,
                    anchorBlob: Data([0x00]),
                    observedThrough: Date(timeIntervalSince1970: 0)
                ),
                epoch: 1
            )
        )
        try tx.upsertCensus(
            CensusRow(
                metric: metric,
                day: "2024-01-01",
                sampleCount: 2,
                digest: Census.digestUUIDs([kept, lost])
            )
        )
        try tx.upsertEmittedIndex(
            EmittedIndexRow(
                uuid: kept,
                metric: metric,
                day: "2024-01-01",
                digest: Census.digestUUIDs([kept]),
                batchID: BatchID(rawValue: "kept")
            )
        )
    }
    let outcome = try await ExportRun(
        source: FixtureSource(
            pages: [
                SamplePage(
                    samples: [],
                    tombstones: [
                        TombstoneRecord(key: RecordKey(uuid: lost), metric: metric)
                    ],
                    metric: metric,
                    anchorBlob: Data([0xD1]),
                    observedThrough: Date(timeIntervalSince1970: 0)
                )
            ]
        ),
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch"),
        envelope: testEnvelope(),
        observations: FixtureDays(byDay: ["2024-01-01": [keptSample]])
    ).run()
    #expect(outcome.kind == .success)
    let parsed = store.transaction.journal.compactMap { DeletionUndatable.parse($0.detail) }
    #expect(parsed.contains { $0.uuid == lost && $0.metric == metric })
    let row = try await store.transact { try $0.loadCensus(metric: metric, day: "2024-01-01") }
    #expect(row?.sampleCount == 1)
    #expect(row?.digest == Census.digestUUIDs([kept]))
    let payloads = try FileManager.default.contentsOfDirectory(
        at: dest,
        includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "ndjson" }
    .map { try String(contentsOf: $0, encoding: .utf8) }
    .joined()
    #expect(payloads.contains(DeletionUndatable.token))
}

@Test func cellCensusFoldIsOrderIndependent() {
    let left = ReconcileCompare.fold(uuids: ["a", "b", "c"])
    let right = ReconcileCompare.fold(uuids: ["c", "a", "b"])
    #expect(left == right)
}

@Test func reconcileCompareDetectsIdenticalCell() {
    let uuids = ["aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"]
    let observed = ReconcileCompare.fold(uuids: uuids)
    let stored = CensusRow(
        metric: MetricID(rawValue: "heartRate"),
        day: "2024-01-01",
        sampleCount: observed.count,
        digest: String(observed.digestXor, radix: 16)
    )
    #expect(ReconcileCompare.compare(stored: stored, observed: observed) == .identical)
}

@Test func reconcileCompareDetectsCountGreater() {
    let stored = CensusRow(
        metric: MetricID(rawValue: "heartRate"),
        day: "2024-01-01",
        sampleCount: 1,
        digest: "1"
    )
    let observed = ReconcileCompare.fold(uuids: ["a", "b"])
    #expect(ReconcileCompare.compare(stored: stored, observed: observed) == .countGreater)
}

@Test func reconcileCompareDetectsCountSmallerAndYieldsTombstoneUUIDs() {
    let metric = MetricID(rawValue: "heartRate")
    let stored = CensusRow(metric: metric, day: "2024-01-01", sampleCount: 2, digest: "1")
    let observed = ReconcileCompare.fold(uuids: ["keep"])
    #expect(ReconcileCompare.compare(stored: stored, observed: observed) == .countSmaller)
    let indexed = [
        EmittedIndexRow(
            uuid: "gone",
            metric: metric,
            day: "2024-01-01",
            digest: "x",
            batchID: BatchID(rawValue: "b")
        ),
        EmittedIndexRow(
            uuid: "keep",
            metric: metric,
            day: "2024-01-01",
            digest: "y",
            batchID: BatchID(rawValue: "b")
        ),
    ]
    #expect(
        ReconcileCompare.absentUUIDs(indexed: indexed, observedUUIDs: ["keep"]) == ["gone"]
    )
    let tombs = ReconcileCompare.tombstonesForAbsence(
        indexed: indexed,
        observedUUIDs: ["keep"],
        metric: metric
    )
    #expect(tombs.map(\.key.uuid) == ["gone"])
}

@Test func reconcileCompareDetectsDigestMismatchWithEqualCount() {
    let stored = CensusRow(
        metric: MetricID(rawValue: "heartRate"),
        day: "2024-01-01",
        sampleCount: 1,
        digest: "deadbeef"
    )
    let observed = ReconcileCompare.fold(uuids: ["aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"])
    #expect(ReconcileCompare.compare(stored: stored, observed: observed) == .digestMismatch)
}

@Test func reconcilePlannerIsCleanWhenCellMatches() {
    let metric = MetricID(rawValue: "heartRate")
    let uuid = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    let observed = [heartSample(uuid)]
    let fold = ReconcileCompare.fold(uuids: [uuid])
    let stored = CensusRow(
        metric: metric,
        day: "2024-01-01",
        sampleCount: fold.count,
        digest: String(fold.digestXor, radix: 16)
    )
    let plan = ReconcilePlanner.planDay(
        metric: metric,
        day: "2024-01-01",
        stored: stored,
        indexed: [
            EmittedIndexRow(
                uuid: uuid,
                metric: metric,
                day: "2024-01-01",
                digest: "x",
                batchID: BatchID(rawValue: "b")
            )
        ],
        observed: observed
    )
    #expect(plan.isClean)
    #expect(plan.outcome == .identical)
}

@Test func reconcilePlannerReemitsWhenHealthKitHasMoreSamples() {
    let metric = MetricID(rawValue: "heartRate")
    let stored = CensusRow(metric: metric, day: "2024-01-01", sampleCount: 0, digest: "0")
    let plan = ReconcilePlanner.planDay(
        metric: metric,
        day: "2024-01-01",
        stored: stored,
        indexed: [],
        observed: [heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")]
    )
    #expect(plan.outcome == .countGreater)
    #expect(plan.repairs == [.reemitDay])
}

@Test func reconcilePlannerEmitsAbsenceTombstonesWhenSamplesDisappear() {
    let metric = MetricID(rawValue: "heartRate")
    let gone = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    let keep = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    // Store claims two samples; observation has one.
    let stored = CensusRow(metric: metric, day: "2024-01-01", sampleCount: 2, digest: "1")
    let indexed = [
        EmittedIndexRow(uuid: keep, metric: metric, day: "2024-01-01", digest: "a", batchID: BatchID(rawValue: "b")),
        EmittedIndexRow(uuid: gone, metric: metric, day: "2024-01-01", digest: "b", batchID: BatchID(rawValue: "b")),
    ]
    let plan = ReconcilePlanner.planDay(
        metric: metric,
        day: "2024-01-01",
        stored: stored,
        indexed: indexed,
        observed: [heartSample(keep)]
    )
    #expect(plan.outcome == .countSmaller)
    #expect(plan.repairs.contains(.reemitDay))
    guard case .emitAbsenceTombstones(let tombs) = plan.repairs.first(where: {
        if case .emitAbsenceTombstones = $0 { return true }
        return false
    }) else {
        Issue.record("expected absence tombstones")
        return
    }
    #expect(tombs.map(\.key.uuid) == [gone])
}

@Test func reconcilePlannerTrailingDaysCoversSevenDayWindow() {
    #expect(
        ReconcilePlanner.trailingDays(throughDay: "2024-03-01", count: 7) == [
            "2024-02-24",
            "2024-02-25",
            "2024-02-26",
            "2024-02-27",
            "2024-02-28",
            "2024-02-29",
            "2024-03-01",
        ]
    )
}

@Test func reconcilePlannerBuildsAnInclusiveValidatedFullRange() throws {
    #expect(
        try ReconcilePlanner.days(from: "2024-02-28", through: "2024-03-01") == [
            "2024-02-28",
            "2024-02-29",
            "2024-03-01",
        ]
    )
    #expect(throws: ReconcileRangeError.invalidDay("2024-02-30")) {
        _ = try ReconcilePlanner.days(from: "2024-02-30", through: "2024-03-01")
    }
    #expect(
        throws: ReconcileRangeError.reversed(
            start: "2024-03-02",
            end: "2024-03-01"
        )
    ) {
        _ = try ReconcilePlanner.days(from: "2024-03-02", through: "2024-03-01")
    }
}

@Test func restoreWithoutReliabilityStateFullReconcileRepairsAllAvailableHistory() async throws {
    let metric = MetricCatalog.heartRate.id
    var old = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    old.start = "2023-12-01T10:00:00Z"
    old.end = old.start
    var recent = heartSample("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
    recent.start = "2024-01-01T10:00:00Z"
    recent.end = recent.start
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-full-reconcile-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    // Backups intentionally contain no anchors, census, or emitted index. The
    // restored Health store remains available through date-ranged queries.
    let store = MemoryStateStore()
    let outcome = try await ReconcileSweep(
        observations: FixtureDays(
            byDay: [
                "2023-12-01": [old],
                "2024-01-01": [recent],
            ]
        ),
        destination: .testing(LocalFileSink(directory: root)),
        store: store,
        metric: metric,
        scratchDirectory: root.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    ).runFullHistory(throughDay: "2024-01-01")

    #expect(outcome.kind == .success)
    #expect(try store.transaction.loadCursor(metric: metric) == nil)
    #expect(try store.transaction.loadEmittedIndex(uuid: old.key.uuid) != nil)
    #expect(try store.transaction.loadEmittedIndex(uuid: recent.key.uuid) != nil)
    let payload = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "ndjson" }
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .joined()
    #expect(payload.contains("\"reason\":\"full_reconcile\""))
    #expect(payload.contains(old.key.uuid))
    #expect(payload.contains(recent.key.uuid))
}

@Test func catchUpAdmissionStopsAtSixtyPercentOfCap() {
    let policy = QueuePolicy.production
    #expect(policy.catchUpLimit == policy.cap * 3 / 5)
    #expect(CatchUpAdmission.allows(queuedBytes: 0))
    #expect(CatchUpAdmission.allows(queuedBytes: policy.catchUpLimit - 1))
    #expect(!CatchUpAdmission.allows(queuedBytes: policy.catchUpLimit))
    #expect(!CatchUpAdmission.allows(queuedBytes: policy.catchUpLimit - 10, incomingBytes: 10))
}

@Test func destinationStatusLineShowsAmberCatchUpAdvisory() {
    let snapshot = DestinationStatusSnapshot(
        destinationID: "local-file",
        destinationLabel: "Archive folder",
        enabled: true,
        lastOutcome: "success",
        queueOccupancy: QueueOccupancy.amber.snapshotToken,
        writtenAtEpoch: 1
    )
    let line = DestinationStatusLine.render(snapshot, nowEpoch: 2) { _ in "earlier" }
    #expect(line.contains("Catch-up is parked while the destination queue fills"))
    #expect(
        DestinationStatusLine.queueAdvisory("green") == nil
    )
    #expect(
        DestinationStatusLine.queueAdvisory("red")?
            .contains("data loss is approaching") == true
    )
}

@Test func exportRunWritesAmberQueueOccupancyOnTheDestinationSnapshot() async throws {
    let metric = MetricCatalog.heartRate.id
    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-amber-snap-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dest) }
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    let snapshotURL = dest.appendingPathComponent("widget-status.json")
    let store = MemoryStateStore()
    try await store.transact { tx in
        try tx.enqueuePending(
            PendingBatch(
                id: BatchID(rawValue: "live-delta"),
                payloadURL: "/tmp/live-delta",
                expectedRecords: 1,
                byteCount: QueuePolicy.production.catchUpLimit,
                metric: metric
            )
        )
    }
    let page = SamplePage(
        samples: [heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0x61]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let outcome = try await ExportRun(
        source: FixtureSource(pages: [page]),
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch"),
        envelope: testEnvelope(),
        snapshotURL: snapshotURL
    ).run()
    #expect(outcome.kind == .success)
    let snapshot = try DestinationSnapshotFile.read(from: snapshotURL)
    #expect(snapshot.queueOccupancy == QueueOccupancy.amber.snapshotToken)
    #expect(
        DestinationStatusLine.render(snapshot, nowEpoch: 1) { _ in "earlier" }
            .contains("Catch-up is parked while the destination queue fills")
    )
}

@Test func queueRedStartsAtEightyPercentAndPurgesAttemptCaches() throws {
    let policy = QueuePolicy.production
    #expect(policy.redLimit == policy.cap * 4 / 5)
    #expect(QueueRed.occupancy(queuedBytes: policy.catchUpLimit - 1) == .green)
    #expect(QueueRed.occupancy(queuedBytes: policy.catchUpLimit) == .amber)
    #expect(QueueRed.occupancy(queuedBytes: policy.redLimit) == .red)
    #expect(QueueRed.occupancy(queuedBytes: policy.cap) == .overCap)
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-queue-red-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let attempts = root.appendingPathComponent(QueueRed.attemptsDirectoryName, isDirectory: true)
    try FileManager.default.createDirectory(at: attempts, withIntermediateDirectories: true)
    let body = attempts.appendingPathComponent("delivery.body")
    try Data("payload".utf8).write(to: body)
    #expect(try QueueRed.purgeAttemptCaches(root: root) == 1)
    #expect(!FileManager.default.fileExists(atPath: body.path))
}

@Test func sqliteWalCheckpointTruncateDoesNotThrow() throws {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-wal-red-\(UUID().uuidString).sqlite")
        .path
    let store = try SQLiteStateStore(path: path)
    try store.checkpointWAL()
}

@Test func scheduledReconcileIsDueOnFirstRunAndAfterTheInterval() {
    #expect(ScheduledReconcile.due(lastEpoch: nil, nowEpoch: 100))
    #expect(!ScheduledReconcile.due(lastEpoch: 100, nowEpoch: 100 + 86_399))
    #expect(ScheduledReconcile.due(lastEpoch: 100, nowEpoch: 100 + 86_400))
}

@Test func reconcileSweepParksWhenCatchUpOccupancyIsAmber() async throws {
    let metric = MetricCatalog.heartRate.id
    var sample = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    sample.start = "2024-01-01T10:00:00Z"
    sample.end = sample.start
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-catchup-park-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let store = MemoryStateStore()
    try await store.transact { tx in
        try tx.enqueuePending(
            PendingBatch(
                id: BatchID(rawValue: "live-delta"),
                payloadURL: "/tmp/live-delta",
                expectedRecords: 1,
                byteCount: QueuePolicy.production.catchUpLimit,
                metric: metric
            )
        )
    }
    let outcome = try await ReconcileSweep(
        observations: FixtureDays(byDay: ["2024-01-01": [sample]]),
        destination: .testing(LocalFileSink(directory: root)),
        store: store,
        metric: metric,
        scratchDirectory: root.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    ).runFullHistory(throughDay: "2024-01-01")
    #expect(outcome.kind == .partial)
    #expect(outcome.partialCause == CatchUpAdmission.parkedJournalDetail)
    let pending = try store.transaction.pendingBatches()
    #expect(pending.map(\.id.rawValue) == ["live-delta"])
}

@Test func catchUpAdmissionParksOpenHaltedAndBlockedBreakers() {
    #expect(CatchUpAdmission.allows(breaker: BreakerSnapshot()))
    #expect(CatchUpAdmission.allows(breaker: BreakerSnapshot(state: .halfOpen)))
    #expect(!CatchUpAdmission.allows(breaker: BreakerSnapshot(state: .open)))
    #expect(!CatchUpAdmission.allows(breaker: BreakerSnapshot(state: .blockedNeedsUser)))
    #expect(!CatchUpAdmission.allows(breaker: BreakerSnapshot(state: .halted)))
    #expect(!CatchUpAdmission.allows(breaker: BreakerSnapshot(state: .failingPersistently)))
}

@Test func queueGapReExportParksWhenDestinationStillBroken() async throws {
    let metric = MetricCatalog.heartRate.id
    var sample = heartSample("dddddddd-dddd-dddd-dddd-dddddddddddd")
    sample.start = "2024-01-15T10:00:00Z"
    sample.end = sample.start
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-gap-reexport-broken-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let store = MemoryStateStore()
    try await store.transact { tx in
        try tx.enqueuePending(
            PendingBatch(
                id: BatchID(rawValue: "live-delta"),
                payloadURL: "/tmp/live-delta",
                expectedRecords: 1,
                byteCount: 8,
                metric: metric
            )
        )
        try DestinationBreaker.save(
            BreakerSnapshot(
                state: .open,
                consecutiveFailures: 5,
                openedAt: Date(timeIntervalSince1970: 1)
            ),
            to: tx,
            destinationID: "local-file"
        )
    }
    let outcome = try await ReconcileSweep(
        observations: FixtureDays(byDay: ["2024-01-15": [sample]]),
        destination: .testing(
            ThrowingSink(error: .destinationUnreachable)
        ),
        store: store,
        metric: metric,
        scratchDirectory: root.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    ).run(
        gap: GapRecord(
            batchID: BatchID(rawValue: "evicted"),
            rangeDescription: "queue_eviction:2024-01-15:2024-01-15",
            metric: metric,
            rangeStartDay: "2024-01-15",
            rangeEndDay: "2024-01-15"
        )
    )
    #expect(outcome.kind == .partial)
    #expect(outcome.partialCause == CatchUpAdmission.destinationParkedJournalDetail)
    let pending = try store.transaction.pendingBatches()
    #expect(pending.map(\.id.rawValue) == ["live-delta"])
}

@Test func queueGapReExportReadsTheRecordedEvictedWindow() async throws {
    let metric = MetricCatalog.heartRate.id
    var sample = heartSample("cccccccc-cccc-cccc-cccc-cccccccccccc")
    sample.start = "2024-01-15T10:00:00Z"
    sample.end = sample.start
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-gap-reexport-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let store = MemoryStateStore()
    let outcome = try await ReconcileSweep(
        observations: FixtureDays(byDay: ["2024-01-15": [sample]]),
        destination: .testing(LocalFileSink(directory: root)),
        store: store,
        metric: metric,
        scratchDirectory: root.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    ).run(
        gap: GapRecord(
            batchID: BatchID(rawValue: "evicted"),
            rangeDescription: "queue_eviction:2024-01-15:2024-01-15",
            metric: metric,
            rangeStartDay: "2024-01-15",
            rangeEndDay: "2024-01-15"
        )
    )

    #expect(outcome.kind == .success)
    let payload = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "ndjson" }
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .joined()
    #expect(payload.contains("\"reason\":\"gap_reexport\""))
    #expect(payload.contains(sample.key.uuid))
}

@Test func queueGapReExportEnqueuesAsPinnedUnderTheSubBudget() async throws {
    let metric = MetricCatalog.heartRate.id
    var sample = heartSample("dddddddd-dddd-dddd-dddd-dddddddddddd")
    sample.start = "2024-01-15T10:00:00Z"
    sample.end = sample.start
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-gap-reexport-pin-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let store = MemoryStateStore()
    await #expect(throws: DestinationSendError.destinationUnreachable) {
        try await ReconcileSweep(
            observations: FixtureDays(byDay: ["2024-01-15": [sample]]),
            destination: .testing(
                ThrowingSink(error: .destinationUnreachable)
            ),
            store: store,
            metric: metric,
            scratchDirectory: root.appendingPathComponent("scratch"),
            envelope: testEnvelope()
        ).run(
            gap: GapRecord(
                batchID: BatchID(rawValue: "evicted"),
                rangeDescription: "queue_eviction:2024-01-15:2024-01-15",
                metric: metric,
                rangeStartDay: "2024-01-15",
                rangeEndDay: "2024-01-15"
            )
        )
    }
    let pending = try store.transaction.pendingBatches()
    #expect(pending.count == 1)
    #expect(pending[0].evictionClass == .pinned)
}

@Test func sqlitePendingBatchesRoundTripPinnedEvictionClass() async throws {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-pinned-\(UUID().uuidString).sqlite")
        .path
    defer { try? FileManager.default.removeItem(atPath: path) }
    let first = try SQLiteStateStore(path: path)
    try await first.transact {
        try $0.enqueuePending(
            PendingBatch(
                id: BatchID(rawValue: "pinned"),
                payloadURL: "/tmp/pinned",
                expectedRecords: 2,
                byteCount: 9,
                metric: MetricCatalog.heartRate.id,
                evictionClass: .pinned
            )
        )
    }
    let reopened = try SQLiteStateStore(path: path)
    let loaded = try await reopened.transact { try $0.pendingBatches() }
    #expect(loaded.count == 1)
    #expect(loaded[0].evictionClass == .pinned)
    #expect(loaded[0].byteCount == 9)
}

@Test func deletionWithoutHealthKitCallbackIsRepairedByReconcile() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let keep = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    let gone = heartSample("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
    // HealthKit supplied no deletion tombstone/callback for `gone`; only the
    // later date-ranged observation reveals its absence.
    let page = SamplePage(
        samples: [keep, gone],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0xAA]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-sweep-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    let store = MemoryStateStore()
    let first = ExportRun(
        source: FixtureSource(pages: [page]),
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    )
    _ = try await first.run()
    let cursor = try store.transaction.loadCursor(metric: metric)
    let seal = HashLedgerSeal(secret: "reconcile-device")
    let sealURL = dest.appendingPathComponent("reconcile-ledger-seal.json")
    let snapshotURL = dest.appendingPathComponent("reconcile-status.json")
    let sweep = ReconcileSweep(
        observations: FixtureDays(byDay: ["2024-01-01": [keep]]),
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch-sweep"),
        envelope: testEnvelope(),
        snapshotURL: snapshotURL,
        ledgerHeadSeal: seal,
        ledgerSealURL: sealURL
    )
    let outcome = try await sweep.run(throughDay: "2024-01-01")
    #expect(outcome.kind == .success)
    #expect(try store.transaction.loadCursor(metric: metric) == cursor)
    #expect(try store.transaction.loadEmittedIndex(uuid: gone.key.uuid) == nil)
    #expect(try store.transaction.loadEmittedIndex(uuid: keep.key.uuid) != nil)
    #expect(try store.transaction.loadCensus(metric: metric, day: "2024-01-01")?.sampleCount == 1)
    let texts = try FileManager.default.contentsOfDirectory(atPath: dest.path)
        .filter { $0.hasSuffix(".ndjson") }
        .map { try String(contentsOfFile: dest.appendingPathComponent($0).path, encoding: .utf8) }
        .joined()
    #expect(texts.contains(gone.key.uuid))
    #expect(texts.contains("\"kind\":\"tombstone\""))
    let snapshot = try DestinationSnapshotFile.read(from: snapshotURL)
    #expect(snapshot.lastOutcome == "success")
    let entries = try store.transaction.loadLedger()
    #expect(
        await LedgerHeadSealRecordFile.verify(entries: entries, seal: seal, url: sealURL)
            == .valid(head: entries.last?.entryHash ?? LedgerChain.genesisHash, count: entries.count)
    )
}

@Test func reconcileSweepReemitsNewSamplesAndLeavesCursor() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let keep = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    let extra = heartSample("cccccccc-cccc-cccc-cccc-cccccccccccc")
    let page = SamplePage(
        samples: [keep],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0xBB]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-sweep-more-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    let store = MemoryStateStore()
    _ = try await ExportRun(
        source: FixtureSource(pages: [page]),
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    ).run()
    let cursor = try store.transaction.loadCursor(metric: metric)
    let outcome = try await ReconcileSweep(
        observations: FixtureDays(byDay: ["2024-01-01": [keep, extra]]),
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch-sweep"),
        envelope: testEnvelope()
    ).run(throughDay: "2024-01-01")
    #expect(outcome.kind == .success)
    #expect(try store.transaction.loadCursor(metric: metric) == cursor)
    #expect(try store.transaction.loadEmittedIndex(uuid: extra.key.uuid) != nil)
    #expect(try store.transaction.loadCensus(metric: metric, day: "2024-01-01")?.sampleCount == 2)
}

@Test func reconcileSweepIsNothingDueWhenTheWindowMatches() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let keep = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    let page = SamplePage(
        samples: [keep],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0xCC]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-sweep-clean-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    let store = MemoryStateStore()
    _ = try await ExportRun(
        source: FixtureSource(pages: [page]),
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    ).run()
    let pendingBefore = try store.transaction.pendingBatches().count
    let outcome = try await ReconcileSweep(
        observations: FixtureDays(byDay: ["2024-01-01": [keep]]),
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch-sweep"),
        envelope: testEnvelope()
    ).run(throughDay: "2024-01-01")
    #expect(outcome.kind == .successNothingDue)
    #expect(try store.transaction.pendingBatches().count == pendingBefore)
}

@Test func aggregateOnlyBackfillDoesNotEmitOrIndexRawSamples() async throws {
    let metric = MetricCatalog.heartRate.id
    let sample = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-backfill-aggregate-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: destination) }
    try FileManager.default.createDirectory(
        at: destination,
        withIntermediateDirectories: true
    )
    let store = MemoryStateStore()
    let outcome = try await ReconcileSweep(
        observations: FixtureDays(byDay: ["2024-01-01": [sample]]),
        destination: .testing(LocalFileSink(directory: destination)),
        store: store,
        metric: metric,
        scratchDirectory: destination.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    ).runBackfill(days: ["2024-01-01"], mode: .aggregateOnly)

    #expect(outcome.kind == .success)
    #expect(
        try store.transaction.loadCensus(metric: metric, day: "2024-01-01")?
            .sampleCount == 1
    )
    #expect(try store.transaction.loadEmittedIndex(uuid: sample.key.uuid) == nil)
    let payload = try FileManager.default.contentsOfDirectory(
        at: destination,
        includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "ndjson" }
    .map { try String(contentsOf: $0, encoding: .utf8) }
    .joined()
    #expect(payload.contains("\"reason\":\"backfill\""))
    #expect(payload.contains("\"kind\":\"aggregate\""))
    #expect(!payload.contains("\"kind\":\"sample.quantity\""))
}

@Test func clearDirtyRemovesOnlyTheNamedDay() async throws {
    let store = MemoryStateStore()
    let metric = MetricID(rawValue: "heartRate")
    try await store.transact { tx in
        try tx.markDirty(metric: metric, day: "2024-01-01")
        try tx.markDirty(metric: metric, day: "2024-01-02")
        try tx.clearDirty(metric: metric, day: "2024-01-01")
    }
    #expect(try await store.transact { try $0.dirtyDays(metric: metric) } == ["2024-01-02"])
}

@Test func aggregateFoldMeansDiscreteSamplesForDay() {
    let metric = MetricID(rawValue: "heartRate")
    let samples = [
        heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", start: "2024-01-01T01:00:00Z"),
        heartSample("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", start: "2024-01-01T02:00:00Z"),
        heartSample("cccccccc-cccc-cccc-cccc-cccccccccccc", start: "2024-01-02T01:00:00Z"),
    ]
    // Override values for a known mean.
    var a = samples[0]; a.value = 60
    var b = samples[1]; b.value = 80
    let fold = AggregateFold.foldDay(metric: metric, day: "2024-01-01", samples: [a, b, samples[2]])
    #expect(fold.statistic == .mean)
    #expect(fold.sampleCount == 2)
    #expect(fold.value == 70)
}

@Test func aggregateFoldSumsCumulativeSamplesForDay() {
    let metric = MetricID(rawValue: "stepCount")
    let samples = [
        SampleRecord(
            key: RecordKey(uuid: "11111111-1111-1111-1111-111111111111"),
            metric: metric,
            start: "2024-01-01T08:00:00Z",
            end: "2024-01-01T08:00:00Z",
            timeZoneOffsetMinutes: 0,
            timeZoneSource: .unknown,
            value: 100,
            unit: CanonicalUnit(symbol: "count"),
            observedAt: "2024-01-01T08:00:00Z"
        ),
        SampleRecord(
            key: RecordKey(uuid: "22222222-2222-2222-2222-222222222222"),
            metric: metric,
            start: "2024-01-01T09:00:00Z",
            end: "2024-01-01T09:00:00Z",
            timeZoneOffsetMinutes: 0,
            timeZoneSource: .unknown,
            value: 50,
            unit: CanonicalUnit(symbol: "count"),
            observedAt: "2024-01-01T09:00:00Z"
        ),
    ]
    let fold = AggregateFold.foldDay(metric: metric, day: "2024-01-01", samples: samples)
    #expect(fold.statistic == .sum)
    #expect(fold.value == 150)
}

@Test func bucketKeyIsStableAcrossRecomputation() {
    let context = TemporalContext(
        timeZoneIdentifier: "UTC",
        localeIdentifier: "en_US_POSIX",
        tzDatabaseVersion: "2024a"
    )
    let metric = MetricID(rawValue: "heartRate")
    let samples = [heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")]
    let first = AggregateDrain.planDay(
        metric: metric,
        day: "2024-01-01",
        samples: samples,
        context: context,
        emitSeq: 1,
        computedAt: "2024-01-02T00:00:00Z",
        observedAt: "2024-01-02T00:00:00Z",
        now: Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01
    )
    let second = AggregateDrain.planDay(
        metric: metric,
        day: "2024-01-01",
        samples: samples,
        context: context,
        emitSeq: 2,
        computedAt: "2024-01-03T00:00:00Z",
        observedAt: "2024-01-03T00:00:00Z",
        now: Date(timeIntervalSince1970: 1_704_240_000),
        priorEmitSeq: 1
    )
    #expect(first?.record.bucketKey == second?.record.bucketKey)
    #expect(second?.record.state == .revised)
    #expect(second?.record.supersedes == 1)
}

@Test func nativeWireEncodesAggregateLineAndFooterCount() throws {
    let context = TemporalContext(
        timeZoneIdentifier: "UTC",
        localeIdentifier: "en_US_POSIX",
        tzDatabaseVersion: "2024a"
    )
    let metric = MetricID(rawValue: "heartRate")
    let plan = AggregateDrain.planDay(
        metric: metric,
        day: "2024-01-01",
        samples: [heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")],
        context: context,
        emitSeq: 1,
        computedAt: "2024-01-02T00:00:00Z",
        observedAt: "2024-01-02T00:00:00Z",
        now: Date(timeIntervalSince1970: 1_704_153_600)
    )!
    let data = try NativeWire.encode(
        samples: [],
        tombstones: [],
        aggregates: [plan.record],
        metric: metric,
        batchID: BatchID(rawValue: "agg-batch"),
        envelope: testEnvelope()
    )
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("\"kind\":\"aggregate\""))
    #expect(text.contains("\"bucketKey\":\"\(plan.record.bucketKey)\""))
    #expect(text.contains("\"aggregate\":1") || text.contains("\"aggregate\": 1"))
}

@Test func dirtyDayMarkedByCensusFeedsAggregateDrainPlan() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let store = MemoryStateStore()
    let page = SamplePage(
        samples: [heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([1]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    try await store.transact { tx in
        try Census.apply(page: page, to: tx)
        try EmittedIndex.record(page: page, batchID: BatchID(rawValue: "b1"), on: tx)
    }
    #expect(try await store.transact { try $0.dirtyDays(metric: metric) } == ["2024-01-01"])
    let context = TemporalContext(
        timeZoneIdentifier: "UTC",
        localeIdentifier: "en_US_POSIX",
        tzDatabaseVersion: "2024a"
    )
    let plan = AggregateDrain.planDay(
        metric: metric,
        day: "2024-01-01",
        samples: page.samples,
        context: context,
        emitSeq: 1,
        computedAt: "2024-01-02T00:00:00Z",
        observedAt: "2024-01-02T00:00:00Z",
        now: Date(timeIntervalSince1970: 1_704_153_600)
    )
    #expect(plan?.record.sampleCount == 1)
    #expect(plan?.record.computation == .localSampleFold)
    try await store.transact { try $0.clearDirty(metric: metric, day: "2024-01-01") }
    #expect(try await store.transact { try $0.dirtyDays(metric: metric) }.isEmpty)
}

@Test func exportRunRevisesAggregateOnSecondPageSameDay() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let firstPage = SamplePage(
        samples: [heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0x01]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    var later = heartSample("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
    later.value = 80
    let secondPage = SamplePage(
        samples: [later],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0x02]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-drain-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    let store = MemoryStateStore()
    let run = ExportRun(
        source: FixtureSource(pages: [firstPage, secondPage]),
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    )
    #expect(try await run.run().kind == .success)
    #expect(try store.transaction.dirtyDays(metric: metric).isEmpty)
    #expect(try await run.run().kind == .success)
    #expect(try store.transaction.loadCensus(metric: metric, day: "2024-01-01")?.sampleCount == 2)
    let files = try FileManager.default.contentsOfDirectory(
        at: dest,
        includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "ndjson" }
    let texts = try files.map { try String(contentsOf: $0, encoding: .utf8) }
    #expect(texts.contains { $0.contains("\"state\":\"revised\"") })
    #expect(texts.contains { $0.contains("\"supersedes\":1") })
}

@Test func exportRunUsesCanonicalStatisticsForCumulativeMetric() async throws {
    let metric = MetricCatalog.stepCount.id
    var sample = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    sample.metric = metric
    sample.unit = CanonicalUnit(symbol: "count")
    sample.value = 100
    let page = SamplePage(
        samples: [sample],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0x41]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-statistics-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    let store = MemoryStateStore()
    let run = ExportRun(
        source: FixtureSource(pages: [page]),
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch"),
        envelope: testEnvelope(),
        statistics: FixtureStatistics(
            byDay: ["2024-01-01": statisticsRecord(value: 123)]
        )
    )
    #expect(try await run.run().kind == .success)
    #expect(try store.transaction.dirtyDays(metric: metric).isEmpty)
    let texts = try FileManager.default.contentsOfDirectory(
        at: dest,
        includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "ndjson" }
    .map { try String(contentsOf: $0, encoding: .utf8) }
    #expect(texts.contains { $0.contains("\"healthKitStatisticsCollectionQuery\"") })
    #expect(texts.contains { $0.contains("\"value\":123") })
    #expect(!texts.contains { $0.contains("\"localSampleFold\"") })
}

@Test func exportRunDoesNotLocallyFoldCumulativeMetricWithoutStatisticsSource() async throws {
    let metric = MetricCatalog.stepCount.id
    var sample = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    sample.metric = metric
    sample.unit = CanonicalUnit(symbol: "count")
    let page = SamplePage(
        samples: [sample],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0x42]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-no-statistics-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    let store = MemoryStateStore()
    let run = ExportRun(
        source: FixtureSource(pages: [page]),
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    )
    #expect(try await run.run().kind == .success)
    #expect(try store.transaction.dirtyDays(metric: metric) == ["2024-01-01"])
    let texts = try FileManager.default.contentsOfDirectory(
        at: dest,
        includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "ndjson" }
    .map { try String(contentsOf: $0, encoding: .utf8) }
    #expect(!texts.contains { $0.contains("\"localSampleFold\"") })
}

@Test func statisticsAggregateRevisionGetsEngineSequenceAndSupersedes() throws {
    let canonical = statisticsRecord(value: 456)
    let plan = try #require(
        AggregateDrain.planStatisticsDay(
            metric: MetricCatalog.stepCount.id,
            day: "2024-01-01",
            canonical: canonical,
            context: .utc,
            emitSeq: 4,
            computedAt: "2024-01-03T00:00:00Z",
            observedAt: "2024-01-03T00:00:00Z",
            now: Date(timeIntervalSince1970: 1_704_240_000),
            priorEmitSeq: 3
        )
    )
    #expect(plan.record.emitSeq == 4)
    #expect(plan.record.supersedes == 3)
    #expect(plan.record.state == .revised)
    #expect(plan.record.computedAt == "2024-01-03T00:00:00Z")
}

@Test func wakeLedgerAppendsBeforeWorkAndRoundTrips() throws {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-wake-\(UUID().uuidString).log")
        .path
    let ledger = WakeLedger(path: path)
    try ledger.append(WakeRecord(trigger: .observerQuery, atEpoch: 100))
    try ledger.append(WakeRecord(trigger: .appForeground, atEpoch: 200))
    #expect(try ledger.records() == [
        WakeRecord(trigger: .observerQuery, atEpoch: 100),
        WakeRecord(trigger: .appForeground, atEpoch: 200),
    ])
}

@Test func observerCompletionReceiptFinishesExactlyOnceIncludingDeinit() {
    var completions = 0
    var receipt: ObserverCompletionReceipt? = ObserverCompletionReceipt {
        completions += 1
    }
    receipt?.finish()
    receipt?.finish()
    receipt = nil
    #expect(completions == 1)
}

@Test func ledgerChainDetectsInteriorMutationAndReordering() {
    let first = LedgerChain.seal(
        EgressEntry(destination: "one", sampleCount: 2, outcomeKind: "attempt"),
        sequence: 1,
        previousHash: LedgerChain.genesisHash
    )
    let second = LedgerChain.seal(
        EgressEntry(destination: "one", sampleCount: 2, outcomeKind: "success"),
        sequence: 2,
        previousHash: first.entryHash
    )
    #expect(
        LedgerChain.verify([first, second])
            == .valid(head: second.entryHash, count: 2)
    )
    var changed = first
    changed.sampleCount = 3
    #expect(LedgerChain.verify([changed, second]) == .invalid(sequence: 1))
    #expect(LedgerChain.verify([second, first]) == .invalid(sequence: 2))
}

@Test func sqliteLedgerPersistsAndVerifiesHashChain() async throws {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-ledger-\(UUID().uuidString).sqlite")
    let store = try SQLiteStateStore(path: path.path)
    try await store.transact { tx in
        try tx.appendLedger(
            EgressEntry(
                destination: "local-file",
                sampleCount: 2,
                outcomeKind: "attempt",
                byteCount: 100,
                wallTimeEpoch: 10
            )
        )
        try tx.appendLedger(
            EgressEntry(
                destination: "local-file",
                sampleCount: 2,
                outcomeKind: "success",
                byteCount: 100,
                wallTimeEpoch: 11
            )
        )
    }
    let entries = try await store.transact { try $0.loadLedger() }
    #expect(entries.map(\.sequence) == [1, 2])
    #expect(entries[1].previousHash == entries[0].entryHash)
    #expect(
        LedgerChain.verify(entries)
            == .valid(head: entries[1].entryHash, count: 2)
    )
}

/// R-22's acceptance criterion is two-part: distinct outcomes *and* distinct copy. The
/// classification is simulated below; this pins the half a user actually reads.
@Test func schedulingAndExecutionFailuresReadDifferently() {
    let scheduling = AttributionKind.scheduling.userFacingCopy
    let execution = AttributionKind.execution.userFacingCopy
    let quiet = AttributionKind.none.userFacingCopy
    #expect(Set([scheduling, execution, quiet]).count == 3)

    // RK-4: a wake the OS never delivered must not read as our export failing.
    #expect(scheduling.contains("iOS did not wake the app"))
    #expect(scheduling.contains("Nothing ran"))
    #expect(!scheduling.lowercased().contains("export did not finish"))
    #expect(execution.contains("woke on time"))
    #expect(execution.contains("ours"))

    for kind in AttributionKind.allCases {
        #expect(!kind.userFacingCopy.isEmpty)
    }
}

@Test func wakeAttributionSeparatesSchedulingFromExecution() {
    let expected: TimeInterval = 1_000
    #expect(
        WakeAttribution.classify(
            wakes: [],
            lastJournal: nil,
            nowEpoch: 2_000,
            expectedWakeByEpoch: expected
        ) == .scheduling
    )
    #expect(
        WakeAttribution.classify(
            wakes: [WakeRecord(trigger: .bgAppRefresh, atEpoch: 1_500)],
            lastJournal: nil,
            nowEpoch: 2_000,
            expectedWakeByEpoch: expected
        ) == .execution
    )
    #expect(
        WakeAttribution.classify(
            wakes: [WakeRecord(trigger: .bgAppRefresh, atEpoch: 1_500)],
            lastJournal: RunEvent(
                runID: RunID(rawValue: "r"),
                outcomeKind: "failed",
                detail: "anchor_undecodable"
            ),
            nowEpoch: 2_000,
            expectedWakeByEpoch: expected
        ) == .execution
    )
    #expect(
        WakeAttribution.classify(
            wakes: [WakeRecord(trigger: .bgAppRefresh, atEpoch: 1_500)],
            lastJournal: RunEvent(
                runID: RunID(rawValue: "r"),
                outcomeKind: "success",
                detail: ""
            ),
            nowEpoch: 2_000,
            expectedWakeByEpoch: expected
        ) == .none
    )
    #expect(
        WakeAttribution.classify(
            wakes: [],
            lastJournal: nil,
            nowEpoch: 500,
            expectedWakeByEpoch: expected
        ) == .none
    )
}

@Test func sqlitePersistsRichJournalAndWipeClearsState() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-wipe-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let payload = root.appendingPathComponent("batch.ndjson")
    try "payload\n".write(to: payload, atomically: true, encoding: .utf8)
    let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("cccccccc-cccc-cccc-cccc-cccccccccccc")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0xCC]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let event = RunEvent(
        runID: RunID(rawValue: "r1"),
        outcomeKind: "success",
        detail: "",
        trigger: .observerQuery,
        samplesRead: 3,
        samplesCommitted: 3,
        samplesAcked: 3
    )
    try await store.transact { tx in
        try tx.commitBatch(
            PendingBatch(
                id: BatchID(rawValue: "b"),
                payloadURL: payload.path,
                expectedRecords: 1
            ),
            advancing: CursorAdvance(page: page, epoch: 1)
        )
        try tx.appendJournal(event)
    }
    #expect(try await store.transact { try $0.loadJournal() } == [event])
    try await store.wipe(atEpoch: 1_234)
    #expect(try await store.transact { try $0.loadCursor(metric: metric) } == nil)
    #expect(try await store.transact { try $0.pendingBatches() }.isEmpty)
    #expect(try await store.transact { try $0.loadJournal() }.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: payload.path))
    let successor = try await store.transact { try $0.loadLedger() }
    #expect(LedgerChain.verify(successor) == .valid(head: successor[0].entryHash, count: 1))
    #expect(successor[0].outcomeKind == "genesis_after_wipe")
    #expect(successor[0].wallTimeEpoch == 1_234)
}

@Test func destructiveWipeDeletesSecretsAndSealsSuccessorGenesisWithNewIdentity() async throws {
    let state = MemoryStateStore()
    try await state.transact { tx in
        try tx.appendLedger(
            EgressEntry(
                destination: "local-file",
                sampleCount: 3,
                outcomeKind: "success",
                wallTimeEpoch: 1
            )
        )
    }
    let secrets = MemorySecretStore()
    let handle = SecretHandle(rawValue: "credential")
    try await secrets.store([1, 2, 3], handle: handle)
    let seal = ResettableTestLedgerSeal()
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-wipe-seal-\(UUID().uuidString).json")

    try await DestructiveWipe.perform(
        store: state,
        secretStores: [secrets],
        ledgerSeal: seal,
        ledgerSealURL: url,
        atEpoch: 1_234
    )

    await #expect(throws: SecretStoreError.notFound) {
        _ = try await secrets.load(handle)
    }
    let successor = try await state.transact { try $0.loadLedger() }
    #expect(successor.count == 1)
    #expect(successor[0].outcomeKind == "genesis_after_wipe")
    #expect(await seal.destroyedCount == 1)
    #expect(
        await LedgerHeadSealRecordFile.verify(entries: successor, seal: seal, url: url)
            == .valid(head: successor[0].entryHash, count: 1)
    )
}

@Test func appWipeEnumeratesEveryCredentialServiceAndManagedArtifact() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let harness = try String(
        contentsOf: root.appendingPathComponent("Apps/Exporter-iOS/HarnessExport.swift"),
        encoding: .utf8
    )
    for service in [
        "app.openhealthexporter.ios.psk",
        "app.openhealthexporter.ios.https",
        "app.openhealthexporter.mqtt",
    ] {
        #expect(harness.contains("KeychainSecretStore(service: \"\(service)\")"))
    }
    for artifact in [
        "exports",
        "scratch",
        "backfill-scratch",
        "demo-exports",
        "demo-scratch",
        "https-destination.json",
        "mqtt-destination.json",
        "mqtt-client.p12",
        "imported-destination-drafts.json",
        "otlp-destination.json",
        "wake-ledger.log",
        "health-authorization.json",
        "network-activity.json",
    ] {
        #expect(harness.contains("\"\(artifact)\""))
    }
    #expect(harness.contains("removePersistentDomain"))
    #expect(harness.contains("try removeIfPresent(directory)"))
}

@Test func r08TrailingReconcileRunsOnEveryHealthDestination() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let harness = try String(
        contentsOf: root.appendingPathComponent("Apps/Exporter-iOS/HarnessExport.swift"),
        encoding: .utf8
    )
    let calls = harness.components(separatedBy: "try await trailingReconcileAfterDelta(").count - 1
    let destinationIDs = ["local-file", "https", "mqtt", "companion"]
    #expect(calls == destinationIDs.count)
    for destinationID in destinationIDs {
        #expect(
            harness.contains("destinationID: \"\(destinationID)\""),
            "missing trailing reconcile destination \(destinationID)"
        )
    }
}

@Test func o9ScheduledFullReconcileIsGatedByCatchUpAdmission() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let harness = try String(
        contentsOf: root.appendingPathComponent("Apps/Exporter-iOS/HarnessExport.swift"),
        encoding: .utf8
    )
    #expect(harness.contains("maybeScheduledFullReconcile"))
    #expect(harness.contains("CatchUpAdmission.allows"))
    #expect(harness.contains("ScheduledReconcile.due"))
    #expect(harness.contains("trigger == .appForeground || trigger == .launch"))
    #expect(harness.contains("applyQueueRedIfNeeded"))
    #expect(harness.contains("deferForLowPower: isLowPowerDeferred()"))
    #expect(harness.contains("deferForThermal: isThermalDeferred()"))
    #expect(harness.contains("thermalHalved: isThermalDeferred()"))
    #expect(harness.contains("Gzip.$level.withValue(gzipLevel()"))
    #expect(harness.contains("thermalState"))
    #expect(harness.components(separatedBy: "try await applyQueueRedIfNeeded(").count - 1 == 4)
}

@Test func meteredNetworkOptInIsOffByDefaultOnEveryOutboundHealthPath() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let harness = try String(
        contentsOf: root.appendingPathComponent("Apps/Exporter-iOS/HarnessExport.swift"),
        encoding: .utf8
    )
    #expect(harness.contains("allowsMeteredNetwork(destinationID:"))
    #expect(harness.contains("NetworkPathMonitorCache.conditions()"))
    for destinationID in ["https", "mqtt", "companion", "otlp"] {
        #expect(
            harness.contains("allowsMeteredNetwork(destinationID: \"\(destinationID)\")"),
            "missing metered opt-in for \(destinationID)"
        )
    }
    for relative in [
        "Sources/SinkHTTP/HTTPSSink.swift",
        "Sources/SinkMQTT/MQTTSink.swift",
        "Sources/SinkCompanion/CompanionSink.swift",
        "Sources/OTLPExport/OTLPExporter.swift",
        "Sources/SinkHTTP/HTTPSDestinationEnable.swift",
        "Sources/SinkMQTT/MQTTDestinationEnable.swift",
        "Sources/SinkCompanion/CompanionDestinationEnable.swift",
    ] {
        let source = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
        #expect(
            source.contains("MeteredNetworkGate.require"),
            "missing metered gate in \(relative)"
        )
    }
}

@Test func privacyGateCannotEnterBackgroundExportOrDeliveryPaths() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let privacyGate = try String(
        contentsOf: root.appendingPathComponent("Apps/Exporter-iOS/AppPrivacyGate.swift"),
        encoding: .utf8
    )
    let exportHarness = try String(
        contentsOf: root.appendingPathComponent("Apps/Exporter-iOS/HarnessExport.swift"),
        encoding: .utf8
    )
    let lifecycle = try String(
        contentsOf: root.appendingPathComponent(
            "Apps/Exporter-iOS/AppLifecycleCoordinator.swift"
        ),
        encoding: .utf8
    )
    #expect(privacyGate.contains("Export and destination-delivery code deliberately have no dependency"))
    #expect(!exportHarness.contains("AppPrivacyGate"))
    #expect(!lifecycle.contains("AppPrivacyGate"))
}

@Test func exportRunJournalRecordsTriggerAndCounts() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0x11]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-journal-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    let store = MemoryStateStore()
    let run = ExportRun(
        source: FixtureSource(pages: [page]),
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch"),
        envelope: testEnvelope(),
        trigger: .observerQuery
    )
    _ = try await run.run()
    let event = try store.transaction.loadJournal().last
    #expect(event?.trigger == .observerQuery)
    #expect(event?.samplesRead == 2)
    #expect(event?.samplesAcked == 2)
    #expect(event?.outcomeKind == "success")
    #expect(event?.facts.metric == "heartRate")
    #expect(event?.facts.destinationID == "local-file")
    #expect(event?.facts.stepTimings.map(\.name) == ["read", "transform", "enqueue", "send"])
    #expect((event?.facts.byteCount ?? 0) > 0)
    #expect(event?.facts.windowStartDay != nil)
    #expect(event?.facts.redactedPayload?.contains("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa") == false)
    let revealed = RunHistoryDetail.revealedPayload(for: try #require(event))
    #expect(revealed.contains("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
    let detail = RunHistoryDetail.lines(for: try #require(event))
    #expect(detail.contains { $0.hasPrefix("outcome:") })
    #expect(detail.contains { $0.hasPrefix("trigger:") })
    #expect(detail.contains { $0.hasPrefix("window:") })
    #expect(detail.contains { $0.hasPrefix("bytes:") })
    #expect(detail.contains { $0.hasPrefix("duration:") })
    #expect(detail.contains { $0.hasPrefix("step send:") })
    #expect(detail.contains { $0.contains("payload:") })
}

@Test func typePurgeDueOnlyOnGrantToDeniedOrExplicitStop() {
    #expect(
        TypePurge.due(previous: .granted, observed: .denied, explicitStop: false)
    )
    #expect(
        TypePurge.due(previous: .granted, observed: .granted, explicitStop: true)
    )
    #expect(
        !TypePurge.due(previous: .unknown, observed: .denied, explicitStop: false)
    )
    #expect(
        !TypePurge.due(previous: .granted, observed: .granted, explicitStop: false)
    )
    #expect(
        !TypePurge.due(previous: .denied, observed: .denied, explicitStop: false)
    )
}

@Test func typePurgeDropsOnlyThatMetricAndUnlinksPayload() async throws {
    let heart = MetricID(rawValue: "heartRate")
    let steps = MetricID(rawValue: "stepCount")
    let heartPage = SamplePage(
        samples: [heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")],
        tombstones: [],
        metric: heart,
        anchorBlob: Data([0x11]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let stepPage = SamplePage(
        samples: [heartSample("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")],
        tombstones: [],
        metric: steps,
        anchorBlob: Data([0x22]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-purge-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let heartPayload = root.appendingPathComponent("heart.ndjson")
    let stepPayload = root.appendingPathComponent("steps.ndjson")
    try "heart\n".write(to: heartPayload, atomically: true, encoding: .utf8)
    try "steps\n".write(to: stepPayload, atomically: true, encoding: .utf8)
    let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
    try await store.transact { tx in
        try tx.commitBatch(
            PendingBatch(
                id: BatchID(rawValue: "h"),
                payloadURL: heartPayload.path,
                expectedRecords: 1,
                metric: heart
            ),
            advancing: CursorAdvance(page: heartPage, epoch: 1)
        )
        try tx.commitBatch(
            PendingBatch(
                id: BatchID(rawValue: "s"),
                payloadURL: stepPayload.path,
                expectedRecords: 1,
                metric: steps
            ),
            advancing: CursorAdvance(page: stepPage, epoch: 1)
        )
        try tx.upsertEmittedIndex(
            EmittedIndexRow(
                uuid: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
                metric: heart,
                day: "2024-01-01",
                digest: "heart",
                batchID: BatchID(rawValue: "h")
            )
        )
        try tx.upsertEmittedIndex(
            EmittedIndexRow(
                uuid: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
                metric: steps,
                day: "2024-01-01",
                digest: "steps",
                batchID: BatchID(rawValue: "s")
            )
        )
    }
    let purgeStarted = ContinuousClock.now
    try await store.purgeType(
        metric: heart,
        reason: "revocation_observed",
        destination: "local-file",
        atEpoch: 1_234
    )
    #expect(
        ContinuousClock.now - purgeStarted
            < .seconds(Int64(TypePurge.observationSLA))
    )
    let remaining = try await store.transact { try $0.pendingBatches() }
    #expect(remaining.map(\.id.rawValue) == ["s"])
    #expect(!FileManager.default.fileExists(atPath: heartPayload.path))
    #expect(FileManager.default.fileExists(atPath: stepPayload.path))
    let status = try await store.transact { try $0.loadTypeStatus(metric: heart) }
    #expect(status?.disabled == true)
    #expect(status?.reason == "revocation_observed")
    #expect(status?.generation == 2)
    #expect(try await store.transact { try $0.loadCursor(metric: heart) } == nil)
    #expect(try await store.transact { try $0.loadCursor(metric: steps) } != nil)
    #expect(
        try await store.transact {
            try $0.loadEmittedIndex(uuid: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        } == nil
    )
    #expect(
        try await store.transact {
            try $0.loadEmittedIndex(uuid: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
        } != nil
    )
    let journal = try await store.transact { try $0.loadJournal() }
    #expect(journal.last?.outcomeKind == "purged")
    let gaps = try await store.transact { try $0.loadGaps() }
    #expect(gaps.contains { $0.rangeDescription.hasPrefix("purged_by_revocation:") })
    try await store.reenableType(metric: heart, reason: "user_requested")
    let reenabled = try await store.transact { try $0.loadTypeStatus(metric: heart) }
    #expect(reenabled?.disabled == false)
    #expect(reenabled?.generation == 2)
}

@Test func typePurgeAtProductionCapFinishesInsideObservationSLAAndBlocksLaterSends() async throws {
    let heart = MetricCatalog.heartRate.id
    let steps = MetricCatalog.stepCount.id
    let store = MemoryStateStore()
    let chunk = 1024 * 1024
    let cap = QueuePolicy.production.cap
    try await store.transact { tx in
        var remaining = cap
        var index = 0
        while remaining > 0 {
            let bytes = min(chunk, remaining)
            try tx.enqueuePending(
                PendingBatch(
                    id: BatchID(rawValue: "heart-\(index)"),
                    payloadURL: "/tmp/ohe-r44-\(index)",
                    expectedRecords: 1,
                    byteCount: bytes,
                    metric: heart,
                    rangeStartDay: "2026-01-01",
                    rangeEndDay: "2026-01-01"
                )
            )
            remaining -= bytes
            index += 1
        }
        try tx.enqueuePending(
            PendingBatch(
                id: BatchID(rawValue: "steps-live"),
                payloadURL: "/tmp/ohe-r44-steps",
                expectedRecords: 1,
                byteCount: 8,
                metric: steps
            )
        )
    }
    #expect(try await store.transact { try $0.queuedBytes() } == cap + 8)
    let started = ContinuousClock.now
    try await store.purgeType(
        metric: heart,
        reason: TypeDisableReason.authorizationRevoked,
        destination: "local-file",
        atEpoch: 1
    )
    #expect(ContinuousClock.now - started < .seconds(Int64(TypePurge.observationSLA)))
    #expect(
        try await store.transact { try $0.pendingBatches().map(\.id.rawValue) } == ["steps-live"]
    )
    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-r44-cap-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dest) }
    let source = ReadCountingSource(
        page: SamplePage(
            samples: [heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")],
            tombstones: [],
            metric: heart,
            anchorBlob: Data([0x44]),
            observedThrough: Date(timeIntervalSince1970: 0)
        )
    )
    let outcome = try await ExportRun(
        source: source,
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: heart,
        scratchDirectory: dest.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    ).run()
    #expect(outcome.kind == .failed)
    #expect(outcome.partialCause == "types_purged")
    #expect(source.reads == 0)
    let sent = try FileManager.default.contentsOfDirectory(
        at: dest,
        includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "ndjson" }
    #expect(sent.isEmpty)
}

private actor ResettableTestLedgerSeal: ResettableLedgerHeadSeal {
    private var generation = 0
    private(set) var destroyedCount = 0

    func signedHead(_ head: String) async throws -> String {
        try await HashLedgerSeal(secret: "generation-\(generation)").signedHead(head)
    }

    func matches(head: String, signature: String) async -> Bool {
        await HashLedgerSeal(secret: "generation-\(generation)")
            .matches(head: head, signature: signature)
    }

    func destroyIdentity() async throws {
        generation += 1
        destroyedCount += 1
    }
}

final class CountingSource: SampleSource, @unchecked Sendable {
    var pages: Int = 0
    func page(metric: MetricID, afterAnchor: Data?) async throws -> SamplePage {
        pages += 1
        return SamplePage(
            samples: [heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")],
            tombstones: [],
            metric: metric,
            anchorBlob: Data([0x11]),
            observedThrough: Date(timeIntervalSince1970: 0)
        )
    }
}

@Test func exportRunSkipsDisabledTypeWithoutReading() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-disabled-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    let store = MemoryStateStore()
    try await store.transact {
        try $0.upsertTypeStatus(
            TypeStatus(metric: metric, disabled: true, reason: "explicit_stop")
        )
    }
    let source = CountingSource()
    let run = ExportRun(
        source: source,
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    )
    let outcome = try await run.run()
    #expect(outcome.kind == .failed)
    #expect(outcome.partialCause == "types_purged")
    #expect(source.pages == 0)
    #expect(try store.transaction.loadLedger().last?.outcomeKind == "run:failed")
}

@Test func reenabledTypeCommitsWithItsBumpedGeneration() async throws {
    let metric = MetricCatalog.heartRate.id
    let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-generation-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    let store = MemoryStateStore()
    try await store.transact {
        try $0.upsertTypeStatus(
            TypeStatus(
                metric: metric,
                disabled: false,
                reason: "user_requested",
                generation: 4
            )
        )
    }
    let run = ExportRun(
        source: CountingSource(),
        destination: .testing(LocalFileSink(directory: dest)),
        store: store,
        metric: metric,
        scratchDirectory: dest.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    )
    _ = try await run.run()
    #expect(try store.transaction.loadCursor(metric: metric)?.epoch == 4)
}

private struct ThrowingSink: DestinationSink {
    var error: DestinationSendError

    func send(fileHandle: String, idempotencyKey: BatchID) async throws -> DeliveryReceipt {
        throw error
    }
}

private struct SilentDiscardSink: DestinationSink {
    func send(fileHandle: String, idempotencyKey: BatchID) async throws -> DeliveryReceipt {
        DeliveryReceipt(batchID: idempotencyKey, accepted: 0, statusOnly: true)
    }
}
