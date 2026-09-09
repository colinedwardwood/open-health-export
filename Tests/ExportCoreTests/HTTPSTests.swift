import CoreDomain
import CorrectnessEngine
import DestinationTrust
import EnginePorts
import FileWriteKit
import Foundation
import NetEgress
import RequestTemplate
import MetricCatalog
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

@Test func duplicateHTTPSDeliveryConvergesAtTheReceiver() async throws {
    let (file, batchID) = try writeHTTPSPayload()
    let receiver = ConvergingHTTPReceiver()
    let destination = try HTTPSDestination(
        urlString: "https://ha.example/api/webhook/ohe",
        allowedHosts: ["ha.example"]
    )
    let sink = HTTPSSink(destination: destination, transport: receiver)
    let first = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    let second = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(first.accepted == 1)
    #expect(second.accepted == 1)
    #expect(await receiver.storedRows == 1)
    #expect(await receiver.deliveries == 2)
}

private actor ConvergingHTTPReceiver: HTTPTransport {
    var stored: [String: Data] = [:]
    var storedRows = 0
    var deliveries = 0

    func execute(_ request: OutboundHTTPRequest) async throws -> OutboundHTTPResponse {
        deliveries += 1
        let key = request.headers["Idempotency-Key"] ?? ""
        let body = try Data(contentsOf: request.bodyFile)
        if let existing = stored[key] {
            guard existing == body else {
                return OutboundHTTPResponse(status: 409, body: Data())
            }
        } else {
            stored[key] = body
            storedRows += NativeWire.countRecords(in: String(decoding: body, as: UTF8.self))
        }
        let accepted = NativeWire.countRecords(in: String(decoding: body, as: UTF8.self))
        let payload = Data("{\"spec\":\"ohe.wire/1\",\"accepted\":\(accepted)}".utf8)
        return OutboundHTTPResponse(status: 200, body: payload)
    }
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

@Test func httpsDestinationTestFailsOnUnauthorized() async throws {
    let destination = try HTTPSDestination(
        urlString: "https://ha.example/hook",
        allowedHosts: ["ha.example"],
        authorizationBearer: "super-secret-token"
    )
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 401, body: Data()),
        tls: sampleIdentity(leaf: "aaaabbbbccccdddd")
    )
    let report = await HTTPSDestinationTest.run(
        destination: destination,
        transport: transport,
        canary: Data("canary\n".utf8)
    )
    #expect(report.verdict == .failed)
    #expect(report.failingStep == .authenticate)
}

@Test func httpsDestinationTestRejectsPinChange() async throws {
    let destination = try HTTPSDestination(
        urlString: "https://ha.example/hook",
        allowedHosts: ["ha.example"]
    )
    let observed = sampleIdentity(leaf: "eeeeffff00001111")
    let stored = PinRecord(
        leafSPKISha256: "aaaabbbbccccdddd",
        issuerSPKISha256: "issuer00",
        firstSeen: "2024-01-01T00:00:00Z",
        policy: .leaf
    )
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 204, body: Data()),
        tls: observed
    )
    let report = await HTTPSDestinationTest.run(
        destination: destination,
        transport: transport,
        pin: stored,
        canary: Data("canary\n".utf8)
    )
    #expect(report.verdict == .failed)
    #expect(report.failingStep == .confirmCertificate)
}

@Test func haEntityReadbackRequiresDeclaredUnitAndStateClass() async throws {
    let destination = try HTTPSDestination(
        urlString: "https://ha.example/api/states/sensor.ohe_steps",
        allowedHosts: ["ha.example"]
    )
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 200, body: Data()),
        tls: sampleIdentity(leaf: "aaaabbbbccccdddd")
    )
    await transport.enqueue(OutboundHTTPResponse(status: 201, body: Data()))
    await transport.enqueue(
        OutboundHTTPResponse(
            status: 200,
            body: Data(
                """
                {"attributes":{"unit_of_measurement":"steps","state_class":"total_increasing"}}
                """.utf8
            )
        )
    )
    let report = await HTTPSDestinationTest.run(
        destination: destination,
        transport: transport,
        canary: Data("canary\n".utf8),
        entityURL: destination.url,
        expected: MetricCatalog.stepCount
    )
    #expect(report.verdict == .passed)
    #expect(
        !HAEntityReadback.matches(
            declaration: MetricCatalog.stepCount,
            json: Data("{\"attributes\":{\"unit_of_measurement\":\"kcal\"}}".utf8)
        )
    )
}

@Test func httpsDestinationTestPassesAndDoesNotLeakBearer() async throws {
    let destination = try HTTPSDestination(
        urlString: "https://ha.example/hook",
        allowedHosts: ["ha.example"],
        authorizationBearer: "super-secret-token"
    )
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 204, body: Data()),
        tls: sampleIdentity(leaf: "aaaabbbbccccdddd")
    )
    let report = await HTTPSDestinationTest.run(
        destination: destination,
        transport: transport,
        canary: Data("canary\n".utf8)
    )
    #expect(report.verdict == .passed)
    #expect(report.failingStep == nil)
}

@Test func haEntityReadbackFailsOnWrongStateClass() async throws {
    let destination = try HTTPSDestination(
        urlString: "https://ha.example/api/states/sensor.ohe_steps",
        allowedHosts: ["ha.example"]
    )
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 200, body: Data()),
        tls: sampleIdentity(leaf: "aaaabbbbccccdddd")
    )
    await transport.enqueue(OutboundHTTPResponse(status: 201, body: Data()))
    await transport.enqueue(
        OutboundHTTPResponse(
            status: 200,
            body: Data("{\"attributes\":{\"unit_of_measurement\":\"steps\",\"state_class\":\"measurement\"}}".utf8)
        )
    )
    let report = await HTTPSDestinationTest.run(
        destination: destination,
        transport: transport,
        canary: Data("canary\n".utf8),
        entityURL: destination.url,
        expected: MetricCatalog.stepCount
    )
    #expect(report.verdict == .failed)
    #expect(report.failingStep == .readResponse)
}

@Test func httpsDestinationEnableRequiresTheRealPathTestAndPinsTLS() async throws {
    let destination = try HTTPSDestination(
        urlString: "https://receiver.example/export",
        allowedHosts: ["receiver.example"]
    )
    let identity = sampleIdentity(leaf: "aaaabbbbccccdddd")
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 204, body: Data()),
        tls: identity
    )
    let enabled = try await HTTPSDestinationEnable.complete(
        destination: destination,
        transport: transport,
        exporterID: "00000000-0000-4000-8000-000000000025",
        emittedAt: "2026-01-01T00:00:00Z"
    )
    #expect(enabled.report.allowsEnablement)
    #expect(enabled.identity == identity)
    #expect(
        enabled.events == [
            .canaryConfirmed,
            .pinRecorded(groupedFingerprint: TLSIdentity.grouped(identity.leafSPKISha256)),
            .destinationEnabled,
        ]
    )

    let rejected = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 401, body: Data()),
        tls: identity
    )
    await #expect(throws: SetupError.verificationRequired) {
        _ = try await HTTPSDestinationEnable.complete(
            destination: destination,
            transport: rejected,
            exporterID: "00000000-0000-4000-8000-000000000025",
            emittedAt: "2026-01-01T00:00:00Z"
        )
    }
}

@Test func systemHTTPTransportFactoryHonorsThePersistedAllowlistBeforeProbing() async throws {
    let url = try #require(URL(string: "http://receiver.example/export"))
    let transport = try SystemHTTPTransport.make(
        probing: url,
        allowedHosts: ["receiver.example"],
        allowInsecureHTTP: true
    )
    #expect(try await transport.identityProbe() == nil)
    #expect(throws: EgressError.notAllowlisted("receiver.example")) {
        _ = try SystemHTTPTransport.make(
            probing: url,
            allowedHosts: ["other.example"],
            allowInsecureHTTP: true
        )
    }
}
