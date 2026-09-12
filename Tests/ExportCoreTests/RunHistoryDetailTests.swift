// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import EnginePorts
import Foundation
import StorageSQLite
import Testing

@Test func runHistoryDetailListsRequiredFieldsAndHidesExactPayload() throws {
    let payload = "{\"uuid\":\"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa\"}\n"
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-history-payload-\(UUID().uuidString).ndjson")
    try Data(payload.utf8).write(to: url)
    let event = RunEvent(
        runID: RunID(rawValue: "run-heartRate"),
        outcomeKind: "failed",
        detail: "destinationUnreachable",
        trigger: .shortcut,
        samplesRead: 4,
        samplesCommitted: 4,
        samplesAcked: 0,
        wallTimeEpoch: 100,
        errorClass: "destinationUnreachable",
        facts: RunHistoryFacts(
            destinationID: "home-assistant",
            metric: "heartRate",
            windowStartDay: "2026-01-01",
            windowEndDay: "2026-01-02",
            byteCount: payload.utf8.count,
            durationMillis: 40,
            stepTimings: [
                RunStepTiming(name: "read", durationMillis: 10),
                RunStepTiming(name: "send", durationMillis: 20),
            ],
            payloadSHA256: "abc",
            redactedPayload: RunHistoryDetail.redactedPayload(
                metric: "heartRate",
                records: 4,
                byteCount: payload.utf8.count,
                windowStartDay: "2026-01-01",
                windowEndDay: "2026-01-02"
            ),
            payloadPath: url.path
        )
    )
    let hidden = RunHistoryDetail.lines(for: event)
    #expect(hidden.contains("outcome: failed"))
    #expect(hidden.contains("trigger: shortcut"))
    #expect(hidden.contains("destination: home-assistant"))
    #expect(hidden.contains("window: 2026-01-01 → 2026-01-02"))
    #expect(hidden.contains("type heartRate: 4 records"))
    #expect(hidden.contains("bytes: \(payload.utf8.count)"))
    #expect(hidden.contains("duration: 40 ms"))
    #expect(hidden.contains("step read: 10 ms"))
    #expect(hidden.contains("error: destinationUnreachable"))
    #expect(hidden.contains(where: { $0.contains("\"records\":4") }))
    #expect(!hidden.contains(where: { $0.contains("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa") }))
    #expect(hidden.contains(RunHistoryDetail.payloadHiddenCopy))

    let revealed = RunHistoryDetail.lines(for: event, revealPayload: true)
    #expect(revealed.contains(where: { $0.contains("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa") }))
    #expect(RunHistory.problemsFirst([
        RunEvent(runID: RunID(rawValue: "ok"), outcomeKind: "success", detail: ""),
        event,
    ]).first?.runID == event.runID)
    #expect(RunHistoryDetail.emptyStateCopy.contains("No exports yet"))
}

@Test func runHistoryFactsRoundTripThroughJSON() {
    let facts = RunHistoryFacts(
        destinationID: "nas",
        metric: "stepCount",
        windowStartDay: "2026-02-01",
        windowEndDay: "2026-02-01",
        byteCount: 12,
        durationMillis: 9,
        stepTimings: [RunStepTiming(name: "read", durationMillis: 9)],
        payloadSHA256: "deadbeef",
        redactedPayload: "{}",
        payloadPath: "/tmp/x"
    )
    let decoded = RunHistoryFacts.decode(facts.jsonString())
    #expect(decoded == facts)
    #expect(RunHistoryFacts.decode(nil) == .empty)
}

@Test func cancelledBySystemHistoryLineIsInterrupted() {
    let event = RunEvent(
        runID: RunID(rawValue: "run-heartRate"),
        outcomeKind: "cancelledBySystem",
        detail: "os_termination",
        trigger: .manual,
        samplesRead: 4,
        samplesCommitted: 1,
        samplesAcked: 0,
        wallTimeEpoch: 100,
        errorClass: "cancelledBySystem"
    )
    #expect(RunHistoryDetail.listLine(event).hasPrefix("Interrupted"))
    #expect(RunHistoryDetail.listLine(event).contains("0/1 acknowledged"))
}

@Test func sqliteJournalPersistsHistoryFacts() async throws {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-history-\(UUID().uuidString).sqlite")
        .path
    let store = try SQLiteStateStore(path: path)
    let event = RunEvent(
        runID: RunID(rawValue: "run-stepCount"),
        outcomeKind: "partial",
        detail: "",
        trigger: .manual,
        samplesRead: 1,
        samplesCommitted: 1,
        samplesAcked: 1,
        wallTimeEpoch: 50,
        facts: RunHistoryFacts(
            destinationID: "archive",
            metric: "stepCount",
            windowStartDay: "2026-03-01",
            windowEndDay: "2026-03-01",
            byteCount: 8,
            durationMillis: 5,
            stepTimings: [RunStepTiming(name: "read", durationMillis: 5)],
            payloadSHA256: "00",
            redactedPayload: "{\"metric\":\"stepCount\",\"records\":1,\"bytes\":8,\"window\":\"2026-03-01/2026-03-01\"}"
        )
    )
    try await store.transact { try $0.appendJournal(event) }
    let loaded = try await store.transact { try $0.loadJournal() }
    #expect(loaded.last?.facts.metric == "stepCount")
    #expect(loaded.last?.facts.windowStartDay == "2026-03-01")
    #expect(loaded.last?.facts.stepTimings.first?.name == "read")
    #expect(loaded.last?.outcomeKind == "partial")
}
