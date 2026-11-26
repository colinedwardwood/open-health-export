// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import DiagnosticBundle
import EnginePorts
import Foundation
import NetEgress
import Redaction
import Testing

private let secret = "SEEDED-SECRET-hunter2-Bearer-abc123"

private func payload(events: [RunEvent]) throws -> Data {
    try BundleAssembler().assemble(
        header: DiagnosticHeader(
            appVersion: "1.2.3",
            osVersion: "26.0",
            deviceModel: "iPhone",
            localeIdentifier: "en_US",
            utcOffsetMinutes: 0,
            generatedAt: "2026-01-01T00:00:00Z",
            sourceCommit: "abc1234",
            buildHash: "hash"
        ),
        events: events
    )
}

@Test func diagnosticsReportListsBuildExportsLaunchFailuresAndNetwork() throws {
    let report = DiagnosticsReport.make(
        bundlePayload: try payload(events: [
            RunEvent(
                runID: RunID(rawValue: "r1"), outcomeKind: "success", detail: "", trigger: .manual,
                samplesRead: 3, samplesCommitted: 3, samplesAcked: 3
            ),
        ]),
        launchIssues: [LaunchIssue(stage: .observerStart, errorClass: "internalFault", atEpoch: 5_000)],
        network: [NetworkActivityRow(
            host: "a.example", kinds: ["http"], count: 2, bytes: 40, firstSeenEpoch: 1, lastSeenEpoch: 2
        )]
    )
    #expect(report.buildLines.contains("App version: 1.2.3"))
    #expect(report.buildLines.contains("Source commit: abc1234"))
    #expect(report.exportLines.first?.contains("outcome=success") == true)
    #expect(report.launchLines.first?.hasPrefix("observer_start errorClass=internalFault") == true)
    #expect(report.networkLines == ["destination 1: http · 2 attempts · 40 bytes"])
}

@Test func diagnosticsReportSaysNoneWhenNothingIsRecorded() throws {
    let report = DiagnosticsReport.make(bundlePayload: try payload(events: []), launchIssues: [], network: [])
    #expect(report.exportLines == [DiagnosticsReport.noneLine])
    #expect(report.launchLines == [DiagnosticsReport.noneLine])
    #expect(report.networkLines == [DiagnosticsReport.noneLine])
}

@Test func aSeededSecretNeverReachesTheSharedText() throws {
    // The secret is planted everywhere free text can reach: journal detail and run ID,
    // a launch issue's error class, and the host of a network row.
    let report = DiagnosticsReport.make(
        bundlePayload: try payload(events: [
            RunEvent(
                runID: RunID(rawValue: secret), outcomeKind: "failed", detail: secret, trigger: .manual,
                samplesRead: 1, errorClass: "internalFault"
            ),
        ]),
        launchIssues: [LaunchIssue(stage: .wakeLedger, errorClass: secret, atEpoch: 1)],
        network: [NetworkActivityRow(
            host: "\(secret).example.com:8443", kinds: ["byteStream"], count: 1, bytes: 1,
            firstSeenEpoch: 1, lastSeenEpoch: 1
        )]
    )
    for token in [secret, "hunter2", "example.com", "8443"] + RedactionCanary.tokens {
        #expect(!report.text.contains(token))
    }
    #expect(report.launchLines.first?.contains("errorClass=unknown") == true)
}
