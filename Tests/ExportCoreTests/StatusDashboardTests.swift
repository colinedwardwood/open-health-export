// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppServices
import CoreDomain
import DestinationTrust
import EnginePorts
import Foundation
import NetEgress
import Testing
import Watchdog

private let now: TimeInterval = 1_790_000_000
private func ago(_ epoch: TimeInterval) -> String { "\(Int((now - epoch) / 60)) min ago" }

private func snapshot(
    _ id: String,
    label: String,
    state: DestinationDisplayState,
    lastSuccess: TimeInterval? = now - 720,
    errorClass: String? = nil,
    changes: Int = 0
) -> DestinationStatusSnapshot {
    DestinationStatusSnapshot(
        destinationID: id,
        destinationLabel: label,
        enabled: true,
        state: state,
        lastSuccessEpoch: lastSuccess,
        errorClass: errorClass,
        unacknowledgedSecurityEventCount: changes,
        writtenAtEpoch: now
    )
}

/// UX-19: nothing on Status is an enum name, an error class or camelCase.
private func looksRaw(_ text: String) -> Bool {
    // Apple's own product names are the only camel case allowed.
    let words = ["iOS", "iPhone", "iPad"].reduce(text) { $0.replacingOccurrences(of: $1, with: "") }
    return words.range(of: "[a-z][A-Z]", options: .regularExpression) != nil || words.contains("_")
}

@Test func everyStateAndErrorClassReadsAsWords() {
    for state in DestinationDisplayState.allCases {
        for errorClass in ErrorClass.allCases.map(\.rawValue) + [nil, "somethingNew"] {
            let rows = StatusDashboard.rows(
                [snapshot("d", label: "Archive folder", state: state, errorClass: errorClass)],
                nowEpoch: now,
                relative: ago
            )
            for row in rows {
                #expect(!looksRaw(row.detail), "\(state) \(errorClass ?? "nil"): \(row.detail)")
                #expect(!looksRaw(row.stateLabel), "\(state): \(row.stateLabel)")
                #expect(!row.detail.contains(state.rawValue), "\(state): \(row.detail)")
            }
        }
    }
}

@Test func appAndWidgetUseTheSameLabelAndGlyph() {
    for state in DestinationDisplayState.allCases {
        let row = StatusDashboard.rows([snapshot("d", label: "X", state: state)], nowEpoch: now, relative: ago)[0]
        #expect(row.stateLabel == state.label)
        #expect(row.glyph == state.glyph)
    }
}

@Test func summaryNamesTheWorstDestinationAndOffersToCheckIt() {
    let rows = StatusDashboard.rows(
        [
            snapshot("files", label: "Files", state: .healthy),
            snapshot("ha", label: "Home Assistant", state: .healthy),
            snapshot("mqtt", label: "Mosquitto", state: .overdue, lastSuccess: now - 25_200),
        ],
        nowEpoch: now,
        relative: ago
    )
    let summary = StatusDashboard.summary(rows, lastSuccessEpoch: now - 720, relative: ago)
    #expect(summary.headline == "2 of 3 destinations are up to date.")
    #expect(summary.detail == "Mosquitto: Last delivered 420 min ago.")
    #expect(summary.action == .check(destinationID: "mqtt", label: "Mosquitto"))
    #expect(summary.tone == .attention)
}

@Test func allHealthySaysSoWithTheLastExport() {
    let rows = StatusDashboard.rows(
        [snapshot("files", label: "Files", state: .healthy)],
        nowEpoch: now,
        relative: ago
    )
    let summary = StatusDashboard.summary(rows, lastSuccessEpoch: now - 720, relative: ago)
    #expect(summary.headline == "Everything is up to date.")
    #expect(summary.detail == "Last export 12 min ago. Sending to 1 destination.")
    #expect(summary.action == nil)
}

@Test func noDestinationsOffersSetup() {
    let summary = StatusDashboard.summary([], lastSuccessEpoch: nil, relative: ago)
    #expect(summary.action == .setUp)
}

@Test func aChangedDestinationNeedsAttentionEvenWhenHealthy() {
    let row = StatusDashboard.rows(
        [snapshot("https", label: "Server", state: .healthy, changes: 1)],
        nowEpoch: now,
        relative: ago
    )[0]
    #expect(row.needsAttention)
    #expect(row.tone == .attention)
}

private struct FakeStorageError: StorageFailure {}
private struct SomethingElse: Error {}

@Test func everyCaughtErrorBecomesAFivePartObject() {
    #expect(UserFacingFailure.object(for: FakeStorageError(), destinationLabel: "Files").archetype == .storageProblem)
    #expect(UserFacingFailure.object(for: SomethingElse(), destinationLabel: "Files").archetype == .unexpected)
    #expect(UserFacingFailure.object(for: EgressError.httpStatus(401), destinationLabel: "HA").archetype == .http401)
    #expect(UserFacingFailure.object(for: EgressError.transport("x"), destinationLabel: "HA").archetype == .timeout)
    #expect(
        UserFacingFailure.object(for: DestinationSendError.destinationUnreachable, destinationLabel: "HA").archetype
            == .hostUnresolvable
    )
    #expect(UserFacingFailure.object(for: SetupError.testFailed(at: .resolveHost), destinationLabel: "HA").archetype == .hostUnresolvable)
    #expect(UserFacingFailure.object(for: SetupError.testFailed(at: .authenticate), destinationLabel: "HA").archetype == .http401)
    #expect(UserFacingFailure.object(for: SetupError.testFailed(at: .tlsHandshake), destinationLabel: "HA").archetype == .tlsTrustFailure)
    for archetype in [UserFacingErrorArchetype.storageProblem, .unexpected] {
        let object = UserFacingErrorObject.make(archetype: archetype, destinationLabel: "Files")
        #expect(!object.title.isEmpty && !object.cause.isEmpty && !object.fix.isEmpty)
        #expect(!object.actions.isEmpty)
    }
}
