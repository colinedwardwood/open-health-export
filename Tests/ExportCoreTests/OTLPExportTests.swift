import CoreDomain
import EnginePorts
import Foundation
import NetEgress
import OTLPExport
import Redaction
import StorageSQLite
import TestSupport
import Testing

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
    #expect(keys == ["service.name", "outcome", "trigger"])
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

@Test func otlpOpportunityForbidsObserverWakesAndAllowsForegroundOrChargingWiFi() {
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

@Test func otlpBackgroundTaskStaysOffTheHealthExportProcessingPath() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let info = try String(
        contentsOf: root.appendingPathComponent("Apps/Exporter-iOS/Info.plist"),
        encoding: .utf8
    )
    #expect(info.contains("app.openhealthexporter.otlp"))
    let source = try String(
        contentsOf: root.appendingPathComponent("Apps/Exporter-iOS/AppLifecycleCoordinator.swift"),
        encoding: .utf8
    )
    let parts = source.components(separatedBy: "enum OTLPBackgroundCoordinator")
    #expect(parts.count == 2)
    #expect(!parts[0].contains("projectOTLP"))
    #expect(parts[1].contains("projectOTLP"))
    #expect(!parts[1].contains("runOnePageEachMetric"))
    #expect(parts[1].contains("requiresExternalPower = true"))
    #expect(parts[1].contains("requiresNetworkConnectivity = true"))
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
