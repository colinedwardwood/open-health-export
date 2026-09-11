import CoreDomain
import CoreTemporal
@testable import CorrectnessEngine
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

@Test func traceparentIsWellFormedAndStableForASeed() {
    let value = Traceparent.make(seed: "0192f3c1-0000-0000-0000-000000000001")
    #expect(Traceparent.isWellFormed(value))
    #expect(value == Traceparent.make(seed: "0192f3c1-0000-0000-0000-000000000001"))
    #expect(value != Traceparent.make(seed: "other-seed"))
}

@Test func inboundTraceparentIsNeverContinued() {
    let inbound = Traceparent.make(seed: "attacker")
    let root = Traceparent.root(seed: "mac-installation", ignoringInbound: inbound)
    #expect(root != inbound)
    #expect(Traceparent.isWellFormed(root))
}

@Test func httpsDefaultSendOmitsTraceHeaders() async throws {
    let (file, batchID) = try writeTraceparentPayload()
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 204, body: Data())
    )
    let sink = HTTPSSink(
        destination: try HTTPSDestination(
            urlString: "https://ha.example/hook",
            allowedHosts: ["ha.example"]
        ),
        transport: transport,
        headerTemplates: [
            "tracestate": "vendor=secret",
            "baggage": "userId=should-not-leave",
        ]
    )
    _ = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    let headers = try #require(await transport.requests.first).headers
    #expect(headers["traceparent"] == nil)
    #expect(headers["tracestate"] == nil)
    #expect(headers["baggage"] == nil)
}

@Test func enabledTraceparentSendsOnlyThatHeader() async throws {
    let (file, batchID) = try writeTraceparentPayload()
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 204, body: Data())
    )
    let emission = TraceparentEmission(enabled: true)
    let sink = HTTPSSink(
        destination: try HTTPSDestination(
            urlString: "https://ha.example/hook",
            allowedHosts: ["ha.example"]
        ),
        transport: transport,
        traceparent: emission
    )
    let receipt = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(!receipt.traceparentAutoDisabled)
    let headers = try #require(await transport.requests.first).headers
    let value = try #require(headers["traceparent"])
    #expect(value == Traceparent.make(seed: batchID.rawValue))
    #expect(headers["tracestate"] == nil)
    #expect(headers["baggage"] == nil)
}

@Test func headerPlausibleFailureRetriesWithoutTraceparentAndDisables() async throws {
    let (file, batchID) = try writeTraceparentPayload()
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 204, body: Data())
    )
    await transport.enqueue(OutboundHTTPResponse(status: 400, body: Data()))
    let emission = TraceparentEmission(enabled: true)
    let sink = HTTPSSink(
        destination: try HTTPSDestination(
            urlString: "https://ha.example/hook",
            allowedHosts: ["ha.example"]
        ),
        transport: transport,
        traceparent: emission
    )
    let receipt = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(receipt.traceparentAutoDisabled)
    #expect(emission.autoDisabled)
    let requests = await transport.requests
    #expect(requests.count == 2)
    #expect(requests[0].headers["traceparent"] != nil)
    #expect(requests[1].headers["traceparent"] == nil)
    #expect(emission.header(seed: batchID.rawValue) == nil)
}

@Test func connectionResetBeforeResponseRetriesWithoutTraceparent() async throws {
    let (file, batchID) = try writeTraceparentPayload()
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 204, body: Data())
    )
    await transport.failOnce(EgressError.transport("connection reset"))
    let emission = TraceparentEmission(enabled: true)
    let sink = HTTPSSink(
        destination: try HTTPSDestination(
            urlString: "https://ha.example/hook",
            allowedHosts: ["ha.example"]
        ),
        transport: transport,
        traceparent: emission
    )
    let receipt = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(receipt.traceparentAutoDisabled)
    let requests = await transport.requests
    #expect(requests.count == 2)
    #expect(requests[0].headers["traceparent"] != nil)
    #expect(requests[1].headers["traceparent"] == nil)
}

@Test func unauthorizedDoesNotRetryTraceparent() async throws {
    let (file, batchID) = try writeTraceparentPayload()
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 401, body: Data())
    )
    let sink = HTTPSSink(
        destination: try HTTPSDestination(
            urlString: "https://ha.example/hook",
            allowedHosts: ["ha.example"]
        ),
        transport: transport,
        traceparent: TraceparentEmission(enabled: true)
    )
    await #expect(throws: EgressError.httpStatus(401)) {
        _ = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    }
    #expect(await transport.requests.count == 1)
}

@Test func traceparentAutoDisableIsJournalled() async throws {
    let (file, batchID) = try writeTraceparentPayload()
    let transport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 204, body: Data())
    )
    await transport.enqueue(OutboundHTTPResponse(status: 431, body: Data()))
    let sink = HTTPSSink(
        destination: try HTTPSDestination(
            urlString: "https://ha.example/hook",
            allowedHosts: ["ha.example"]
        ),
        transport: transport,
        traceparent: TraceparentEmission(enabled: true)
    )
    let store = MemoryStateStore()
    let receipt = try await DeliveryExecutor.send(
        batch: PendingBatch(
            id: batchID,
            payloadURL: file.path,
            expectedRecords: 1
        ),
        destination: .testing(sink),
        destinationName: "https",
        store: store,
        clock: FrozenClock(instant: Date(timeIntervalSince1970: 1_700_000_000))
    )
    #expect(receipt.traceparentAutoDisabled)
    let journal = try store.transaction.loadJournal()
    #expect(journal.contains { $0.outcomeKind == "traceparent_auto_disabled" })
}

private func writeTraceparentPayload() throws -> (URL, BatchID) {
    let sample = heartSample("00000000-0000-0000-0000-000000000001")
    let batchID = BatchID(rawValue: "0192f3c1-0000-0000-0000-000000000001")
    let data = try NativeWire.encode(
        samples: [sample],
        tombstones: [],
        metric: MetricID(rawValue: "heartRate"),
        batchID: batchID,
        envelope: testEnvelope()
    )
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
        "ohe-traceparent-\(UUID().uuidString)"
    )
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("batch.ndjson")
    try FileWriteKit.writeAtomically(data, to: file)
    return (file, batchID)
}
