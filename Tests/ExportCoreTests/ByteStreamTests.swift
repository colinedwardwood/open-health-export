// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CompanionWire
import CoreDomain
import EnginePorts
import FileWriteKit
import Foundation
import MQTTCodec
import NetEgress
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
