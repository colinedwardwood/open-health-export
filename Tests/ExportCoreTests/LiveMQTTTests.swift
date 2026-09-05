#if canImport(Network)
import CoreDomain
import EnginePorts
import FileWriteKit
import Foundation
import MQTTCodec
import NetEgress
import SinkMQTT
import Testing
import WireFormat

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
#endif
