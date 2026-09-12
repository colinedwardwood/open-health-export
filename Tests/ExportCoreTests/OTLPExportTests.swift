// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import EnginePorts
import Foundation
import NetEgress
import OTLPExport
import Redaction
import StorageSQLite
import TestSupport
import Testing

/// OBS-22 / R-52. The export cycle's half of this is
/// `p16DefaultLocalFileExportMakesNoAttributableNetworkDials`; this is the telemetry
/// subsystem's half, which is the one the requirement actually names. A real loopback
/// listener is reachable for the whole test, so nothing about the environment is what
/// prevents a connection — only the default configuration is.
@Test func defaultTelemetryConfigurationOpensNoConnection() async throws {
    let interceptor = ScriptableHTTPServer()
    try interceptor.start()
    defer { interceptor.stop() }
    interceptor.setFallback(ScriptableHTTPServer.Script(status: 200))

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-obs22-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let event = RunEvent(
        runID: RunID(rawValue: "run-obs22"),
        outcomeKind: "success",
        detail: "",
        trigger: .bgProcessing,
        wallTimeEpoch: 1_700_000_000
    )

    let recorder = EgressAttemptLog.Recorder()
    let exported = try await EgressAttemptLog.$recorder.withValue(recorder) {
        try await OTLPExporter(
            settings: .disabled,
            transport: URLSessionHTTPTransport()
        ).export(events: [event], bodyDirectory: directory)
    }

    #expect(exported == false)
    #expect(OTLPExportSettings.disabled.endpoint == nil)
    #expect(recorder.snapshot().isEmpty, "default telemetry dialled \(recorder.snapshot())")
    #expect(interceptor.requests().isEmpty, "default telemetry reached the interceptor")

    // The control. Without it, an interceptor that quietly stopped listening would
    // make every assertion above pass forever.
    let enabled = try OTLPSettingsGate.enabledSettings(
        urlString: interceptor.origin.absoluteString,
        allowInsecureHTTP: true,
        previewCompleted: true
    )
    let control = EgressAttemptLog.Recorder()
    let sent = try await EgressAttemptLog.$recorder.withValue(control) {
        try await OTLPExporter(
            settings: enabled,
            transport: URLSessionHTTPTransport()
        ).export(events: [event], bodyDirectory: directory)
    }
    #expect(sent)
    #expect(control.snapshot().contains { $0.kind == .http })
    #expect(!interceptor.requests().isEmpty)
}

@Test func otlpProjectionContainsOnlyDeclaredAttributes() {
    let event = RunEvent(
        runID: RunID(rawValue: "run-secret-identifier"),
        outcomeKind: "partial",
        detail: "clinic.example.org bearer-secret-token-0123456789 72.123456 Dexcom G7",
        trigger: .bgAppRefresh,
        samplesRead: 42,
        samplesCommitted: 41,
        samplesAcked: 40,
        wallTimeEpoch: 1_700_000_000,
        errorClass: "private-error"
    )
    let payload = OTLPProjector.traces(events: [event])
    #expect(
        OTLPProjector.attributeKeys(in: payload)
            == ["service.name", "outcome", "trigger"]
    )
    let text = String(decoding: payload, as: UTF8.self)
    #expect(!text.contains(event.runID.rawValue))
    #expect(!text.contains(event.detail))
    #expect(!text.contains("samplesRead"))
    #expect(!text.contains("errorClass"))
    #if DEBUG
    #expect(RedactionCanary.isClean(text))
    #endif
}

@Test func otlpAttributeSchemaMatchesClosedRuntimeDomains() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let data = try Data(
        contentsOf: root.appendingPathComponent("spec/telemetry/attributes.json")
    )
    let object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let attributes = try #require(object["attributes"] as? [[String: Any]])
    let keys = Set(attributes.compactMap { $0["key"] as? String })
    #expect(keys == ["service.name", "ohe.destination.id", "outcome", "trigger"])
    let outcome = try #require(
        attributes.first { $0["key"] as? String == "outcome" }
    )
    let trigger = try #require(
        attributes.first { $0["key"] as? String == "trigger" }
    )
    #expect(
        Set(try #require(outcome["domain"] as? [String]))
            == Set(RunOutcome.Kind.allCases.map(\.rawValue))
    )
    #expect(
        Set(try #require(trigger["domain"] as? [String]))
            == Set(RunTrigger.allCases.map(\.rawValue))
    )
    #expect(attributes.allSatisfy { $0["healthDerived"] as? Bool == false })
}

@Test func disabledOTLPDoesNoTransportOrFileWork() async throws {
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 200, body: Data())
    )
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "ohe-otlp-disabled-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let exported = try await OTLPExporter(
        settings: .disabled,
        transport: transport
    ).export(events: [otlpRunEvent()], bodyDirectory: directory)

    #expect(!exported)
    #expect(await transport.requests.isEmpty)
    #expect(
        !FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("otlp-traces.pb").path
        )
    )
}

@Test func enabledOTLPPostsProtobufToTheAllowlistedEndpoint() async throws {
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 200, body: Data())
    )
    let destination = try HTTPSDestination(
        urlString: "https://collector.example/v1/traces",
        allowedHosts: ["collector.example"]
    )
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "ohe-otlp-enabled-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let exported = try await OTLPExporter(
        settings: OTLPExportSettings(enabled: true, endpoint: destination),
        transport: transport
    ).export(events: [otlpRunEvent()], bodyDirectory: directory)

    #expect(exported)
    let requests = await transport.requests
    let request = try #require(requests.first)
    #expect(requests.count == 1)
    #expect(request.method == "POST")
    #expect(request.url.absoluteString == "https://collector.example/v1/traces")
    #expect(request.headers == ["Content-Type": "application/x-protobuf"])
    let body = try Data(contentsOf: request.bodyFile)
    #expect(body == OTLPProjector.traces(events: [otlpRunEvent()]))
    #expect(!body.isEmpty)
}

@Test func enabledOTLPPostsFreshnessGaugesToMetricsEndpoint() async throws {
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 200, body: Data())
    )
    let traces = try HTTPSDestination(
        urlString: "https://collector.example/v1/traces",
        allowedHosts: ["collector.example"]
    )
    let metrics = try HTTPSDestination(
        urlString: "https://collector.example/v1/metrics",
        allowedHosts: ["collector.example"]
    )
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "ohe-otlp-metrics-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let destinations = [
        OTLPMetricsDestination(destinationID: "opaque-id", lastSuccessEpoch: 100),
    ]
    let exported = try await OTLPExporter(
        settings: OTLPExportSettings(enabled: true, endpoint: traces),
        transport: transport
    ).exportMetrics(
        destinations: destinations,
        nowEpoch: 200,
        endpoint: metrics,
        bodyDirectory: directory
    )

    #expect(exported)
    let requests = await transport.requests
    let request = try #require(requests.first)
    #expect(requests.count == 1)
    #expect(request.url.absoluteString == "https://collector.example/v1/metrics")
    #expect(request.headers == ["Content-Type": "application/x-protobuf"])
    #expect(
        try Data(contentsOf: request.bodyFile)
            == OTLPMetricsProjector.metrics(destinations: destinations, nowEpoch: 200)
    )
}

@Test func otlpOpportunityForbidsObserverWakesAndAllowsForegroundOrChargingWiFi() {
    #expect(OTLPOpportunity.maximumExportWakeWorkNanoseconds == 0)
    #expect(OTLPOpportunity.allow(.foreground))
    #expect(OTLPOpportunity.allow(.chargingOnWiFi))
    #expect(!OTLPOpportunity.allow(.exportBackgroundWake))
    #expect(!OTLPOpportunity.allow(.dedicatedTelemetryTask))
    #expect(
        !OTLPOpportunity.allow(
            foreground: true,
            charging: true,
            onWiFi: true,
            observerWake: true
        )
    )
    #expect(
        OTLPOpportunity.allow(
            foreground: true,
            charging: false,
            onWiFi: false,
            observerWake: false
        )
    )
    #expect(
        OTLPOpportunity.allow(
            foreground: false,
            charging: true,
            onWiFi: true,
            observerWake: false
        )
    )
    #expect(
        !OTLPOpportunity.allow(
            foreground: false,
            charging: true,
            onWiFi: false,
            observerWake: false
        )
    )
}

@Test func destinationFreshnessMetricsContainBothSeriesAndNoLabels() {
    let payload = OTLPMetricsProjector.metrics(
        destinations: [
            OTLPMetricsDestination(
                destinationID: "778615f4-opaque",
                lastSuccessEpoch: 1_699_999_900
            )
        ],
        nowEpoch: 1_700_000_000
    )
    let text = String(decoding: payload, as: UTF8.self)
    #expect(text.contains(OTLPMetricsProjector.lastSuccessMetric))
    #expect(text.contains(OTLPMetricsProjector.stalenessMetric))
    #expect(text.contains(OTLPMetricsProjector.destinationIDAttribute))
    #expect(text.contains("778615f4-opaque"))
    #expect(!text.contains("Kitchen Home Assistant"))
    #expect(
        OTLPProjector.attributeKeys(in: payload)
            == ["service.name", "ohe.destination.id"]
    )
}

@Test func destinationFreshnessMetricIDsStayInsideCardinalityCap() {
    let destinations = (0 ..< 12).map {
        OTLPMetricsDestination(
            destinationID: "destination-\(String(format: "%02d", $0))",
            lastSuccessEpoch: TimeInterval($0)
        )
    }
    let payload = OTLPMetricsProjector.metrics(destinations: destinations, nowEpoch: 100)
    let text = String(decoding: payload, as: UTF8.self)
    #expect(text.contains("destination-00"))
    #expect(text.contains("destination-06"))
    #expect(!text.contains("destination-07"))
    #expect(text.contains("other"))
}

@Test func telemetryCardinalityBudgetEnumeratesBelowBothCaps() {
    let names = TelemetryCardinalityBudget.declarations.map(\.name)
    #expect(Set(names).count == names.count)
    #expect(TelemetryCardinalityBudget.totalSeries(healthTypeEnabled: false) == 377)
    #expect(
        TelemetryCardinalityBudget.totalSeries(healthTypeEnabled: false)
            <= TelemetryCardinalityBudget.defaultLimit
    )
    #expect(TelemetryCardinalityBudget.totalSeries(healthTypeEnabled: true) == 1_448)
    #expect(
        TelemetryCardinalityBudget.totalSeries(healthTypeEnabled: true)
            <= TelemetryCardinalityBudget.healthTypeEnabledLimit
    )
}

@Test func unknownMetricAttributeBecomesOtherAndIncrementsDroppedCounter() {
    var dropped = TelemetryDroppedCounter()
    let known = TelemetryAttributeGuard.normalize(
        TelemetryTriggerClass.user.rawValue,
        as: TelemetryTriggerClass.self,
        dropped: &dropped
    )
    let unknown = TelemetryAttributeGuard.normalize(
        "runtime-user-authored-value",
        as: TelemetryTriggerClass.self,
        dropped: &dropped
    )
    #expect(known == .user)
    #expect(unknown == .other)
    #expect(dropped.unknownAttributeValues == 1)
    #expect(dropped.metricPoint.metric == "ohe.telemetry.dropped")
    #expect(dropped.metricPoint.signal == .metric)
    #expect(dropped.metricPoint.reason == .unknownAttributeValue)
    #expect(dropped.metricPoint.count == 1)
}

@Test func otlpCreatesNoDedicatedBackgroundSchedule() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let info = try String(
        contentsOf: root.appendingPathComponent("Apps/Exporter-iOS/Info.plist"),
        encoding: .utf8
    )
    #expect(!info.contains("app.openhealthexporter.otlp"))
    let source = try String(
        contentsOf: root.appendingPathComponent("Apps/Exporter-iOS/AppLifecycleCoordinator.swift"),
        encoding: .utf8
    )
    #expect(!source.contains("OTLPBackgroundCoordinator"))
    #expect(!source.contains("projectOTLP"))
}

@Test func otlpDependencyGraphUsesHTTPProtobufWithoutGRPCOrNIO() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let package = try String(
        contentsOf: root.appendingPathComponent("Package.swift"),
        encoding: .utf8
    ).lowercased()
    for forbidden in ["grpc-swift", "swift-nio", "grpcswift", "nioposix"] {
        #expect(!package.contains(forbidden), "Package.swift links forbidden product \(forbidden)")
    }
    let exporter = try String(
        contentsOf: root.appendingPathComponent("Sources/OTLPExport/OTLPExporter.swift"),
        encoding: .utf8
    )
    #expect(exporter.contains("\"Content-Type\": \"application/x-protobuf\""))
}

@Test func telemetrySerializerIsIsolatedAndItsOwnEgressCannotCreateSpans() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let directory = root.appendingPathComponent("Sources/OTLPExport")
    let files = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "swift" }
    let sources = try files.map {
        try String(contentsOf: $0, encoding: .utf8)
    }.joined(separator: "\n")
    for forbidden in [
        "NativeWire.",
        "NativeSidecars.",
        "SampleRecord",
        "DestinationSink",
        "appendJournal",
        "RunEvent(",
    ] {
        #expect(!sources.contains(forbidden), "OTLP pipeline references \(forbidden)")
    }
    let exporter = try String(
        contentsOf: directory.appendingPathComponent("OTLPExporter.swift"),
        encoding: .utf8
    )
    #expect(!exporter.contains("OTLPProjector.traces(events: ["))
    #expect(!exporter.contains("span("))
}

@Test func otlpSettingsStayDisabledUntilPreviewCompletes() {
    #expect(throws: OTLPExportError.previewRequired) {
        _ = try OTLPSettingsGate.enabledSettings(
            urlString: "https://collector.example/v1/traces",
            allowInsecureHTTP: false,
            previewCompleted: false
        )
    }
}

@Test func otlpSettingsRequireAHost() {
    #expect(throws: OTLPExportError.endpointRequired) {
        _ = try OTLPSettingsGate.enabledSettings(
            urlString: "not-a-url",
            allowInsecureHTTP: false,
            previewCompleted: true
        )
    }
}

@Test func otlpBacklogDropsAgeAndCountOverflowAndKeepsTheNewest() {
    let now: TimeInterval = 2_000_000_000
    let stale = otlpRunEvent(
        id: "old",
        wall: now - OTLPBacklog.maxAgeSeconds - 1
    )
    let overflow = (0 ..< 3).map { index in
        otlpRunEvent(id: "overflow-\(index)", wall: now - 10 + TimeInterval(index))
    }
    let keep = otlpRunEvent(id: "keep", wall: now)
    let already = otlpRunEvent(id: "done", wall: now, projected: now - 1)
    let selection = OTLPBacklog.select(
        events: [stale] + overflow + [keep, already],
        nowEpoch: now,
        cap: 1
    )
    #expect(selection.events.map(\.runID.rawValue) == ["keep"])
    #expect(Set(selection.dropped.map(\.runID.rawValue)) == Set(["old", "overflow-0", "overflow-1", "overflow-2"]))
}

@Test func otlpPreviewBytesContainOnlyAllowlistedAttributes() {
    let payload = OTLPPreview.payload(events: [otlpRunEvent()])
    let text = OTLPPreview.text(payload: payload)
    #expect(text.contains("attributes: outcome, service.name, trigger"))
    #expect(text.contains("hex:"))
    let decoded = String(decoding: payload, as: UTF8.self)
    #expect(!decoded.contains("clinic"))
    #expect(!text.contains("00000000-0000-4000-8000-000000000053"))
}

@Test func sqlitePersistsOTLPProjectionBookkeeping() async throws {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-otlp-journal-\(UUID().uuidString).sqlite")
        .path
    let store = try SQLiteStateStore(path: path)
    let event = otlpRunEvent()
    try await store.transact { try $0.appendJournal(event) }
    let unprojected = try await store.transact { try $0.unprojectedJournal(limit: 10) }
    #expect(unprojected == [event])
    try await store.transact { tx in
        try tx.markJournalProjected(runIDs: [event.runID], atEpoch: 99)
        try tx.appendLedger(
            EgressEntry(
                destination: "otlp",
                sampleCount: 0,
                outcomeKind: "success",
                byteCount: 12,
                detail: "runs=1",
                wallTimeEpoch: 99
            )
        )
    }
    let after = try await store.transact { try $0.loadJournal() }
    #expect(after.first?.projectedAtEpoch == 99)
    #expect(try await store.transact { try $0.unprojectedJournal(limit: 10) }.isEmpty)
    let ledger = try await store.transact { try $0.loadLedger() }
    #expect(ledger.last?.destination == "otlp")
    #expect(ledger.last?.sampleCount == 0)
}

@Test func unprojectedOTLPJournalSurvivesStoreRelaunch() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-otlp-relaunch-\(UUID().uuidString).sqlite")
    defer {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(
            at: URL(fileURLWithPath: url.path + "-wal")
        )
        try? FileManager.default.removeItem(
            at: URL(fileURLWithPath: url.path + "-shm")
        )
    }
    let event = otlpRunEvent(id: "survives-relaunch")
    do {
        let store = try SQLiteStateStore(path: url.path)
        try await store.transact { try $0.appendJournal(event) }
    }
    do {
        let reopened = try SQLiteStateStore(path: url.path)
        #expect(try await reopened.transact { try $0.unprojectedJournal(limit: 10) } == [event])
        try await reopened.transact {
            try $0.markJournalProjected(runIDs: [event.runID], atEpoch: 100)
        }
    }
    do {
        let reopened = try SQLiteStateStore(path: url.path)
        #expect(try await reopened.transact { try $0.unprojectedJournal(limit: 10) }.isEmpty)
    }
}

@Test func memoryStoreProjectionMarksSurviveALaterAppend() async throws {
    let store = MemoryStateStore()
    let first = otlpRunEvent(id: "a", wall: 1)
    let second = otlpRunEvent(id: "b", wall: 2)
    try await store.transact { tx in
        try tx.appendJournal(first)
        try tx.appendJournal(second)
        try tx.markJournalProjected(runIDs: [first.runID], atEpoch: 5)
    }
    let leftover = try await store.transact { try $0.unprojectedJournal(limit: 8) }
    #expect(leftover.map(\.runID.rawValue) == ["b"])
}

@Test func enabledOTLPRejectsNonSuccessStatus() async throws {
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 503, body: Data())
    )
    let destination = try HTTPSDestination(
        urlString: "https://collector.example/v1/traces",
        allowedHosts: ["collector.example"]
    )
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "ohe-otlp-failure-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    await #expect(throws: EgressError.httpStatus(503)) {
        _ = try await OTLPExporter(
            settings: OTLPExportSettings(enabled: true, endpoint: destination),
            transport: transport
        ).export(events: [otlpRunEvent()], bodyDirectory: directory)
    }
}

private func otlpRunEvent(
    id: String = "00000000-0000-4000-8000-000000000053",
    wall: TimeInterval = 1_700_000_000,
    projected: TimeInterval? = nil
) -> RunEvent {
    RunEvent(
        runID: RunID(rawValue: id),
        outcomeKind: "success",
        detail: "",
        trigger: .manual,
        wallTimeEpoch: wall,
        projectedAtEpoch: projected
    )
}
