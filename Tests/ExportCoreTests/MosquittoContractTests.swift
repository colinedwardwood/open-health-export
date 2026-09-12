// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

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

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private func mosquittoURL() -> String? {
    ProcessInfo.processInfo.environment["OHE_MQTT_BROKER"]
}

@Suite
struct MosquittoExternalBrokerTests {
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

@Test(.enabled(if: mosquittoURL() != nil))
func mosquittoContractRejectsExcludedQoS2AndLastWillBeforeDial() throws {
    let url = try #require(mosquittoURL())
    let host = URL(string: url)?.host ?? "127.0.0.1"
    #expect(throws: MQTTError.qos2Unsupported) {
        _ = try MQTTQoS(configurationValue: 2)
    }
    #expect(throws: MQTTError.lastWillUnsupported) {
        _ = try MQTTDestination(
            urlString: url,
            allowedHosts: [host],
            allowInsecure: true,
            clientID: "ohe-r90-no-will",
            topic: "ohe/health",
            lastWillEnabled: true
        )
    }
}
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

private func mosquittoSubExecutable() -> String? {
    let extras = [
        "/opt/homebrew/bin/mosquitto_sub",
        "/usr/local/bin/mosquitto_sub",
        "/usr/bin/mosquitto_sub",
    ]
    if let found = extras.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
        return found
    }
    for dir in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
        let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent("mosquitto_sub").path
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
}

private func mosquittoPasswdExecutable() -> String? {
    let extras = [
        "/opt/homebrew/bin/mosquitto_passwd",
        "/usr/local/bin/mosquitto_passwd",
        "/usr/bin/mosquitto_passwd",
    ]
    if let found = extras.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
        return found
    }
    for dir in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
        let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent("mosquitto_passwd").path
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
}

@Suite(.serialized)
struct MosquittoSubprocessTests {
@Test(
    .enabled(
        if: mosquittoExecutable() != nil && mosquittoPasswdExecutable() != nil
    )
)
func mosquittoQoS1RequiresUsernameAndPassword() async throws {
    let binary = try #require(mosquittoExecutable())
    let passwd = try #require(mosquittoPasswdExecutable())
    let port = UInt16(21_830 + (ProcessInfo.processInfo.processIdentifier % 1_000))
    let work = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-mosq-auth-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: work) }
    let pwfile = work.appendingPathComponent("passwd")
    let makeUser = Process()
    makeUser.executableURL = URL(fileURLWithPath: passwd)
    makeUser.arguments = ["-c", "-b", pwfile.path, "exporter", "secret"]
    makeUser.standardOutput = FileHandle.nullDevice
    makeUser.standardError = FileHandle.nullDevice
    try makeUser.run()
    makeUser.waitUntilExit()
    guard makeUser.terminationStatus == 0 else { throw MQTTError.truncated }
    let conf = work.appendingPathComponent("mosquitto.conf")
    try """
    listener \(port)
    protocol mqtt
    allow_anonymous false
    password_file \(pwfile.path)
    persistence false
    log_type error
    """.write(to: conf, atomically: true, encoding: .utf8)
    let broker = try startMosquitto(binary: binary, conf: conf)
    defer { if broker.isRunning { broker.terminate() } }
    try await waitForMosquitto(port: port)

    let (file, batchID) = try writeMQTTPayload()
    let anonymous = try MQTTDestination(
        urlString: "mqtt://127.0.0.1:\(port)",
        allowedHosts: ["127.0.0.1"],
        allowInsecure: true,
        clientID: "ohe-r90-auth-anon",
        topic: "ohe/health"
    )
    let rejected = try MQTTSink.overNetwork(destination: anonymous, pin: nil)
    await #expect(throws: MQTTError.connack(5)) {
        _ = try await rejected.send(fileHandle: file.path, idempotencyKey: batchID)
    }

    let destination = try MQTTDestination(
        urlString: "mqtt://127.0.0.1:\(port)",
        allowedHosts: ["127.0.0.1"],
        allowInsecure: true,
        clientID: "ohe-r90-auth-ok",
        topic: "ohe/health",
        username: "exporter",
        password: "secret"
    )
    let sink = try MQTTSink.overNetwork(destination: destination, pin: nil)
    let receipt = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(receipt.accepted == 1)
}

@Test(
    .enabled(
        if: mosquittoExecutable() != nil && mosquittoSubExecutable() != nil
    )
)
func mosquittoBrokerKeepsNoRetainedHealthPayload() async throws {
    let binary = try #require(mosquittoExecutable())
    let subscriber = try #require(mosquittoSubExecutable())
    let port = UInt16(23_830 + (ProcessInfo.processInfo.processIdentifier % 1_000))
    let work = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-mosq-retain-\(UUID().uuidString)")
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
    let broker = try startMosquitto(binary: binary, conf: conf)
    defer { if broker.isRunning { broker.terminate() } }
    try await waitForMosquitto(port: port)

    let (file, batchID) = try writeMQTTPayload()
    let healthTopic = "ohe/health"
    let destination = try MQTTDestination(
        urlString: "mqtt://127.0.0.1:\(port)",
        allowedHosts: ["127.0.0.1"],
        allowInsecure: true,
        clientID: "ohe-r90-retain-health",
        topic: healthTopic
    )
    let sink = try MQTTSink.overNetwork(destination: destination, pin: nil)
    let receipt = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(receipt.accepted == 1)
    let healthRetained = try mosquittoRetainedPayload(
        subscriber: subscriber,
        port: port,
        topic: healthTopic
    )
    #expect(healthRetained.isEmpty)

    let exporterId = "phone-1A7B"
    let discoveryTopic = try HADiscovery.deviceConfigTopic(exporterId: exporterId)
    let discoveryPayload = try HADiscovery.encodeDeviceConfig(
        exporterId: exporterId,
        metrics: [MetricCatalog.heartRate.id]
    )
    let session = MQTTSession(
        pipe: ByteStreamMQTTPipe(
            stream: POSIXByteStream(
                endpoint: try StreamEndpoint(host: "127.0.0.1", port: port, usesTLS: false)
            )
        )
    )
    try await session.connect(
        destination: try MQTTDestination(
            urlString: "mqtt://127.0.0.1:\(port)",
            allowedHosts: ["127.0.0.1"],
            allowInsecure: true,
            clientID: "ohe-r90-retain-discovery",
            topic: healthTopic
        )
    )
    try await session.publish(
        topic: discoveryTopic,
        payload: discoveryPayload,
        qos: .atMostOnce,
        retain: true
    )
    try await session.disconnect()
    let discoveryRetained = try mosquittoRetainedPayload(
        subscriber: subscriber,
        port: port,
        topic: discoveryTopic
    )
    #expect(discoveryRetained == discoveryPayload)
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
    await stopMosquitto(broker)
    broker = try startBroker()
    try await waitUntilListening()
    try await publishOnce(clientID: "ohe-r90-restart-2")
}
}

#if canImport(Network)
/// Serialized with the other broker-spawning tests: each case binds a listener and
/// imports PKCS#12 material, and running them alongside the rest of the suite
/// leaves brokers and TLS imports contending until the run stops making progress.
@Suite(.serialized)
struct MosquittoTLSSubprocessTests {
@Test(.enabled(if: mosquittoExecutable() != nil))
func mosquittoQoS1PublishesOverPinnedTestCATLS() async throws {
    let binary = try #require(mosquittoExecutable())
    let material = try MosquittoTLSMaterial.generate()
    defer { try? FileManager.default.removeItem(at: material.directory) }
    let port = UInt16(19_830 + (ProcessInfo.processInfo.processIdentifier % 1_000))
    let conf = material.directory.appendingPathComponent("tls.conf")
    try """
    listener \(port)
    protocol mqtt
    allow_anonymous true
    persistence false
    log_type error
    cafile \(material.caCert.path)
    certfile \(material.serverCert.path)
    keyfile \(material.serverKey.path)
    require_certificate false
    """.write(to: conf, atomically: true, encoding: .utf8)
    let broker = try startMosquitto(binary: binary, conf: conf)
    defer { if broker.isRunning { broker.terminate() } }
    try await waitForMosquitto(port: port)

    let (file, batchID) = try writeMQTTPayload()
    let destination = try MQTTDestination(
        urlString: "mqtts://127.0.0.1:\(port)",
        allowedHosts: ["127.0.0.1"],
        clientID: "ohe-r90-tls-ca",
        topic: "ohe/health"
    )
    let sink = try MQTTSink.overNetwork(destination: destination, pin: material.pin)
    let receipt = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(receipt.accepted == 1)
    #expect(receipt.unconfirmed == 0)

    let wrong = PinRecord(
        leafSPKISha256: String(repeating: "ab", count: 32),
        issuerSPKISha256: String(repeating: "cd", count: 32),
        firstSeen: "2024-01-01T00:00:00Z",
        policy: .leaf
    )
    let rejected = try MQTTSink.overNetwork(destination: destination, pin: wrong)
    await #expect(throws: StreamError.pinMismatch) {
        _ = try await rejected.send(fileHandle: file.path, idempotencyKey: batchID)
    }
}

@Test(.enabled(if: mosquittoExecutable() != nil))
func mosquittoQoS1RequiresTheCAIssuedClientCertificate() async throws {
    let binary = try #require(mosquittoExecutable())
    let material = try MosquittoTLSMaterial.generate()
    defer { try? FileManager.default.removeItem(at: material.directory) }
    let port = UInt16(20_830 + (ProcessInfo.processInfo.processIdentifier % 1_000))
    let conf = material.directory.appendingPathComponent("mtls.conf")
    try """
    listener \(port)
    protocol mqtt
    allow_anonymous true
    persistence false
    log_type error
    cafile \(material.caCert.path)
    certfile \(material.serverCert.path)
    keyfile \(material.serverKey.path)
    require_certificate true
    """.write(to: conf, atomically: true, encoding: .utf8)
    let broker = try startMosquitto(binary: binary, conf: conf)
    defer { if broker.isRunning { broker.terminate() } }
    try await waitForMosquitto(port: port)

    let (file, batchID) = try writeMQTTPayload()
    let withoutClient = try MQTTDestination(
        urlString: "mqtts://127.0.0.1:\(port)",
        allowedHosts: ["127.0.0.1"],
        clientID: "ohe-r90-mtls-none",
        topic: "ohe/health"
    )
    let missing = try MQTTSink.overNetwork(destination: withoutClient, pin: material.pin)
    await #expect(throws: (any Error).self) {
        _ = try await missing.send(fileHandle: file.path, idempotencyKey: batchID)
    }

    let rogue = try MQTTDestination(
        urlString: "mqtts://127.0.0.1:\(port)",
        allowedHosts: ["127.0.0.1"],
        clientID: "ohe-r90-mtls-rogue",
        topic: "ohe/health",
        clientPKCS12: material.roguePKCS12,
        clientPKCS12Password: "test"
    )
    let rogueSink = try MQTTSink.overNetwork(destination: rogue, pin: material.pin)
    await #expect(throws: (any Error).self) {
        _ = try await rogueSink.send(fileHandle: file.path, idempotencyKey: batchID)
    }

    let destination = try MQTTDestination(
        urlString: "mqtts://127.0.0.1:\(port)",
        allowedHosts: ["127.0.0.1"],
        clientID: "ohe-r90-mtls-ok",
        topic: "ohe/health",
        clientPKCS12: material.clientPKCS12,
        clientPKCS12Password: "test"
    )
    let sink = try MQTTSink.overNetwork(destination: destination, pin: material.pin)
    let receipt = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(receipt.accepted == 1)
}
}
#endif

private func mosquittoRetainedPayload(subscriber: String, port: UInt16, topic: String) throws -> Data {
    let pipe = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: subscriber)
    process.arguments = [
        "-h", "127.0.0.1",
        "-p", "\(port)",
        "-t", topic,
        "-i", "ohe-retain-\(port)-\(abs(topic.hashValue))",
        "--retained-only",
        "-C", "1",
        "-W", "2",
    ]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    if data.last == 0x0A {
        return data.dropLast()
    }
    return data
}

private func startMosquitto(binary: String, conf: URL) throws -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = ["-c", conf.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    return process
}

private func stopMosquitto(_ process: Process) async {
    guard process.isRunning else { return }
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            #if canImport(Darwin)
            // waitUntilExit() has no deadline, so a broker that does not act on
            // SIGTERM parks the whole run rather than failing one test. Escalate
            // on the same bounded schedule the Glibc branch uses.
            process.terminate()
            for _ in 0 ..< 100 {
                if !process.isRunning { break }
                Darwin.usleep(20_000)
            }
            if process.isRunning {
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
            #else
            let pid = process.processIdentifier
            _ = Glibc.kill(pid, SIGTERM)
            var status: Int32 = 0
            for _ in 0 ..< 100 {
                let result = Glibc.waitpid(pid, &status, WNOHANG)
                if result == pid || (result < 0 && errno == ECHILD) {
                    continuation.resume()
                    return
                }
                Glibc.usleep(20_000)
            }
            _ = Glibc.kill(pid, SIGKILL)
            #endif
            continuation.resume()
        }
    }
}

private func waitForMosquitto(port: UInt16) async throws {
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
