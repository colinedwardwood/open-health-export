// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

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
    #expect(requests[0].headers["Content-Encoding"] == "gzip")
    #expect(requests[0].headers["traceparent"] == nil)
    #expect(requests[0].headers["tracestate"] == nil)
    #expect(requests[0].headers["baggage"] == nil)
}

@Test func duplicateHTTPSDeliveryConvergesAtTheReceiver() async throws {
    let (file, batchID) = try writeHTTPSPayload()
    let receiver = ConvergingHTTPReceiver()
    let destination = try HTTPSDestination(
        urlString: "https://ha.example/api/webhook/ohe",
        allowedHosts: ["ha.example"]
    )
    let sink = HTTPSSink(destination: destination, transport: receiver)
    for replay in 1 ... 10 {
        let receipt = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
        #expect(receipt.accepted == 1, "replay \(replay)")
    }
    #expect(await receiver.storedRows == 1)
    #expect(await receiver.deliveries == 10)
}

private actor ConvergingHTTPReceiver: HTTPTransport {
    var stored: [String: Data] = [:]
    var storedRows = 0
    var deliveries = 0

    func execute(_ request: OutboundHTTPRequest) async throws -> OutboundHTTPResponse {
        deliveries += 1
        let key = request.headers["Idempotency-Key"] ?? ""
        var body = try Data(contentsOf: request.bodyFile)
        if request.headers["Content-Encoding"] == "gzip" {
            body = try Gzip.decompress(body)
        }
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
    let gzipped = try Data(contentsOf: requests[0].bodyFile)
    let body = String(decoding: try Gzip.decompress(gzipped), as: UTF8.self)
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

    let probed = try await HTTPSDestinationEnable.probe(
        destination: destination,
        transport: transport,
        exporterID: "00000000-0000-4000-8000-000000000025",
        emittedAt: "2026-01-01T00:00:00Z"
    )
    #expect(!probed.pendingEvents.contains(.destinationEnabled))
    #expect(probed.report.allowsEnablement)
    let committed = try HTTPSDestinationEnable.commit(probe: probed, transport: transport)
    #expect(
        committed.events == [
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

@Test func gzipRoundTripsAndHTTPSBodiesAreGzipEncoded() throws {
    let original = Data((0..<4_000).map { UInt8($0 % 251) })
    let compressed = try Gzip.compress(original)
    #expect(try Gzip.decompress(compressed) == original)
    #expect(compressed.count < original.count)
}

@Test func httpRetryAfterParsesDeltaSecondsAndHTTPDate() {
    #expect(HTTPRetryAfter.parse("30", now: Date(timeIntervalSince1970: 0)) == 30)
    #expect(HTTPRetryAfter.parse("100000", now: Date(timeIntervalSince1970: 0)) == HTTPRetryAfter.maximum)
    let now = Date(timeIntervalSince1970: 1_000)
    #expect(
        HTTPRetryAfter.parse("Thu, 01 Jan 1970 00:16:50 GMT", now: now) == 10
    )
    #expect(HTTPRetryAfter.parse("nope", now: now) == nil)
}

@Test func httpsHonoursRetryAfterOnTransientFailure() async throws {
    let (file, batchID) = try writeHTTPSPayload()
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(
            status: 429,
            body: Data(),
            headers: ["Retry-After": "120"]
        )
    )
    let destination = try HTTPSDestination(
        urlString: "https://ha.example/ingest",
        allowedHosts: ["ha.example"]
    )
    let sink = HTTPSSink(destination: destination, transport: transport)
    await #expect(throws: EgressError.httpRetryAfter(status: 429, seconds: 120)) {
        _ = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    }
}

@Test func scriptableHTTPServerCoversStatusLatencyChunkedRedirectRetryAndReset() async throws {
    let server = ScriptableHTTPServer()
    try server.start()
    defer { server.stop() }

    server.enqueue(
        ScriptableHTTPServer.Script(
            status: 204,
            delayNanoseconds: 80_000_000
        )
    )
    server.enqueue(
        ScriptableHTTPServer.Script(
            status: 302,
            headers: ["Location": "http://evil.example/hook"]
        )
    )
    server.enqueue(
        ScriptableHTTPServer.Script(
            status: 429,
            headers: ["Retry-After": "15"]
        )
    )
    server.enqueue(
        try ScriptableHTTPServer.Script.json(["accepted": 7], status: 200).withChunkSize(5)
    )
    server.enqueue(
        ScriptableHTTPServer.Script(
            status: 200,
            body: Data(repeating: 0x41, count: 64),
            closeAfterBodyBytes: 8
        )
    )

    let transport = URLSessionHTTPTransport()
    let body = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-http-loopback-\(UUID().uuidString)")
    try Data("ping".utf8).write(to: body)

    let clock = ContinuousClock()
    let delayed = try await clock.measure {
        _ = try await transport.execute(
            OutboundHTTPRequest(
                method: "POST",
                url: server.origin.appendingPathComponent("delay"),
                headers: ["X-Test": "latency"],
                bodyFile: body
            )
        )
    }
    #expect(delayed >= .milliseconds(80))

    let redirected = try await transport.execute(
        OutboundHTTPRequest(
            method: "POST",
            url: server.origin.appendingPathComponent("redirect"),
            headers: [:],
            bodyFile: body
        )
    )
    #expect(redirected.status == 302)
    #expect(redirected.header("Location") == "http://evil.example/hook")

    let limited = try await transport.execute(
        OutboundHTTPRequest(
            method: "POST",
            url: server.origin.appendingPathComponent("retry"),
            headers: [:],
            bodyFile: body
        )
    )
    #expect(limited.status == 429)
    #expect(limited.header("Retry-After") == "15")

    let chunked = try await transport.execute(
        OutboundHTTPRequest(
            method: "POST",
            url: server.origin.appendingPathComponent("chunked"),
            headers: [:],
            bodyFile: body
        )
    )
    #expect(chunked.status == 200)
    let object = try JSONSerialization.jsonObject(with: chunked.body) as? [String: Any]
    #expect(object?["accepted"] as? Int == 7)

    await #expect(throws: (any Error).self) {
        _ = try await transport.execute(
            OutboundHTTPRequest(
                method: "POST",
                url: server.origin.appendingPathComponent("reset"),
                headers: [:],
                bodyFile: body
            )
        )
    }

    let recorded = server.requests()
    #expect(recorded.map(\.target) == ["/delay", "/redirect", "/retry", "/chunked", "/reset"])
    #expect(recorded.allSatisfy { $0.method == "POST" })
    #expect(recorded.contains { $0.headers["x-test"] == "latency" })
}

@Test func scriptableHTTPServerSlowLorisDelaysEachResponseByte() async throws {
    let server = ScriptableHTTPServer()
    try server.start()
    defer { server.stop() }
    server.enqueue(
        ScriptableHTTPServer.Script(
            status: 204,
            slowLorisNanosecondsPerByte: 2_000_000
        )
    )
    let transport = URLSessionHTTPTransport()
    let body = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-slowloris-\(UUID().uuidString)")
    try Data("ping".utf8).write(to: body)
    let clock = ContinuousClock()
    let elapsed = try await clock.measure {
        _ = try await transport.execute(
            OutboundHTTPRequest(
                method: "POST",
                url: server.origin.appendingPathComponent("slow"),
                headers: [:],
                bodyFile: body
            )
        )
    }
    #expect(elapsed >= .milliseconds(40))
}

@Test func httpsSinkDeliversOverLoopbackHTTPAndHonoursQueued401ThenSuccess() async throws {
    let server = ScriptableHTTPServer()
    try server.start()
    defer { server.stop() }
    server.enqueue(ScriptableHTTPServer.Script(status: 401))
    server.enqueue(ScriptableHTTPServer.Script(status: 204))

    let (file, batchID) = try writeHTTPSPayload()
    let destination = try HTTPSDestination(
        urlString: server.origin.appendingPathComponent("hook").absoluteString,
        allowedHosts: ["127.0.0.1"],
        allowInsecureHTTP: true
    )
    let sink = HTTPSSink(destination: destination, transport: URLSessionHTTPTransport())
    await #expect(throws: EgressError.httpStatus(401)) {
        _ = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    }
    let receipt = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(receipt.statusOnly)
    let recorded = server.requests()
    #expect(recorded.count == 2)
    #expect(recorded[0].headers["idempotency-key"] == batchID.rawValue)
    #expect(recorded[0].headers["content-encoding"] == "gzip")
    #expect(try Gzip.decompress(recorded[0].body).isEmpty == false)
}

#if canImport(Network)
@Suite(.serialized)
struct HTTPSPinnedLoopbackTests {
@Test func httpsEnablePinsSelfSignedLoopbackAndURLSessionHonoursThePin() async throws {
    let material = try LoopbackTLS.material()
    let server = try LocalHTTPSServer(parameters: LocalHTTPSServer.tlsParameters(identity: material.identity))
    let port = try await server.start()
    let destination = try HTTPSDestination(
        urlString: "https://127.0.0.1:\(port)/hook",
        allowedHosts: ["127.0.0.1"]
    )
    let transport = try SystemHTTPTransport.make(
        probing: destination.url,
        allowedHosts: ["127.0.0.1"]
    )
    let completed = try await HTTPSDestinationEnable.complete(
        destination: destination,
        transport: transport,
        exporterID: "00000000-0000-4000-8000-000000000025",
        emittedAt: "2026-01-01T00:00:00Z"
    )
    #expect(completed.identity?.leafSPKISha256 == material.pin.leafSPKISha256)
    #expect(completed.report.allowsEnablement)
    let preview = String(decoding: completed.preview, as: UTF8.self)
    #expect(preview.contains("\"kind\":\"canary\""))
    #expect(preview.contains("\"code\":\"OHE1-HTTPS\""))
    #expect(!preview.contains("\"kind\":\"sample."))
    let (file, batchID) = try writeHTTPSPayload()
    let sink = HTTPSSink(
        destination: destination,
        transport: PinningHTTPTransport(inner: transport, pin: material.pin)
    )
    let receipt = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(receipt.statusOnly)
    await server.stop()
}

@Test func httpsPinnedURLSessionRejectsAMismatchedLeaf() async throws {
    let material = try LoopbackTLS.material()
    let server = try LocalHTTPSServer(parameters: LocalHTTPSServer.tlsParameters(identity: material.identity))
    let port = try await server.start()
    let destination = try HTTPSDestination(
        urlString: "https://127.0.0.1:\(port)/hook",
        allowedHosts: ["127.0.0.1"]
    )
    let wrong = PinRecord(
        leafSPKISha256: String(repeating: "ab", count: 32),
        issuerSPKISha256: String(repeating: "cd", count: 32),
        firstSeen: "2024-01-01T00:00:00Z",
        policy: .leaf
    )
    let (file, batchID) = try writeHTTPSPayload()
    let sink = HTTPSSink(
        destination: destination,
        transport: PinningHTTPTransport(
            inner: try SystemHTTPTransport.make(
                probing: destination.url,
                allowedHosts: ["127.0.0.1"]
            ),
            pin: wrong
        )
    )
    await #expect(throws: EgressError.pinMismatch) {
        _ = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    }
    await server.stop()
}

@Test func httpsSinkPostsOverHTTP2WhenThePeerAdvertisesALPN() async throws {
    let material = try LoopbackTLS.material()
    let server = try LocalHTTP2Server(parameters: LocalHTTP2Server.tlsParameters(identity: material.identity))
    let port = try await server.start()
    let destination = try HTTPSDestination(
        urlString: "https://127.0.0.1:\(port)/hook",
        allowedHosts: ["127.0.0.1"]
    )
    let (file, batchID) = try writeHTTPSPayload()
    let sink = HTTPSSink(
        destination: destination,
        transport: PinningHTTPTransport(
            inner: try SystemHTTPTransport.make(
                probing: destination.url,
                allowedHosts: ["127.0.0.1"]
            ),
            pin: material.pin
        )
    )
    let receipt = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(receipt.statusOnly)
    #expect(await server.prefaceSeen())
    #expect(await server.requestCount() == 1)
    await server.stop()
}
}
#endif

private extension ScriptableHTTPServer.Script {
    func withChunkSize(_ size: Int) -> ScriptableHTTPServer.Script {
        var copy = self
        copy.chunkSize = size
        return copy
    }
}
