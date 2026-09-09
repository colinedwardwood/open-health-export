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

private func mosquittoExecutable() -> String? {
    let extras = [
        "/opt/homebrew/sbin/mosquitto",
        "/usr/local/sbin/mosquitto",
        "/usr/sbin/mosquitto",
    ]
    if let found = extras.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
        return found
    }
    for dir in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
        let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent("mosquitto").path
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
}

@Test(.enabled(if: mosquittoExecutable() != nil))
func mosquittoQoS1SurvivesBrokerRestart() async throws {
    let binary = try #require(mosquittoExecutable())
    let port = UInt16(18_830 + (ProcessInfo.processInfo.processIdentifier % 1_000))
    let work = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-mosq-restart-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: work) }
    let conf = work.appendingPathComponent("mosquitto.conf")
    try """
    listener \(port)
    protocol mqtt
    allow_anonymous true
    persistence false
    log_type error
    """.write(to: conf, atomically: true, encoding: .utf8)

    func startBroker() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["-c", conf.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    func waitUntilListening() async throws {
        for _ in 0 ..< 50 {
            let stream = POSIXByteStream(
                endpoint: try StreamEndpoint(host: "127.0.0.1", port: port, usesTLS: false)
            )
            do {
                try await stream.open()
                await stream.close()
                return
            } catch {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        throw MQTTError.truncated
    }

    var broker = try startBroker()
    defer {
        if broker.isRunning { broker.terminate() }
    }
    try await waitUntilListening()

    let url = "mqtt://127.0.0.1:\(port)"
    let (file, batchID) = try writeMQTTPayload()
    func publishOnce(clientID: String) async throws {
        let destination = try MQTTDestination(
            urlString: url,
            allowedHosts: ["127.0.0.1"],
            allowInsecure: true,
            clientID: clientID,
            topic: "ohe/health"
        )
        let sink = try MQTTSink.overNetwork(destination: destination, pin: nil)
        let receipt = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
        #expect(receipt.accepted == 1)
        #expect(receipt.unconfirmed == 0)
    }

    try await publishOnce(clientID: "ohe-r90-restart-1")
    broker.terminate()
    broker.waitUntilExit()
    broker = try startBroker()
    try await waitUntilListening()
    try await publishOnce(clientID: "ohe-r90-restart-2")
}
