import CoreDomain
import CorrectnessEngine
import EnginePorts
import Foundation
import MetricCatalog
import MQTTCodec
import NetEgress
import SinkMQTT
import TestSupport
import Testing
import WireFormat

private func mosquittoURL() -> String? {
    ProcessInfo.processInfo.environment["OHE_MQTT_BROKER"]
}

@Test(.enabled(if: mosquittoURL() != nil))
func mosquittoQoS1PublishesAndAwaitsPuback() async throws {
    let url = try #require(mosquittoURL())
    let host = URL(string: url)?.host ?? "127.0.0.1"
    let (file, batchID) = try writeMQTTPayload()
    let destination = try MQTTDestination(
        urlString: url,
        allowedHosts: [host],
        allowInsecure: true,
        clientID: "ohe-r90-qos1",
        topic: "ohe/health"
    )
    let sink = try MQTTSink.overNetwork(destination: destination, pin: nil)
    let receipt = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(receipt.accepted == 1)
    #expect(receipt.unconfirmed == 0)
}

@Test(.enabled(if: mosquittoURL() != nil))
func mosquittoQoS0IsUnknownAckOnTheEngine() async throws {
    let url = try #require(mosquittoURL())
    let host = URL(string: url)?.host ?? "127.0.0.1"
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("ffffffff-ffff-ffff-ffff-ffffffffffff")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0xFF]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let mqtt = try MQTTDestination(
        urlString: url,
        allowedHosts: [host],
        allowInsecure: true,
        clientID: "ohe-r90-qos0",
        topic: "ohe/health",
        qos: .atMostOnce
    )
    #expect(!mqtt.confirmsDelivery)
    let sink = try MQTTSink.overNetwork(destination: mqtt, pin: nil)
    let store = MemoryStateStore()
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-mosq-\(UUID().uuidString)")
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
