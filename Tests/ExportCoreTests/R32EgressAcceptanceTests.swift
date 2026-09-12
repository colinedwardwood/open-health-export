// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CorrectnessEngine
import DestinationTrust
import EnginePorts
import Foundation
import MetricCatalog
import NetEgress
import SinkHTTP
import TestSupport
import Testing
import WireFormat

/// R-32 measures application-initiated connection attempts at the `NetEgress`
/// chokepoint. A packet-capture version of this test excludes only these named
/// OS-initiated categories; they are not silently folded into a general exception:
/// DNS resolution, OCSP, CRL, and Certificate Transparency (CT) traffic.
private let r32ExcludedOSInitiatedTraffic = [
    "DNS",
    "OCSP",
    "CRL",
    "Certificate Transparency (CT)",
]

/// R-32 acceptance harness. The control completes a real `ExportRun` through
/// `HTTPSSink` and `URLSession` to a reachable loopback receiver. The subject then
/// removes that same host from the current allowlist and enters through the same
/// app-style cycle assembly function. Production rejects the saved URL while
/// rebuilding `HTTPSDestination`, before source reads, DNS, or transport execution.
@Test func p16R32RemovedHTTPSHostReceivesZeroAppInitiatedEgressAcrossExportCycle() async throws {
    let receiver = ScriptableHTTPServer()
    try receiver.start()
    defer { receiver.stop() }
    receiver.setFallback(.init(status: 204))

    let host = try #require(receiver.origin.host)
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-r32-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let controlRecorder = EgressAttemptLog.Recorder()
    let control = try await EgressAttemptLog.$recorder.withValue(controlRecorder) {
        try await runR32HTTPSExportCycle(
            urlString: receiver.origin.appendingPathComponent("health").absoluteString,
            currentAllowedHosts: [host],
            scratchDirectory: directory.appendingPathComponent("control")
        )
    }
    #expect(control.kind == .success)
    let controlAttempts = controlRecorder.snapshot()
    #expect(controlAttempts.count == 1)
    #expect(controlAttempts[0].kind == .http)
    #expect(controlAttempts[0].host == host)
    #expect(controlAttempts[0].bytes > 0)
    #expect(receiver.requests().count == 1, "control did not reach the loopback receiver")

    let removedHostRecorder = EgressAttemptLog.Recorder()
    await #expect(throws: EgressError.notAllowlisted(host)) {
        try await EgressAttemptLog.$recorder.withValue(removedHostRecorder) {
            try await runR32HTTPSExportCycle(
                urlString: receiver.origin.appendingPathComponent("health").absoluteString,
                currentAllowedHosts: [],
                scratchDirectory: directory.appendingPathComponent("removed")
            )
        }
    }

    #expect(
        removedHostRecorder.snapshot().isEmpty,
        "removed host caused app-initiated egress: \(removedHostRecorder.snapshot())"
    )
    #expect(receiver.requests().count == 1, "removed host received a second request")
    #expect(
        r32ExcludedOSInitiatedTraffic
            == ["DNS", "OCSP", "CRL", "Certificate Transparency (CT)"]
    )
}

/// Mirrors the relevant ordering in `HarnessExport.runHTTPSDestination`: load the
/// saved URL, authorize it against the *current* allowlist, construct the transport,
/// and only then start `ExportRun`.
private func runR32HTTPSExportCycle(
    urlString: String,
    currentAllowedHosts: Set<String>,
    scratchDirectory: URL
) async throws -> RunOutcome {
    let destination = try HTTPSDestination(
        urlString: urlString,
        allowedHosts: currentAllowedHosts,
        allowInsecureHTTP: true
    )
    let transport = try SystemHTTPTransport.make(
        probing: destination.url,
        allowedHosts: currentAllowedHosts,
        allowInsecureHTTP: true
    )
    let source = R32OnePageSource()
    return try await ExportRun(
        source: source,
        destination: .testing(
            HTTPSSink(destination: destination, transport: transport)
        ),
        store: MemoryStateStore(),
        metric: MetricCatalog.heartRate.id,
        scratchDirectory: scratchDirectory,
        destinationName: "r32-https",
        envelope: WireEnvelope(
            exporterId: "00000000-0000-0000-0000-000000000032",
            seq: 1,
            emittedAt: "2026-09-11T00:00:00Z",
            observedAt: "2026-09-11T00:00:00Z"
        )
    ).run()
}

private struct R32OnePageSource: SampleSource {
    func page(metric: MetricID, afterAnchor: Data?) async throws -> SamplePage {
        SamplePage(
            samples: [
                SampleRecord(
                    key: RecordKey(uuid: "00000000-0000-0000-0000-000000000032"),
                    metric: metric,
                    start: "2026-09-11T00:00:00Z",
                    end: "2026-09-11T00:00:00Z",
                    timeZoneOffsetMinutes: 0,
                    timeZoneSource: .unknown,
                    value: 60,
                    unit: CanonicalUnit(symbol: "count/min"),
                    observedAt: "2026-09-11T00:00:00Z"
                ),
            ],
            tombstones: [],
            metric: metric,
            anchorBlob: Data([0x32]),
            observedThrough: Date(timeIntervalSince1970: 1_789_084_800)
        )
    }
}
