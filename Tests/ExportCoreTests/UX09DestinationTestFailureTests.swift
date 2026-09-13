// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CompanionWire
import DestinationTrust
import FileWriteKit
import Foundation
import MetricCatalog
import NetEgress
import SinkCompanion
import SinkHTTP
import SinkLocalFile
import SinkMQTT
import TestSupport
import Testing

/// UX-09: fifteen induced faults must name the failing step, not a generic timeout.
@Test func ux09InducedFailuresNameTheCorrectStep() async throws {
    var named: [(String, DestinationTestStep)] = []

    let missingFolder = try LocalFileDestinationTest.run(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("ohe-ux09-missing-\(UUID().uuidString)")
    )
    named.append(expectFailure(missingFolder, at: .openFolder, id: "local-missing-folder"))

    let writable = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-ux09-write-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: writable, withIntermediateDirectories: true)
    let writeFault = try FileWriteKit.$fault.withValue(.abortBeforeRename) {
        try LocalFileDestinationTest.run(directory: writable, canary: Data("canary\n".utf8))
    }
    named.append(expectFailure(writeFault, at: .writeCanary, id: "local-write-fault"))

    let readable = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-ux09-read-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: readable, withIntermediateDirectories: true)
    let canaryFile = readable.appendingPathComponent("ohe-canary.ndjson")
    let readGone = try LocalFileDestinationTest.run(
        directory: readable,
        canary: Data("canary\n".utf8)
    ) { _, _, step in
        if step == .readBack {
            try? FileManager.default.removeItem(at: canaryFile)
        }
    }
    named.append(expectFailure(readGone, at: .readBack, id: "local-read-gone"))

    let confirmDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-ux09-confirm-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: confirmDir, withIntermediateDirectories: true)
    let confirmFile = confirmDir.appendingPathComponent("ohe-canary.ndjson")
    let confirmMismatch = try LocalFileDestinationTest.run(
        directory: confirmDir,
        canary: Data("canary\n".utf8)
    ) { _, _, step in
        if step == .readBack {
            try? Data("tampered\n".utf8).write(to: confirmFile)
        }
    }
    named.append(expectFailure(confirmMismatch, at: .confirmBytes, id: "local-confirm-mismatch"))

    var unresolved = try HTTPSDestination(
        urlString: "https://ha.example/hook",
        allowedHosts: ["ha.example"]
    )
    var components = URLComponents(url: unresolved.url, resolvingAgainstBaseURL: false)!
    components.host = ""
    unresolved.url = try #require(components.url)
    let resolve = await HTTPSDestinationTest.run(
        destination: unresolved,
        transport: RecordingHTTPTransport(response: OutboundHTTPResponse(status: 204, body: Data())),
        canary: Data("canary\n".utf8)
    )
    named.append(expectFailure(resolve, at: .resolveHost, id: "https-resolve"))

    let tlsThrowTransport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 204, body: Data()),
        identityError: .transport("handshake")
    )
    named.append(
        expectFailure(
            await HTTPSDestinationTest.run(
                destination: try httpsHook(),
                transport: tlsThrowTransport,
                canary: Data("canary\n".utf8)
            ),
            at: .tlsHandshake,
            id: "https-tls-throw"
        )
    )

    let tlsNilTransport = RecordingHTTPTransport(response: OutboundHTTPResponse(status: 204, body: Data()))
    named.append(
        expectFailure(
            await HTTPSDestinationTest.run(
                destination: try httpsHook(),
                transport: tlsNilTransport,
                canary: Data("canary\n".utf8)
            ),
            at: .tlsHandshake,
            id: "https-tls-nil"
        )
    )

    let pinTransport = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 204, body: Data()),
        tls: sampleIdentity(leaf: "eeeeffff00001111")
    )
    named.append(
        expectFailure(
            await HTTPSDestinationTest.run(
                destination: try httpsHook(),
                transport: pinTransport,
                pin: PinRecord(
                    leafSPKISha256: "aaaabbbbccccdddd",
                    issuerSPKISha256: "issuer00",
                    firstSeen: "2024-01-01T00:00:00Z",
                    policy: .leaf
                ),
                canary: Data("canary\n".utf8)
            ),
            at: .confirmCertificate,
            id: "https-pin-mismatch"
        )
    )

    named.append(
        expectFailure(
            await HTTPSDestinationTest.run(
                destination: try HTTPSDestination(
                    urlString: "https://ha.example/hook",
                    allowedHosts: ["ha.example"],
                    authorizationBearer: "token"
                ),
                transport: RecordingHTTPTransport(
                    response: OutboundHTTPResponse(status: 401, body: Data()),
                    tls: sampleIdentity(leaf: "aaaabbbbccccdddd")
                ),
                canary: Data("canary\n".utf8)
            ),
            at: .authenticate,
            id: "https-401"
        )
    )

    named.append(
        expectFailure(
            await HTTPSDestinationTest.run(
                destination: try httpsHook(),
                transport: RecordingHTTPTransport(
                    response: OutboundHTTPResponse(status: 403, body: Data()),
                    tls: sampleIdentity(leaf: "aaaabbbbccccdddd")
                ),
                canary: Data("canary\n".utf8)
            ),
            at: .authenticate,
            id: "https-403"
        )
    )

    let postThrow = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 204, body: Data()),
        tls: sampleIdentity(leaf: "aaaabbbbccccdddd")
    )
    await postThrow.failOnce(.transport("post"))
    named.append(
        expectFailure(
            await HTTPSDestinationTest.run(
                destination: try httpsHook(),
                transport: postThrow,
                canary: Data("canary\n".utf8)
            ),
            at: .sendCanary,
            id: "https-post-throw"
        )
    )

    named.append(
        expectFailure(
            await HTTPSDestinationTest.run(
                destination: try httpsHook(),
                transport: RecordingHTTPTransport(
                    response: OutboundHTTPResponse(status: 502, body: Data()),
                    tls: sampleIdentity(leaf: "aaaabbbbccccdddd")
                ),
                canary: Data("canary\n".utf8)
            ),
            at: .sendCanary,
            id: "https-502"
        )
    )

    let getThrow = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 201, body: Data()),
        tls: sampleIdentity(leaf: "aaaabbbbccccdddd")
    )
    await getThrow.enqueue(OutboundHTTPResponse(status: 201, body: Data()))
    await getThrow.failStartingAtExecute(2, .transport("get"))
    named.append(
        expectFailure(
            await HTTPSDestinationTest.run(
                destination: try httpsHook(),
                transport: getThrow,
                canary: Data("canary\n".utf8),
                entityURL: URL(string: "https://ha.example/api/states/sensor.ohe_steps")!,
                expected: MetricCatalog.stepCount
            ),
            at: .readResponse,
            id: "https-get-throw"
        )
    )

    let getMismatch = RecordingHTTPTransport(
        response: OutboundHTTPResponse(status: 200, body: Data()),
        tls: sampleIdentity(leaf: "aaaabbbbccccdddd")
    )
    await getMismatch.enqueue(OutboundHTTPResponse(status: 201, body: Data()))
    await getMismatch.enqueue(
        OutboundHTTPResponse(
            status: 200,
            body: Data("{\"attributes\":{\"unit_of_measurement\":\"kcal\"}}".utf8)
        )
    )
    named.append(
        expectFailure(
            await HTTPSDestinationTest.run(
                destination: try HTTPSDestination(
                    urlString: "https://ha.example/api/states/sensor.ohe_steps",
                    allowedHosts: ["ha.example"]
                ),
                transport: getMismatch,
                canary: Data("canary\n".utf8),
                entityURL: URL(string: "https://ha.example/api/states/sensor.ohe_steps")!,
                expected: MetricCatalog.stepCount
            ),
            at: .readResponse,
            id: "https-get-mismatch"
        )
    )

    named.append(
        expectFailure(
            await MQTTDestinationTest.run(
                destination: try mqttPlain(),
                pipe: ConnackRefusedMQTTPipe(),
                canary: Data("canary\n".utf8)
            ),
            at: .connect,
            id: "mqtt-connack-refused"
        )
    )

    named.append(
        expectFailure(
            await MQTTDestinationTest.run(
                destination: try mqttPlain(),
                pipe: ConnackThenFailMQTTPipe(),
                canary: Data("canary\n".utf8)
            ),
            at: .publishCanary,
            id: "mqtt-publish-throw"
        )
    )

    named.append(
        expectFailure(
            await CompanionDestinationTest.run(
                pipe: ThrowingCompanionPipe(),
                installationID: "phone",
                canary: Data("companion-canary".utf8)
            ),
            at: .connect,
            id: "companion-connect-throw"
        )
    )

    named.append(
        expectFailure(
            await CompanionDestinationTest.run(
                pipe: HelloThenThrowCompanionPipe(),
                installationID: "phone",
                canary: Data("companion-canary".utf8)
            ),
            at: .sendCanary,
            id: "companion-offer-throw"
        )
    )

    named.append(
        expectFailure(
            await CompanionDestinationTest.run(
                pipe: ResumeThenBadReceiptCompanionPipe(),
                installationID: "phone",
                canary: Data("companion-canary".utf8)
            ),
            at: .readResponse,
            id: "companion-bad-receipt"
        )
    )

    #expect(named.count >= 15)
    #expect(Set(named.map(\.0)).count == named.count)
}

private func httpsHook() throws -> HTTPSDestination {
    try HTTPSDestination(urlString: "https://ha.example/hook", allowedHosts: ["ha.example"])
}

private func mqttPlain() throws -> MQTTDestination {
    try MQTTDestination(
        urlString: "mqtt://broker.example:1883",
        allowedHosts: ["broker.example"],
        allowInsecure: true,
        clientID: "c1",
        topic: "ohe/health"
    )
}

private func expectFailure(
    _ report: DestinationTestReport,
    at step: DestinationTestStep,
    id: String
) -> (String, DestinationTestStep) {
    #expect(report.verdict == .failed)
    #expect(report.failingStep == step)
    #expect(report.failingStep?.progressLabel == step.progressLabel)
    return (id, step)
}

private actor ConnackRefusedMQTTPipe: MQTTBytePipe {
    func send(_ data: Data) async throws {}

    func receive(max: Int) async throws -> Data {
        Data([0x20, 0x02, 0x00, 0x05])
    }
}

private actor ConnackThenFailMQTTPipe: MQTTBytePipe {
    private var sends = 0

    func send(_ data: Data) async throws {
        sends += 1
        if sends > 1 {
            throw EgressError.transport("publish")
        }
    }

    func receive(max: Int) async throws -> Data {
        Data([0x20, 0x02, 0x00, 0x00])
    }
}

private actor ThrowingCompanionPipe: CompanionBytePipe {
    func send(_ data: Data) async throws {
        throw EgressError.transport("connect")
    }

    func receive(max: Int) async throws -> Data {
        Data()
    }
}

private actor HelloThenThrowCompanionPipe: CompanionBytePipe {
    private let inner = LoopbackCompanionBroker()

    func send(_ data: Data) async throws {
        var remainder = data
        while let decoded = try CompanionFrame.decodePrefix(remainder) {
            remainder.removeFirst(decoded.consumed)
            if case .offer = try CompanionMessage.decode(decoded.frame) {
                throw EgressError.transport("offer")
            }
        }
        try await inner.send(data)
    }

    func receive(max: Int) async throws -> Data {
        try await inner.receive(max: max)
    }
}

private actor ResumeThenBadReceiptCompanionPipe: CompanionBytePipe {
    private var remainder = Data()
    private var outbox = Data()
    private var waiters: [CheckedContinuation<Data, Error>] = []
    private var batchID = "canary"

    func send(_ data: Data) async throws {
        remainder.append(data)
        while let decoded = try CompanionFrame.decodePrefix(remainder) {
            remainder.removeFirst(decoded.consumed)
            switch try CompanionMessage.decode(decoded.frame) {
            case .hello:
                enqueue(
                    try CompanionMessage.hello(
                        protocolVersion: CompanionReceiver.protocolVersion,
                        installationID: "mac",
                        capabilities: CompanionReceiver.capabilities
                    ).encodedFrame()
                )
            case .offer(let offer):
                batchID = offer.batchID
                enqueue(try CompanionMessage.resume(fromChunk: 0).encodedFrame())
            case .chunk(let seq, _):
                enqueue(try CompanionMessage.chunkAck(seq: seq).encodedFrame())
            case .commit:
                enqueue(
                    try CompanionMessage.receipt(batchID: batchID, digest: "deadbeef").encodedFrame()
                )
            default:
                break
            }
        }
    }

    func receive(max: Int) async throws -> Data {
        if !outbox.isEmpty {
            let n = min(max, outbox.count)
            let chunk = outbox.prefix(n)
            outbox.removeFirst(n)
            return Data(chunk)
        }
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func enqueue(_ data: Data) {
        if waiters.isEmpty {
            outbox.append(data)
        } else {
            let waiter = waiters.removeFirst()
            waiter.resume(returning: data)
        }
    }
}
