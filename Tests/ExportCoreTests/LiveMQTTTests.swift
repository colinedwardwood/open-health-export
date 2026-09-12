// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(Network)
import CoreDomain
import DestinationTrust
import EnginePorts
import FileWriteKit
import Foundation
import MQTTCodec
import NetEgress
import SinkMQTT
import Testing
import WireFormat

@Suite(.serialized)
struct LiveMQTTTests {
@Test func mqttPublishesOverLoopbackTCP() async throws {
    let broker = try LocalMQTTBroker()
    let port = try await broker.start()
    let (file, batchID) = try writeMQTTPayload()
    let destination = try MQTTDestination(
        urlString: "mqtt://127.0.0.1:\(port)",
        allowedHosts: ["127.0.0.1"],
        allowInsecure: true,
        clientID: "c1",
        topic: "ohe/health"
    )
    let stream = NWByteStream(
        endpoint: try StreamEndpoint.parse(
            "mqtt://127.0.0.1:\(port)",
            allowedHosts: ["127.0.0.1"],
            allowInsecure: true
        ),
        options: NWByteStream.Options(failFastOnWaiting: true)
    )
    let sink = MQTTSink(destination: destination, pipe: ByteStreamMQTTPipe(stream: stream))
    let receipt = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(receipt.accepted == 1)
    await broker.stop()
}

@Test func mqttsPublishesOverPinnedLoopbackTLS() async throws {
    let material = try LoopbackTLS.material()
    let broker = try LocalMQTTBroker(parameters: LocalMQTTBroker.tlsParameters(identity: material.identity))
    let port = try await broker.start()
    let (file, batchID) = try writeMQTTPayload()
    let destination = try MQTTDestination(
        urlString: "mqtts://127.0.0.1:\(port)",
        allowedHosts: ["127.0.0.1"],
        clientID: "c1",
        topic: "ohe/health"
    )
    let sink = try MQTTSink.overNetwork(destination: destination, pin: material.pin)
    let receipt = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(receipt.accepted == 1)
    await broker.stop()
}

@Test func mqttsWrongPinFailsBeforePUBLISH() async throws {
    let material = try LoopbackTLS.material()
    let broker = try LocalMQTTBroker(parameters: LocalMQTTBroker.tlsParameters(identity: material.identity))
    let port = try await broker.start()
    let destination = try MQTTDestination(
        urlString: "mqtts://127.0.0.1:\(port)",
        allowedHosts: ["127.0.0.1"],
        clientID: "c1",
        topic: "ohe/health"
    )
    let wrong = PinRecord(
        leafSPKISha256: String(repeating: "ab", count: 32),
        issuerSPKISha256: String(repeating: "cd", count: 32),
        firstSeen: "2024-01-01T00:00:00Z",
        policy: .leaf
    )
    let sink = try MQTTSink.overNetwork(destination: destination, pin: wrong)
    let (file, batchID) = try writeMQTTPayload()
    await #expect(throws: StreamError.pinMismatch) {
        _ = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    }
    await broker.stop()
}

@Test func mqttsFirstUseAcceptsSelfSignedBrokerAndEnableRecordsThePin() async throws {
    let material = try LoopbackTLS.material()
    let broker = try LocalMQTTBroker(parameters: LocalMQTTBroker.tlsParameters(identity: material.identity))
    let port = try await broker.start()
    let destination = try MQTTDestination(
        urlString: "mqtts://127.0.0.1:\(port)",
        allowedHosts: ["127.0.0.1"],
        clientID: "c1",
        topic: "ohe/health"
    )
    let stream = NWByteStream(
        endpoint: try StreamEndpoint.parse(
            "mqtts://127.0.0.1:\(port)",
            allowedHosts: ["127.0.0.1"]
        ),
        options: NWByteStream.Options(failFastOnWaiting: true)
    )
    let completed = try await MQTTDestinationEnable.complete(
        destination: destination,
        pipe: ByteStreamMQTTPipe(stream: stream),
        exporterID: "00000000-0000-4000-8000-000000000090",
        emittedAt: "2026-01-01T00:00:00Z"
    )
    #expect(completed.identity?.leafSPKISha256 == material.pin.leafSPKISha256)
    #expect(completed.identity?.notBefore.hasSuffix("Z") == true)
    #expect(completed.identity?.notAfter.hasSuffix("Z") == true)
    #expect(completed.identity?.notBefore.isEmpty == false)
    #expect(completed.identity?.notAfter.isEmpty == false)
    #expect(completed.report.allowsEnablement)
    #expect(
        completed.events.contains {
            if case .pinRecorded = $0 { return true }
            return false
        }
    )
    await broker.stop()
}
}
#endif
