import CoreDomain
import DestinationTrust
import EnginePorts
import Foundation
import NetEgress
import TestSupport
import Testing
import WireFormat

func sampleIdentity(leaf: String, issuer: String = "issuer00") -> TLSIdentity {
    TLSIdentity(
        leafSPKISha256: leaf,
        issuerSPKISha256: issuer,
        tlsVersion: "TLS1.3",
        cipherSuite: "TLS_AES_128_GCM_SHA256",
        leafSubject: "CN=ha.example",
        leafIssuer: "CN=Example CA",
        notBefore: "2024-01-01T00:00:00Z",
        notAfter: "2025-01-01T00:00:00Z",
        resolvedAddress: "192.168.1.10",
        addressClass: .privateRFC1918,
        trustAnchorKind: "publicCA"
    )
}

@Test func destinationCannotEnableUntilPinned() throws {
    var setup = DestinationSetup()
    #expect(setup.state == .draft)
    #expect(throws: SetupError.illegalTransition(from: .draft, to: .enabled)) {
        _ = try setup.enable(sink: LocalFileSinkStub())
    }
    let preview = try NativeWire.encodeCanary(
        code: "ABCD-EF01",
        batchID: BatchID(rawValue: "0192f3c1-0000-0000-0000-000000000001"),
        envelope: testEnvelope()
    )
    try setup.recordPreview(preview)
    #expect(setup.previewBytes == preview)
    try setup.markCanarySent(code: "ABCD-EF01")
    #expect(throws: SetupError.canaryMismatch) {
        try setup.confirmCanary("nope")
    }
    try setup.confirmCanary("ABCD-EF01")
    try setup.pinWithoutTLS()
    let verified = try setup.enable(sink: LocalFileSinkStub())
    _ = verified.sink
    #expect(setup.state == .enabled)
}

@Test func canaryPayloadIsNotHealthSamples() throws {
    let data = try NativeWire.encodeCanary(
        code: "ABCD-EF01",
        batchID: BatchID(rawValue: "0192f3c1-0000-0000-0000-000000000001"),
        envelope: testEnvelope()
    )
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("\"kind\":\"canary\""))
    #expect(text.contains("\"code\":\"ABCD-EF01\""))
    #expect(text.contains("\"reason\":\"destinationTest\""))
    #expect(!text.contains("heart_rate"))
    #expect(!text.contains("sample.quantity"))
}

@Test func previewBytesMatchProductionEncoder() throws {
    let sample = heartSample("00000000-0000-0000-0000-000000000001")
    let encoded = try NativeWire.encode(
        samples: [sample],
        tombstones: [],
        metric: MetricID(rawValue: "heartRate"),
        batchID: BatchID(rawValue: "0192f3c1-0000-0000-0000-000000000001"),
        envelope: testEnvelope()
    )
    var setup = DestinationSetup()
    try setup.recordPreview(encoded)
    #expect(setup.previewBytes == encoded)
}

@Test func pinMismatchSendsZeroBytes() async throws {
    let identityA = sampleIdentity(leaf: "aaaabbbbccccdddd")
    let identityB = sampleIdentity(leaf: "eeeeffff00001111")
    var setup = DestinationSetup()
    try setup.recordPreview(Data("preview".utf8))
    try setup.markCanarySent(code: "CODE")
    try setup.confirmCanary("CODE")
    try setup.recordPin(from: identityA, at: "2024-01-01T00:00:00Z", policy: .leaf)
    #expect(identityA.groupedLeafFingerprint.contains(" "))
    let inner = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 204, body: Data()),
        tls: identityB
    )
    let pinning = PinningHTTPTransport(inner: inner, pin: setup.pin!)
    let dummy = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-pin-\(UUID().uuidString)")
    try Data("x".utf8).write(to: dummy)
    let request = OutboundHTTPRequest(
        method: "POST",
        url: URL(string: "https://ha.example/hook")!,
        headers: [:],
        bodyFile: dummy
    )
    await #expect(throws: EgressError.pinMismatch) {
        _ = try await pinning.execute(request)
    }
    let sent = await inner.requests
    #expect(sent.isEmpty)
    #expect(throws: PinError.mismatch) {
        try setup.observeIdentity(identityB, at: "2024-01-02T00:00:00Z")
    }
    #expect(setup.state == .halted)
}

@Test func transportFailureIsNotPinChange() throws {
    var setup = DestinationSetup()
    try setup.recordPreview(Data())
    try setup.markCanarySent(code: "C")
    try setup.confirmCanary("C")
    try setup.recordPin(from: sampleIdentity(leaf: "aaaabbbbccccdddd"), at: "2024-01-01T00:00:00Z", policy: .leaf)
    setup.noteTransportFailure()
    #expect(setup.state == .pinned)
}

@Test func httpPreviewMasksAuthorization() {
    let preview = HTTPPreview.render(
        method: "POST",
        url: "https://ha.example/hook",
        headers: ["Authorization": "Bearer super-secret", "Idempotency-Key": "k1"],
        body: Data("body".utf8)
    )
    let text = String(decoding: preview, as: UTF8.self)
    #expect(text.contains("Bearer ****"))
    #expect(!text.contains("super-secret"))
    #expect(text.contains("Idempotency-Key: k1"))
    #expect(text.hasSuffix("body"))
}

@Test func addressClassPrivateAndLoopback() {
    #expect(AddressClassifying.classify("127.0.0.1") == .loopback)
    #expect(AddressClassifying.classify("10.0.0.1") == .privateRFC1918)
    #expect(AddressClassifying.classify("192.168.1.1") == .privateRFC1918)
    #expect(AddressClassifying.classify("8.8.8.8") == .publicUnicast)
}

private struct LocalFileSinkStub: DestinationSink {
    func send(fileHandle: String, idempotencyKey: BatchID) async throws -> DeliveryReceipt {
        DeliveryReceipt(batchID: idempotencyKey, accepted: 0, statusOnly: true)
    }
}
