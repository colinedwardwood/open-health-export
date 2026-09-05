import CoreDomain
import CorrectnessEngine
import DestinationTrust
import EnginePorts
import FileWriteKit
import Foundation
import NetEgress
import RequestTemplate
import SinkHTTP
import TestSupport
import Testing
import WireFormat

@Test func httpsAllowlistRejectsHostBeforeConnect() {
    #expect(throws: EgressError.notAllowlisted("evil.example")) {
        _ = try HTTPSDestination(
            urlString: "https://evil.example/hook",
            allowedHosts: ["ha.example"]
        )
    }
    #expect(throws: EgressError.insecureHTTP) {
        _ = try HTTPSDestination(
            urlString: "http://ha.example/hook",
            allowedHosts: ["ha.example"]
        )
    }
    #expect(throws: EgressError.forbiddenScheme("javascript")) {
        _ = try HTTPSDestination(
            urlString: "javascript:alert(1)",
            allowedHosts: ["ha.example"]
        )
    }
    #expect(throws: EgressError.credentialsInURL) {
        _ = try HTTPSDestination(
            urlString: "https://user:secret@ha.example/hook",
            allowedHosts: ["ha.example"]
        )
    }
    let ok = try? HTTPSDestination(
        urlString: "http://ha.example/hook",
        allowedHosts: ["ha.example"],
        allowInsecureHTTP: true
    )
    #expect(ok?.url.host == "ha.example")
    #expect(ok?.url.scheme == "http")
}

@Test func httpsWebhook2xxWithoutReceiptIsStatusOnly() async throws {
    let (file, batchID) = try writeHTTPSPayload()
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 204, body: Data())
    )
    let destination = try HTTPSDestination(
        urlString: "https://ha.example/api/webhook/ohe",
        allowedHosts: ["ha.example"]
    )
    let sink = HTTPSSink(destination: destination, transport: transport)
    let receipt = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(receipt.statusOnly)
    #expect(receipt.accepted == 1)
    let requests = await transport.requests
    #expect(requests.count == 1)
    #expect(requests[0].url.host == "ha.example")
    #expect(requests[0].url.path == "/api/webhook/ohe")
    #expect(requests[0].method == "POST")
    #expect(requests[0].headers["Idempotency-Key"] == batchID.rawValue)
    #expect(requests[0].headers["Content-Type"] == "application/x-ndjson; profile=\"ohe.wire/1\"")
}

@Test func httpsReceiptBodyIsFullAckEvidence() async throws {
    let (file, batchID) = try writeHTTPSPayload()
    let body = Data("{\"spec\":\"ohe.wire/1\",\"accepted\":1}".utf8)
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 200, body: body)
    )
    let destination = try HTTPSDestination(
        urlString: "https://ha.example/ingest",
        allowedHosts: ["ha.example"]
    )
    let sink = HTTPSSink(destination: destination, transport: transport)
    let receipt = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(!receipt.statusOnly)
    #expect(receipt.accepted == 1)
}

@Test func https5xxDoesNotAck() async throws {
    let (file, batchID) = try writeHTTPSPayload()
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 503, body: Data())
    )
    let destination = try HTTPSDestination(
        urlString: "https://ha.example/ingest",
        allowedHosts: ["ha.example"]
    )
    let sink = HTTPSSink(destination: destination, transport: transport)
    await #expect(throws: EgressError.httpStatus(503)) {
        _ = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    }
}

@Test func httpsWebhook2xxDrivesSuccessStatusOnlyOnTheEngine() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("dddddddd-dddd-dddd-dddd-dddddddddddd")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0xDD]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 200, body: Data("ok".utf8))
    )
    let destination = try HTTPSDestination(
        urlString: "https://ha.example/api/webhook/ohe",
        allowedHosts: ["ha.example"]
    )
    let sink = HTTPSSink(destination: destination, transport: transport)
    let store = MemoryStateStore()
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-https-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    let run = ExportRun(
        source: FixtureSource(pages: [page]),
        destination: .testing(sink),
        store: store,
        metric: metric,
        scratchDirectory: scratch,
        destinationName: "https",
        envelope: testEnvelope()
    )
    let outcome = try await run.run()
    #expect(outcome.kind == .success)
    #expect(outcome.ackEvidence == .statusOnly)
}

@Test func httpsShortReceiptIsPartial() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0xEE]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(
            status: 200,
            body: Data("{\"accepted\":0}".utf8)
        )
    )
    let destination = try HTTPSDestination(
        urlString: "https://ha.example/ingest",
        allowedHosts: ["ha.example"]
    )
    let sink = HTTPSSink(destination: destination, transport: transport)
    let store = MemoryStateStore()
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-https-p-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    let run = ExportRun(
        source: FixtureSource(pages: [page]),
        destination: .testing(sink),
        store: store,
        metric: metric,
        scratchDirectory: scratch,
        destinationName: "https",
        envelope: testEnvelope()
    )
    let outcome = try await run.run()
    #expect(outcome.kind == .partial)
    #expect(outcome.partialCause == "receipt_short")
}

@Test func httpsHeaderTemplateCannotInjectOrMoveHost() async throws {
    let (file, batchID) = try writeHTTPSPayload()
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 204, body: Data())
    )
    let destination = try HTTPSDestination(
        urlString: "https://ha.example/api/webhook/ohe",
        allowedHosts: ["ha.example"]
    )
    let injected = HTTPSSink(
        destination: destination,
        transport: ForbiddenHTTPTransport(),
        headerTemplates: ["X-Token": "{{secret:t|header}}"],
        secrets: MemorySecrets(["t": "ok\r\nX-Injected: 1"])
    )
    await #expect(throws: TemplateError.headerInjection) {
        _ = try await injected.send(fileHandle: file.path, idempotencyKey: batchID)
    }

    let wrapped = HTTPSSink(
        destination: destination,
        transport: transport,
        bodyTemplate: "{\"batch\":{{batchId|json}},\"count\":{{recordCount|raw}}}"
    )
    _ = try await wrapped.send(fileHandle: file.path, idempotencyKey: batchID)
    let requests = await transport.requests
    #expect(requests[0].url.host == "ha.example")
    #expect(requests[0].url.path == "/api/webhook/ohe")
    let body = String(decoding: try Data(contentsOf: requests[0].bodyFile), as: UTF8.self)
    #expect(body.contains("\"batch\":\"0192f3c1-0000-0000-0000-000000000001\""))
    #expect(body.contains("\"count\":1"))
}

private func writeHTTPSPayload() throws -> (URL, BatchID) {
    let sample = heartSample("00000000-0000-0000-0000-000000000001")
    let batchID = BatchID(rawValue: "0192f3c1-0000-0000-0000-000000000001")
    let data = try NativeWire.encode(
        samples: [sample],
        tombstones: [],
        metric: MetricID(rawValue: "heartRate"),
        batchID: batchID,
        envelope: testEnvelope()
    )
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-https-payload-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("batch.ndjson")
    try FileWriteKit.writeAtomically(data, to: file)
    return (file, batchID)
}
