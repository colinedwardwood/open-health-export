// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import EnginePorts
import Foundation
import Testing

private func event(
    _ id: String,
    _ kind: RunOutcome.Kind,
    at epoch: TimeInterval,
    destination: String = "local-file",
    trigger: RunTrigger = .manual,
    records: Int = 0,
    errorClass: String? = nil
) -> RunEvent {
    var facts = RunHistoryFacts.empty
    facts.destinationID = destination
    facts.metric = "heartRate"
    return RunEvent(
        runID: RunID(rawValue: id),
        outcomeKind: kind.rawValue,
        detail: "",
        trigger: trigger,
        samplesCommitted: records,
        wallTimeEpoch: epoch,
        errorClass: errorClass,
        facts: facts
    )
}

@Test func problemsFilterShowsOnlyRunsThatDidNotDeliver() {
    let events = [
        event("a", .success, at: 10, records: 1_204),
        event("b", .failed, at: 20, destination: "mqtt", errorClass: ErrorClass.destinationUnreachable.rawValue),
        event("c", .successNothingDue, at: 30),
    ]
    let problems = HistoryPresentation.rows(events, filter: .problems)
    #expect(problems.map(\.event.runID.rawValue) == ["b"])
    #expect(HistoryPresentation.rows(events, filter: .all).map(\.event.runID.rawValue) == ["c", "b", "a"])
    #expect(HistoryPresentation.rows(events, filter: .all, destinationID: "mqtt").count == 1)
}

@Test func rowsSayWhatHappenedInWords() {
    let row = HistoryPresentation.row(event("a", .success, at: 10, trigger: .bgAppRefresh, records: 1_204))
    #expect(row.result == "Delivered 1,204 records.")
    #expect(row.trigger == "Background")
    #expect(row.destination == "Archive folder")
    #expect(row.typeName == "Heart rate")
    let failed = HistoryPresentation.row(event("b", .failed, at: 10, errorClass: "somethingNew"))
    #expect(failed.result == "Not delivered.")
    for trigger in RunTrigger.allCases {
        let words = HistoryPresentation.trigger(trigger)
        #expect(words != trigger.rawValue, "\(trigger)")
        #expect(words.range(of: "[a-z][A-Z]", options: .regularExpression) == nil, "\(trigger): \(words)")
    }
}

@Test func anEmptyProblemsListSaysHowManyRunsDelivered() {
    let events = [event("a", .success, at: 1), event("b", .success, at: 2)]
    #expect(HistoryPresentation.emptyCopy(events, filter: .problems) == "No problems in the last 90 days. 2 runs delivered.")
    #expect(HistoryPresentation.emptyCopy([], filter: .problems) == RunHistoryDetail.emptyStateCopy)
}
