// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CompanionWire
import CoreDomain
import EnginePorts
import FileWriteKit
import Foundation
import MQTTCodec
import NetEgress
#if canImport(Network)
import Network
#endif
import SinkCompanion
import SinkMQTT
import TestSupport
import Testing
import WireFormat

@Test func endpointUsesSchemeDefaultPorts() throws {
    let mqtts = try StreamEndpoint.parse("mqtts://broker.example/", allowedHosts: ["broker.example"])
    #expect(mqtts.port == 8883)
    #expect(mqtts.usesTLS)
    let https = try StreamEndpoint.parse("https://ha.example/api", allowedHosts: ["ha.example"])
    #expect(https.port == 443)
    let explicit = try StreamEndpoint.parse("mqtts://broker.example:9999", allowedHosts: ["broker.example"])
    #expect(explicit.port == 9999)
    let insecure = try StreamEndpoint.parse(
        "mqtt://broker.example",
        allowedHosts: ["broker.example"],
        allowInsecure: true
    )
    #expect(insecure.port == 1883)
    #expect(!insecure.usesTLS)
}

@Test func endpointRefusesUnapprovedHostsAndSchemes() {
    #expect(throws: EgressError.notAllowlisted("evil.example")) {
        _ = try StreamEndpoint.parse("mqtts://evil.example", allowedHosts: ["broker.example"])
    }
    #expect(throws: EgressError.insecureHTTP) {
        _ = try StreamEndpoint.parse("mqtt://broker.example", allowedHosts: ["broker.example"])
    }
    #expect(throws: EgressError.forbiddenScheme("javascript")) {
        _ = try StreamEndpoint.parse("javascript://broker.example", allowedHosts: ["broker.example"])
    }
    #expect(throws: EgressError.credentialsInURL) {
        _ = try StreamEndpoint.parse("mqtts://user:pw@broker.example", allowedHosts: ["broker.example"])
    }
    #expect(throws: StreamError.badPort) {
        _ = try StreamEndpoint.parse("mqtts://broker.example:0", allowedHosts: ["broker.example"])
    }
}

@Test func mqttPublishesThroughTheByteStreamAdapter() async throws {
    let (file, batchID) = try writeStreamPayload(uuid: "00000000-0000-0000-0000-0000000000b1")
    let broker = LoopbackMQTTBroker()
    let destination = try MQTTDestination(
        urlString: "mqtts://broker.example:8883",
        allowedHosts: ["broker.example"],
        clientID: "c1",
        topic: "ohe/health"
    )
    let sink = MQTTSink(
        destination: destination,
        pipe: ByteStreamMQTTPipe(stream: LoopbackByteStream(mqtt: broker))
    )
    let receipt = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(receipt.accepted == 1)
}

@Test func companionTransfersThroughTheByteStreamAdapter() async throws {
    let (file, batchID) = try writeStreamPayload(uuid: "00000000-0000-0000-0000-0000000000b2")
    let broker = LoopbackCompanionBroker()
    let sink = CompanionSink(
        pipe: ByteStreamCompanionPipe(stream: LoopbackByteStream(companion: broker)),
        installationID: "phone",
        chunkSize: 32
    )
    let receipt = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(receipt.accepted == 1)
    #expect(await broker.storedDigest(batchID: batchID.rawValue) != nil)
}

@Test func bonjourServiceRejectsAnythingButThePairedCompanionType() throws {
    let service = try BonjourService(name: "Colin's Mac")
    #expect(service.type == "_ohx-recv._tcp")
    #expect(service.domain == "local.")
    #expect(throws: StreamError.badServiceName) {
        _ = try BonjourService(name: "")
    }
    #expect(throws: StreamError.badServiceName) {
        _ = try BonjourService(name: String(repeating: "a", count: 64))
    }
    #expect(throws: StreamError.badServiceName) {
        _ = try BonjourService(name: "Colin's Mac", type: "_http._tcp")
    }
}

@Test func discoveryOnlyMatchesTheExactPairedName() {
    let advertised = ["Colin's Mac", "colin's mac", "Colin's Mac (2)", "Attacker"]
    #expect(BonjourService.match(candidates: advertised, pairedName: "Colin's Mac") == "Colin's Mac")
    #expect(BonjourService.match(candidates: advertised, pairedName: "Colin's MacBook") == nil)
    #expect(BonjourService.match(candidates: [], pairedName: "Colin's Mac") == nil)
    #expect(BonjourService.match(candidates: ["colin's mac"], pairedName: "Colin's Mac") == nil)
}

@Test func pairingSecretBridgesToHandshakeMaterialWithoutLeaking() throws {
    let bytes = (0..<32).map { UInt8($0) }
    let secret = try PairingSecret(bytes: bytes)
    let psk = try CompanionPSK.preSharedKey(from: secret, identity: "phone-1A7B")
    #expect(psk.key == bytes)
    #expect(psk.identity == Array("phone-1A7B".utf8))
    #expect(String(describing: psk) == "PreSharedKey(redacted)")
    #expect(String(reflecting: psk) == "PreSharedKey(redacted)")
}

@Test func preSharedKeyRejectsEmptyMaterial() throws {
    let psk = try PreSharedKey(key: Array(repeating: 7, count: 32), identity: Array("phone".utf8))
    #expect(psk.key.count == 32)
    #expect(throws: StreamError.badPreSharedKey) {
        _ = try PreSharedKey(key: [], identity: Array("phone".utf8))
    }
    #expect(throws: StreamError.badPreSharedKey) {
        _ = try PreSharedKey(key: Array(repeating: 7, count: 32), identity: [])
    }
}

#if canImport(Network)
@Test func liveStreamToAClosedLoopbackPortFailsWithoutIdentity() async throws {
    let endpoint = try StreamEndpoint.parse(
        "mqtt://127.0.0.1:9",
        allowedHosts: ["127.0.0.1"],
        allowInsecure: true
    )
    let stream = NWByteStream(
        endpoint: endpoint,
        options: NWByteStream.Options(connectTimeout: .seconds(5), failFastOnWaiting: true)
    )
    let failure = await #expect(throws: StreamError.self) {
        try await stream.open()
    }
    // A refusal must arrive as a named transport failure, not as the timeout backstop.
    guard case .transport = failure else {
        Issue.record("expected a transport failure, got \(String(describing: failure))")
        return
    }
    #expect(await stream.identity() == nil)
    await stream.close()
}
#endif

/// R-21 / FIX-A07: the product ships copy that names a revoked Local Network grant and
/// says it is "different from the Mac being asleep or on another network". Nothing could
/// produce that outcome before this: a denial arrived as `serviceNotFound` and rendered
/// the unreachable copy, so the app told the user to wake a Mac that was never asleep.
@Test func transportFaultsNormalizeOntoClosedDestinationOutcomes() {
    #expect(TransportFault.normalize(StreamError.localNetworkDenied) == .localNetworkDenied)
    // The whole point of the case: it must not collapse back into unreachable.
    #expect(TransportFault.normalize(StreamError.localNetworkDenied) != .destinationUnreachable)
    for unreachable: StreamError in [.serviceNotFound, .closedByPeer, .connectTimeout, .readTimeout,
                                     .notOpen, .transport("refused")] {
        #expect(TransportFault.normalize(unreachable) == .destinationUnreachable)
    }
    #expect(TransportFault.normalize(StreamError.badPort) == .internalFault("badPort"))
    // A trust event and a SEC-15 stop are worse than unreachable and own their own paths.
    #expect(TransportFault.normalize(StreamError.pinMismatch) == nil)
    #expect(
        TransportFault.normalize(
            StreamError.addressClassViolation(host: "h", address: "1.2.3.4", addressClass: .publicUnicast)
        ) == nil
    )
    // Already-closed errors pass through rather than being swallowed.
    #expect(TransportFault.normalize(DestinationSendError.deviceLocked) == .deviceLocked)
    #expect(TransportFault.normalize(EgressError.transport("offline")) == .destinationUnreachable)
    #expect(TransportFault.normalize(EgressError.httpRetryAfter(status: 503, seconds: 10)) == nil)
    #expect(TransportFault.normalize(EgressError.httpStatus(503)) == nil)
    #expect(TransportFault.normalize(EgressError.httpStatus(401)) == nil)
    #expect(TransportFault.normalize(EgressError.pinMismatch) == nil)
    #expect(TransportFault.normalize(URLError(.cannotConnectToHost)) == .destinationUnreachable)
    #expect(TransportFault.normalize(URLError(.cancelled)) == nil)
}

/// `DeliveryExecutor` classifies `DestinationSendError` and nothing else, treating the
/// remainder as transient. An un-normalized denial would therefore be retried forever
/// against a permission that only the user can change in Settings.
@Test func companionPipeSurfacesLocalNetworkDenialRatherThanRetryingIt() async {
    let pipe = ByteStreamCompanionPipe(stream: RefusingByteStream(failure: .localNetworkDenied))
    await #expect(throws: DestinationSendError.localNetworkDenied) {
        try await pipe.send(Data([0x01]))
    }
    await #expect(throws: DestinationSendError.localNetworkDenied) {
        _ = try await pipe.receive(max: 16)
    }
    // The outcome the journal records has to be the distinct one, not the generic one.
    #expect(DestinationSendError.localNetworkDenied.errorClass == .localNetworkDenied)
}

/// A Mac that is genuinely absent must keep reporting absence. If both sides of the
/// distinction do not hold, the honesty claim is worth nothing.
@Test func anAbsentCompanionStillReportsUnreachable() async {
    let pipe = ByteStreamCompanionPipe(stream: RefusingByteStream(failure: .serviceNotFound))
    await #expect(throws: DestinationSendError.destinationUnreachable) {
        try await pipe.send(Data([0x01]))
    }
}

/// MQTT rides the same socket as the companion. Leaving this adapter raw made the exact
/// same transport failure closed for one destination and generic-transient for another.
@Test func mqttPipeNormalizesTheSharedTransportFailures() async {
    let pipe = ByteStreamMQTTPipe(stream: RefusingByteStream(failure: .connectTimeout))
    await #expect(throws: DestinationSendError.destinationUnreachable) {
        try await pipe.send(Data([0x10]))
    }
    await #expect(throws: DestinationSendError.destinationUnreachable) {
        _ = try await pipe.receive(max: 16)
    }
}

/// mDNS answers a browse under a denied grant with a policy error, not an empty result
/// set. Pinning the codes so a neighbouring DNS failure is not read as a denial.
@Test func onlyThePolicyDNSCodesCountAsDenial() {
    #expect(LocalNetworkDenial.isDenial(dnsCode: -65570)) // kDNSServiceErr_PolicyDenied
    #expect(LocalNetworkDenial.isDenial(dnsCode: -65571)) // kDNSServiceErr_NotPermitted
    #expect(!LocalNetworkDenial.isDenial(dnsCode: -65568)) // Timeout
    #expect(!LocalNetworkDenial.isDenial(dnsCode: -65538)) // NoSuchName
    #expect(!LocalNetworkDenial.isDenial(dnsCode: 0))
}

#if canImport(Network)
/// `EPERM` is a Local Network verdict only on a dial that needed the grant. Reading it as
/// one on public unicast would invent a permission problem out of an unrelated refusal.
@Test func permissionErrorsCountAsDenialOnlyOnLocalDials() {
    #expect(LocalNetworkDenial.isDenial(NWError.posix(.EPERM), needsLocalGrant: true))
    #expect(!LocalNetworkDenial.isDenial(NWError.posix(.EPERM), needsLocalGrant: false))
    #expect(!LocalNetworkDenial.isDenial(NWError.posix(.ECONNREFUSED), needsLocalGrant: true))
    // Browsing always needs the grant, so a policy code stands on its own.
    #expect(LocalNetworkDenial.isDenial(NWError.dns(-65570), needsLocalGrant: false))
}
#endif

private struct RefusingByteStream: ByteStream {
    let failure: StreamError

    func open() async throws { throw failure }
    func send(_ data: Data) async throws { throw failure }
    func receive(max: Int) async throws -> Data { throw failure }
    func close() async {}
    func identity() async -> TLSIdentity? { nil }
}

private func writeStreamPayload(uuid: String) throws -> (URL, BatchID) {
    let batchID = BatchID(rawValue: "0192f3c1-0000-0000-0000-0000000000b0")
    let data = try NativeWire.encode(
        samples: [heartSample(uuid)],
        tombstones: [],
        metric: MetricID(rawValue: "heartRate"),
        batchID: batchID,
        envelope: testEnvelope()
    )
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-stream-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("batch.ndjson")
    try FileWriteKit.writeAtomically(data, to: file)
    return (file, batchID)
}

/// SEC-30 / T-16: asserting the flag reads back, not just that the call was made. A
/// resource value that fails quietly would leave queued health payloads in every
/// iCloud and Finder backup while the code above looks correct.
@Test func backupExclusionIsSetOnTheDirectoryAndReadsBack() throws {
    #if canImport(Darwin)
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-backup-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let before = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(before.isExcludedFromBackup != true)

    try FileWriteKit.excludeFromBackup(directory)

    let after = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(after.isExcludedFromBackup == true)
    #endif
}
