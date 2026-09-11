import CoreDomain
import EnginePorts
import Foundation
import NetEgress
import OTLPExport
import Redaction
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

private func otlpRunEvent() -> RunEvent {
    RunEvent(
        runID: RunID(rawValue: "00000000-0000-4000-8000-000000000053"),
        outcomeKind: "success",
        detail: "",
        trigger: .manual,
        wallTimeEpoch: 1_700_000_000
    )
}
