// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import DestinationTrust
import EnginePorts
import Foundation
import NetEgress
import SinkLocalFile
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
    try setup.recordTest(.passedLocalFile)
    let verified = try setup.enable(sink: LocalFileSinkStub())
    _ = verified.sink
    #expect(setup.state == .enabled)
}

@Test func destinationResumeEnabledDoesNotReEmitTrustEvents() throws {
    var setup = DestinationSetup()
    try setup.resumeEnabled(testReport: .passedLocalFile)
    #expect(setup.state == .enabled)
    #expect(setup.drainEvents().isEmpty)
    _ = try setup.enable(sink: LocalFileSinkStub())
    #expect(setup.drainEvents().isEmpty)
}

@Test func destinationCannotEnableUntilPathTestPasses() throws {
    var setup = DestinationSetup()
    try setup.recordPreview(Data("preview".utf8))
    try setup.markCanarySent(code: "ABCD-EF01")
    try setup.confirmCanary("ABCD-EF01")
    try setup.pinWithoutTLS()
    #expect(throws: SetupError.verificationRequired) {
        _ = try setup.enable(sink: LocalFileSinkStub())
    }
    try setup.recordTest(.failed(at: .openFolder))
    #expect(throws: SetupError.verificationRequired) {
        _ = try setup.enable(sink: LocalFileSinkStub())
    }
    try setup.recordTest(
        DestinationTestReport(
            verdict: .sentUnconfirmed,
            steps: [
                DestinationTestStepReport(name: .publishCanary, outcome: .sentUnconfirmed),
            ]
        )
    )
    _ = try setup.enable(sink: LocalFileSinkStub())
    #expect(setup.state == .enabled)
}

@Test func localFileDestinationTestWritesAndReadsCanary() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-dest-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let report = try LocalFileDestinationTest.run(directory: directory, canary: Data("canary-bytes\n".utf8))
    #expect(report.verdict == .passed)
    #expect(report.failingStep == nil)
    #expect(try Data(contentsOf: directory.appendingPathComponent("ohe-canary.ndjson")) == Data("canary-bytes\n".utf8))
    let missing = try LocalFileDestinationTest.run(
        directory: directory.appendingPathComponent("no-such-folder")
    )
    #expect(missing.verdict == .failed)
    #expect(missing.failingStep == .openFolder)
}

@Test func localFileDestinationEnableRequiresAPassingPathTest() throws {
    let missing = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-enable-missing-\(UUID().uuidString)")
    #expect(throws: SetupError.verificationRequired) {
        _ = try LocalFileDestinationEnable.complete(
            directory: missing,
            exporterId: "exporter-1",
            emittedAt: "2024-01-01T00:00:00Z"
        )
    }
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-enable-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let first = try LocalFileDestinationEnable.complete(
        directory: directory,
        exporterId: "exporter-1",
        emittedAt: "2024-01-01T00:00:00Z"
    )
    #expect(first.report.verdict == .passed)
    #expect(first.events == [
        .canaryConfirmed,
        .pinRecorded(groupedFingerprint: nil),
        .destinationEnabled,
    ])
    let resume = try LocalFileDestinationEnable.resume(directory: directory, testReport: first.report)
    _ = resume.sink
}

@Test func mqttQoS0TestIsNeverSuccess() {
    #expect(DestinationTest.mqttVerdict(confirmsDelivery: false) == .sentUnconfirmed)
    #expect(DestinationTest.mqttVerdict(confirmsDelivery: true) == .passed)
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

@Test func confirmationCardShowsGroupedSPKIAndDryRunPreview() {
    let identity = sampleIdentity(leaf: "aaaabbbbccccdddd")
    let preview = Data("{\"kind\":\"canary\",\"code\":\"OHE1-HTTPS\"}\n".utf8)
    let card = DestinationConfirmationCard(
        host: "homeassistant.local",
        identity: identity,
        preview: preview,
        insecureWithoutTLS: false
    )
    #expect(card.lines.first == ConfirmationCopy.title)
    #expect(card.lines.contains { $0.contains("a private address") })
    #expect(card.lines.contains { $0.contains(identity.groupedLeafFingerprint) })
    #expect(card.lines.contains(ConfirmationCopy.remember))
    #expect(card.lines.contains(ConfirmationCopy.previewHeading))
    #expect(card.lines.contains { $0.contains("\"kind\":\"canary\"") })
}

@Test func onlyPublicDestinationCardsRequireTheTypedPhrase() {
    var publicIdentity = sampleIdentity(leaf: "aaaabbbbccccdddd")
    publicIdentity.resolvedAddress = "203.0.113.10"
    publicIdentity.addressClass = .publicUnicast
    let publicCard = DestinationConfirmationCard(
        host: "collector.example.com",
        identity: publicIdentity,
        preview: Data(),
        insecureWithoutTLS: false
    )
    #expect(publicCard.requiresPublicAddressConfirmation)
    #expect(ConfirmationCopy.publicAddressWarning.contains(ConfirmationCopy.publicAddressPhrase))

    let privateCard = DestinationConfirmationCard(
        host: "homeassistant.local",
        identity: sampleIdentity(leaf: "aaaabbbbccccdddd"),
        preview: Data(),
        insecureWithoutTLS: false
    )
    #expect(!privateCard.requiresPublicAddressConfirmation)

    let literalPublicHTTP = DestinationConfirmationCard(
        host: "8.8.8.8",
        identity: nil,
        preview: Data(),
        insecureWithoutTLS: true
    )
    #expect(literalPublicHTTP.requiresPublicAddressConfirmation)
}

@Test func resumeAfterPassedTestDoesNotReemitPinEvents() throws {
    var setup = DestinationSetup()
    try setup.resumeAfterPassedTest(
        preview: Data("preview".utf8),
        pin: PinRecord(
            leafSPKISha256: "aaaabbbbccccdddd",
            issuerSPKISha256: "issuer00",
            firstSeen: "2026-01-01T00:00:00Z",
            policy: .leaf
        ),
        identity: sampleIdentity(leaf: "aaaabbbbccccdddd"),
        testReport: .passedLocalFile
    )
    #expect(setup.state == .pinned)
    #expect(setup.drainEvents().isEmpty)
    _ = try setup.enable(sink: LocalFileSinkStub())
    #expect(setup.drainEvents() == [.destinationEnabled])
}

private struct LocalFileSinkStub: DestinationSink {
    func send(fileHandle: String, idempotencyKey: BatchID) async throws -> DeliveryReceipt {
        DeliveryReceipt(batchID: idempotencyKey, accepted: 0, statusOnly: true)
    }
}
