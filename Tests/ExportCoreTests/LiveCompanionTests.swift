// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if os(macOS)
import CompanionReceive
import CompanionWire
import CoreDomain
import EnginePorts
import FileWriteKit
import Foundation
import MetricCatalog
import Network
import SinkCompanion
import Testing
import WireFormat
@testable import NetEgress

/// Live TLS-PSK on loopback: Mac `NWListener` and phone `NWByteStream`.
@Suite(.serialized)
struct LiveCompanionPSKTests {
    @Test(.timeLimit(.minutes(1)))
    func companionSinkDeliversOverLiveTLSPSK() async throws {
        let secret = try PairingSecret.generateFromSystemRandomness()
        let psk = try CompanionPSK.preSharedKey(from: secret)
        let parameters = TLSParameters.preSharedKey(psk)
        let listener = try NWListener(using: parameters, on: .any)
        let queue = DispatchQueue(label: "ohe.live-companion")
        let accepted = AcceptedConnection()
        listener.newConnectionHandler = { connection in
            Task { await accepted.offer(connection, queue: queue) }
        }
        let port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            let once = OnceResumePort()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = listener.port {
                        once.resume(continuation, .success(port.rawValue))
                    } else {
                        once.resume(continuation, .failure(StreamError.badPort))
                    }
                case .failed(let error):
                    once.resume(continuation, .failure(error))
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        defer { listener.cancel() }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohe-live-companion-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let archive = CompanionArchive(directory: dir)
        let serve = Task {
            let inbound = try CompanionInbound(
                stream: try await accepted.take(),
                archive: archive,
                installationID: "mac"
            )
            try await inbound.serve()
        }

        let sample = heartSample("00000000-0000-0000-0000-0000000000c2")
        let batchID = BatchID(rawValue: "0192f3c1-0000-0000-0000-0000000000c2")
        let data = try NativeWire.encode(
            samples: [sample],
            tombstones: [],
            metric: MetricCatalog.heartRate.id,
            batchID: batchID,
            envelope: testEnvelope()
        )
        let digest = ContentSHA256.digest(data)
        try FileWriteKit.writeAtomically(data, to: dir.appendingPathComponent("batch.ndjson"))
        let phone = NWByteStream(
            endpoint: try StreamEndpoint(host: "127.0.0.1", port: port, usesTLS: true),
            options: NWByteStream.Options(
                connectTimeout: .seconds(8),
                failFastOnWaiting: true,
                preSharedKey: psk
            )
        )
        let sink = CompanionSink(
            pipe: ByteStreamCompanionPipe(stream: phone),
            installationID: "phone",
            chunkSize: 32
        )
        let receipt = try await sink.send(
            fileHandle: dir.appendingPathComponent("batch.ndjson").path,
            idempotencyKey: batchID
        )
        #expect(receipt.accepted == 1)
        #expect(try archive.loadReceipts()[batchID.rawValue] == digest)
        serve.cancel()
    }
}

private actor AcceptedConnection {
    private var waiters: [CheckedContinuation<AcceptedNWStream, Error>] = []
    private var ready: [AcceptedNWStream] = []

    func offer(_ connection: NWConnection, queue: DispatchQueue) async {
        let stream = AcceptedNWStream(connection: connection, queue: queue)
        await stream.start()
        if waiters.isEmpty {
            ready.append(stream)
        } else {
            waiters.removeFirst().resume(returning: stream)
        }
    }

    func take() async throws -> AcceptedNWStream {
        if let first = ready.first {
            ready.removeFirst()
            return first
        }
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private final class OnceResumePort: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func resume(_ continuation: CheckedContinuation<UInt16, Error>, _ result: Result<UInt16, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        continuation.resume(with: result)
    }
}
#endif
