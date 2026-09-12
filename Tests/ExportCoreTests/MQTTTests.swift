// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CorrectnessEngine
import DestinationTrust
import EnginePorts
import FileWriteKit
import Foundation
import MetricCatalog
import MQTTCodec
import NetEgress
import SinkMQTT
import TestSupport
import Testing
import WireFormat

@Test func mqttRemainingLengthRoundTrips() throws {
    for value in [0, 127, 128, 16383, 2097151] {
        let encoded = try MQTTRemainingLength.encode(value)
        let decoded = try MQTTRemainingLength.decode(Data(encoded), start: 0)
        #expect(decoded.value == value)
        #expect(decoded.consumed == encoded.count)
    }
}

@Test func mqttConnectIs311CleanSession() throws {
    let packet = try MQTTCodec.connect(clientID: "c1")
    let bytes = [UInt8](packet)
    #expect(bytes == [
        0x10, 0x0E,
        0x00, 0x04, 0x4D, 0x51, 0x54, 0x54,
        0x04, 0x02, 0x00, 0x3C,
        0x00, 0x02, 0x63, 0x31,
    ])
    #expect(MQTTPacketKind(rawValue: 8) == nil)
}

@Test func mqttQoS2ConfigurationIsExplicitlyRejected() throws {
    #expect(try MQTTQoS(configurationValue: 0) == .atMostOnce)
    #expect(try MQTTQoS(configurationValue: 1) == .atLeastOnce)
    #expect(throws: MQTTError.qos2Unsupported) {
        _ = try MQTTQoS(configurationValue: 2)
    }
    #expect(throws: MQTTError.unsupportedQoS(3)) {
        _ = try MQTTQoS(configurationValue: 3)
    }
}

@Test func mqttLastWillIsRejectedAndAbsentFromLoopbackConnect() async throws {
    #expect(throws: MQTTError.lastWillUnsupported) {
        _ = try MQTTDestination(
            urlString: "mqtt://broker.example:1883",
            allowedHosts: ["broker.example"],
            allowInsecure: true,
            clientID: "c1",
            topic: "ohe/health",
            lastWillEnabled: true
        )
    }

    let broker = LoopbackMQTTBroker()
    let destination = try MQTTDestination(
        urlString: "mqtt://broker.example:1883",
        allowedHosts: ["broker.example"],
        allowInsecure: true,
        clientID: "c1",
        topic: "ohe/health"
    )
    let session = MQTTSession(pipe: broker)
    try await session.connect(destination: destination)
    let flags = try #require(await broker.lastConnectFlags)
    #expect(flags & 0b0011_1100 == 0) // Will Flag, Will QoS and Will Retain.
    #expect(flags & 0b0000_0010 != 0) // CleanSession remains required by ADR-0003.
}

@Test func mqttPersistentSessionIsRejectedBeforeConnect() throws {
    #expect(throws: MQTTError.persistentSessionUnsupported) {
        _ = try MQTTDestination(
            urlString: "mqtt://broker.example:1883",
            allowedHosts: ["broker.example"],
            allowInsecure: true,
            clientID: "c1",
            topic: "ohe/health",
            cleanSessionEnabled: false
        )
    }
}

@Test func mqttErrorsNameTheFailureWithoutBrokerSecrets() throws {
    let errors: [MQTTError] = [
        .remainingLength,
        .truncated,
        .badUTF8,
        .badTopic,
        .connack(5),
        .unexpectedPacket(8),
        .packetID,
        .retainForbidden,
        .qos2Unsupported,
        .unsupportedQoS(3),
        .lastWillUnsupported,
        .persistentSessionUnsupported,
    ]
    for error in errors {
        let text = try #require(error.errorDescription)
        #expect(!text.isEmpty)
        #expect(!text.contains("broker.example"))
        #expect(!text.contains("password"))
        #expect(!text.contains("nas.example"))
    }
    #expect(
        MQTTError.qos2Unsupported.errorDescription?
            .contains("QoS 2 is not supported") == true
    )
    #expect(
        MQTTError.lastWillUnsupported.errorDescription?
            .contains("stopped before connecting") == true
    )
    #expect(
        MQTTError.persistentSessionUnsupported.errorDescription?
            .contains("persistent sessions are not supported") == true
    )
}

@Test func mqttDataPublishNeverSetsRetain() throws {
    let off = try MQTTCodec.publish(
        topic: "ohe/health",
        payload: Data("x".utf8),
        qos: .atLeastOnce,
        packetID: 1,
        retain: false
    )
    let decodedOff = try MQTTCodec.decode(off)
    #expect(decodedOff.flags & 0b0000_0001 == 0)
    let on = try MQTTCodec.publish(
        topic: "ohe/health",
        payload: Data("x".utf8),
        qos: .atLeastOnce,
        packetID: 1,
        retain: true
    )
    let decodedOn = try MQTTCodec.decode(on)
    #expect(decodedOn.flags & 0b0000_0001 == 1)
}

@Test func mqttSessionRefusesRetainOnTheDataPath() async {
    let broker = LoopbackMQTTBroker()
    let session = MQTTSession(pipe: broker)
    await #expect(throws: MQTTError.retainForbidden) {
        try await session.publish(
            topic: "ohe/health",
            payload: Data(),
            qos: .atMostOnce,
            retain: true
        )
    }
}

@Test func mqttSessionAllowsRetainOnlyForDiscoveryAndStatus() async throws {
    let broker = LoopbackMQTTBroker()
    let session = MQTTSession(pipe: broker)
    let topic = try HADiscovery.deviceConfigTopic(exporterId: "phone-1A7B")
    let config = try HADiscovery.encodeDeviceConfig(
        exporterId: "phone-1A7B",
        metrics: [MetricCatalog.heartRate.id, MetricCatalog.stepCount.id]
    )
    try await session.publish(topic: topic, payload: config, qos: .atMostOnce, retain: true)
    try await session.publish(
        topic: try HADiscovery.statusTopic(exporterId: "phone-1A7B"),
        payload: HADiscovery.statusPayload(),
        qos: .atMostOnce,
        retain: true
    )
    try await session.publish(topic: topic, payload: Data(), qos: .atMostOnce, retain: true)
    await #expect(throws: MQTTError.retainForbidden) {
        try await session.publish(
            topic: topic,
            payload: Data("{\"qty\":1}".utf8),
            qos: .atMostOnce,
            retain: true
        )
    }
}

@Test func mqttRejectsWildcardTopicAndSubscribeKind() throws {
    #expect(throws: MQTTError.badTopic) {
        _ = try MQTTCodec.publish(topic: "health/#", payload: Data(), qos: .atLeastOnce, packetID: 1)
    }
    let subscribe = Data([0x82, 0x00])
    #expect(throws: MQTTError.unexpectedPacket(8)) {
        _ = try MQTTCodec.decode(subscribe)
    }
}

@Test func mqttsHostMustBeAllowlisted() {
    #expect(throws: EgressError.notAllowlisted("evil.example")) {
        _ = try MQTTDestination(
            urlString: "mqtts://evil.example:8883",
            allowedHosts: ["broker.example"],
            clientID: "c1",
            topic: "ohe/health"
        )
    }
    #expect(throws: EgressError.insecureHTTP) {
        _ = try MQTTDestination(
            urlString: "mqtt://broker.example:1883",
            allowedHosts: ["broker.example"],
            clientID: "c1",
            topic: "ohe/health"
        )
    }
}

@Test func mqttQoS1PublishesAndAwaitsPuback() async throws {
    let (file, batchID) = try writeMQTTPayload()
    let broker = LoopbackMQTTBroker()
    let destination = try MQTTDestination(
        urlString: "mqtts://broker.example:8883",
        allowedHosts: ["broker.example"],
        clientID: "c1",
        topic: "ohe/health"
    )
    let sink = MQTTSink(destination: destination, pipe: broker)
    let receipt = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(receipt.accepted == 1)
    #expect(receipt.unconfirmed == 0)
}

@Test func mqttQoS0IsUnknownAckOnTheEngine() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("ffffffff-ffff-ffff-ffff-ffffffffffff")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0xFF]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let broker = LoopbackMQTTBroker()
    let mqtt = try MQTTDestination(
        urlString: "mqtts://broker.example:8883",
        allowedHosts: ["broker.example"],
        clientID: "c1",
        topic: "ohe/health",
        qos: .atMostOnce
    )
    #expect(!mqtt.confirmsDelivery)
    #expect(DestinationTest.mqttVerdict(confirmsDelivery: mqtt.confirmsDelivery) == .sentUnconfirmed)
    let sink = MQTTSink(destination: mqtt, pipe: broker)
    let store = MemoryStateStore()
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-mqtt-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    let run = ExportRun(
        source: FixtureSource(pages: [page]),
        destination: .testing(sink),
        store: store,
        metric: metric,
        scratchDirectory: scratch,
        destinationName: "mqtt",
        envelope: testEnvelope()
    )
    let outcome = try await run.run()
    #expect(outcome.kind == .unknownAck)
}

@Test func mqttDestinationEnableCompletesOverLoopback() async throws {
    let broker = LoopbackMQTTBroker()
    let destination = try MQTTDestination(
        urlString: "mqtt://broker.example:1883",
        allowedHosts: ["broker.example"],
        allowInsecure: true,
        clientID: "c1",
        topic: "ohe/health"
    )
    let completed = try await MQTTDestinationEnable.complete(
        destination: destination,
        pipe: broker,
        exporterID: "00000000-0000-4000-8000-000000000090",
        emittedAt: "2026-01-01T00:00:00Z"
    )
    #expect(completed.report.verdict == .passed)
    #expect(completed.report.allowsEnablement)
    #expect(completed.report.steps.map(\.name) == [.connect, .publishCanary, .receiveEcho])
    #expect(completed.events.contains(.destinationEnabled))
    let probed = try await MQTTDestinationEnable.probe(
        destination: destination,
        pipe: LoopbackMQTTBroker(),
        exporterID: "00000000-0000-4000-8000-000000000090",
        emittedAt: "2026-01-01T00:00:00Z"
    )
    #expect(!probed.pendingEvents.contains(.destinationEnabled))
    let preview = String(decoding: completed.preview, as: UTF8.self)
    #expect(preview.contains("\"kind\":\"canary\""))
    #expect(preview.contains("\"code\":\"OHE1-MQTT\""))
    #expect(!preview.contains("\"kind\":\"sample."))
}

@Test func mqttQoS0EnablementIsSentUnconfirmed() async throws {
    let broker = LoopbackMQTTBroker()
    let destination = try MQTTDestination(
        urlString: "mqtt://broker.example:1883",
        allowedHosts: ["broker.example"],
        allowInsecure: true,
        clientID: "c1",
        topic: "ohe/health",
        qos: .atMostOnce
    )
    let completed = try await MQTTDestinationEnable.complete(
        destination: destination,
        pipe: broker,
        exporterID: "00000000-0000-4000-8000-000000000090",
        emittedAt: "2026-01-01T00:00:00Z"
    )
    #expect(completed.report.verdict == .sentUnconfirmed)
    #expect(completed.report.allowsEnablement)
}

@Test func mqttTopicAllows256BytesAndRejectsOverUInt16() throws {
    let topic256 = String(repeating: "a", count: 256)
    try MQTTTopic.validate(topic256)
    let packet = try MQTTCodec.publish(
        topic: topic256,
        payload: Data("x".utf8),
        qos: .atLeastOnce,
        packetID: 1
    )
    #expect(!packet.isEmpty)
    #expect(throws: MQTTError.badTopic) {
        try MQTTTopic.validate(String(repeating: "b", count: MQTTTopic.maximumUTF8Count + 1))
    }
    try MQTTTopic.validate(String(repeating: "c", count: MQTTTopic.maximumUTF8Count))
}

@Test func mqttTopicTemplateRendersExporterAndBatchAndRejectsWildcards() async throws {
    #expect(try MQTTTopicTemplate.render("ohe/health", values: [:]) == "ohe/health")
    #expect(
        try MQTTTopicTemplate.render(
            "ohe/{{exporterId|raw}}/{{batchId|raw}}",
            values: ["exporterId": "phone-1", "batchId": "b1"]
        ) == "ohe/phone-1/b1"
    )
    #expect(throws: MQTTError.badTopic) {
        try MQTTTopicTemplate.render("ohe/{{exporterId|raw}}/#", values: ["exporterId": "phone-1"])
    }
    let (file, batchID) = try writeMQTTPayload()
    let broker = LoopbackMQTTBroker()
    let destination = try MQTTDestination(
        urlString: "mqtts://broker.example:8883",
        allowedHosts: ["broker.example"],
        clientID: "c1",
        topic: "ohe/{{exporterId|raw}}/health",
        exporterID: "phone-1A7B"
    )
    let sink = MQTTSink(destination: destination, pipe: broker)
    _ = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(await broker.lastPublishTopic == "ohe/phone-1A7B/health")
}

func writeMQTTPayload() throws -> (URL, BatchID) {
    let sample = heartSample("00000000-0000-0000-0000-000000000001")
    let batchID = BatchID(rawValue: "0192f3c1-0000-0000-0000-00000000000a")
    let data = try NativeWire.encode(
        samples: [sample],
        tombstones: [],
        metric: MetricID(rawValue: "heartRate"),
        batchID: batchID,
        envelope: testEnvelope()
    )
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-mqtt-payload-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("batch.ndjson")
    try FileWriteKit.writeAtomically(data, to: file)
    return (file, batchID)
}
