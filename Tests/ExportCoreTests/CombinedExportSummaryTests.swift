// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Testing
import Watchdog

@Test func combinedExportIsPartialWhenAnySelectedTypeReturnedNothing() {
    let mixed: [RunOutcome.Kind] = Array(repeating: .success, count: 29)
        + Array(repeating: .successNothingDue, count: 12)
    #expect(CombinedExportSummary.kind(mixed) == .partial)
    #expect(CombinedExportSummary.typesWithData(mixed) == 29)
    #expect(
        CombinedExportSummary.copy(mixed)
            == "Partial · 29 of 41 types returned data. Review coverage."
    )
    #expect(
        CombinedExportSummary.kind(Array(repeating: .success, count: 41)) == .success
    )
    #expect(
        CombinedExportSummary.copy(Array(repeating: .successNothingDue, count: 41))
            == "Nothing new to export."
    )
    #expect(!CombinedExportSummary.copy(mixed).lowercased().contains("success: 0"))
    #expect(CombinedExportSummary.progress(current: 24, total: 41) == "Reading 24 of 41 types")
}

@Test func combinedExportCopyParksMeteredAndLowPowerAsDeferred() {
    #expect(CombinedExportSummary.copy([.blockedUnmetered]) == "Export deferred.")
    #expect(CombinedExportSummary.kind([.success, .blockedUnmetered]) == .blockedUnmetered)
}

@Test func combinedPartialOverwritesLastPerTypeOutcomeOnSnapshot() {
    var snapshot = DestinationStatusSnapshot(
        destinationID: "local-file",
        enabled: true,
        lastOutcome: "successNothingDue",
        writtenAtEpoch: 1
    )
    snapshot.applyLastOutcome(
        CombinedExportSummary.kind([.success, .successNothingDue]).rawValue
    )
    #expect(snapshot.lastOutcome == "partial")
    #expect(snapshot.state == .partial)
}
