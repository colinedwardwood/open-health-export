// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CompanionWire
import CoreDomain
import EnginePorts
import Foundation
import NetEgress
import WireFormat

public protocol CompanionBytePipe: Sendable {
    func send(_ data: Data) async throws
    func receive(max: Int) async throws -> Data
}

public enum CompanionError: Error, Equatable {
    case truncated
    case rejected(errorClass: String, detail: String, retryable: Bool)
    case unexpected
    case digestMismatch
}

public struct CompanionSink: DestinationSink, Sendable {
    public var pipe: any CompanionBytePipe
    public var installationID: String
    public var chunkSize: Int
    public var traceparent: TraceparentEmission?
    public var meteredPolicy: MeteredNetworkPolicy
    public var pathConditions: NetworkPathConditions

    public init(
        pipe: any CompanionBytePipe,
        installationID: String,
        chunkSize: Int = 16_384,
        traceparent: TraceparentEmission? = nil,
        meteredPolicy: MeteredNetworkPolicy = .refuseMetered,
        pathConditions: NetworkPathConditions = .clear
    ) {
        self.pipe = pipe
        self.installationID = installationID
        self.chunkSize = max(1, min(chunkSize, CompanionFrame.maxPayload - 4))
        self.traceparent = traceparent
        self.meteredPolicy = meteredPolicy
        self.pathConditions = pathConditions
    }

    public func send(fileHandle: String, idempotencyKey: BatchID) async throws -> DeliveryReceipt {
        try MeteredNetworkGate.require(path: pathConditions, policy: meteredPolicy)
        let file = URL(fileURLWithPath: fileHandle)
        let payload = try Data(contentsOf: file)
        let count = NativeWire.countRecords(in: String(decoding: payload, as: UTF8.self))
        let digest = ContentSHA256.digest(payload)
        let offer = CompanionOffer(
            batchID: idempotencyKey.rawValue,
            idempotencyKey: idempotencyKey.rawValue,
            byteCount: UInt64(payload.count),
            digest: digest
        )
        let session = CompanionSession(pipe: pipe)
        try await session.send(.hello(
            protocolVersion: CompanionReceiver.protocolVersion,
            installationID: installationID,
            capabilities: CompanionReceiver.capabilities
        ))
        let hello = try await session.receive()
        var peerAllowsTraceparent = false
        switch hello {
        case .hello(let version, _, let capabilities):
            if version != CompanionReceiver.protocolVersion { throw CompanionCodecError.protocolVersion }
            peerAllowsTraceparent = capabilities.contains("traceparent")
        case .reject(let errorClass, let detail, let retryable):
            throw CompanionError.rejected(errorClass: errorClass, detail: detail, retryable: retryable)
        default:
            throw CompanionError.unexpected
        }
        var outbound = offer
        if peerAllowsTraceparent {
            outbound.traceparent = traceparent?.header(seed: idempotencyKey.rawValue)
        }
        try await session.send(.offer(outbound))
        var reply = try await session.receive()
        var autoDisabled = false
        if case .reject = reply, outbound.traceparent != nil {
            outbound.traceparent = nil
            traceparent?.noteAutoDisabled()
            autoDisabled = true
            try await session.send(.offer(outbound))
            reply = try await session.receive()
        }
        switch reply {
        case .receipt(let batchID, let ackedDigest):
            guard batchID == offer.batchID, ackedDigest == digest else { throw CompanionError.digestMismatch }
            return DeliveryReceipt(
                batchID: idempotencyKey,
                accepted: count,
                statusOnly: false,
                traceparentAutoDisabled: autoDisabled
            )
        case .resume(let fromChunk):
            let parts = CompanionChunks.split(payload, size: chunkSize)
            var seq = fromChunk
            while seq < UInt32(parts.count) {
                try await session.send(.chunk(seq: seq, bytes: parts[Int(seq)]))
                guard case .chunkAck(let acked) = try await session.receive(), acked == seq else {
                    throw CompanionError.unexpected
                }
                seq += 1
            }
            try await session.send(.commit(digest: digest))
            switch try await session.receive() {
            case .receipt(let batchID, let ackedDigest):
                guard batchID == offer.batchID, ackedDigest == digest else { throw CompanionError.digestMismatch }
                return DeliveryReceipt(
                    batchID: idempotencyKey,
                    accepted: count,
                    statusOnly: false,
                    traceparentAutoDisabled: autoDisabled
                )
            case .reject(let errorClass, let detail, let retryable):
                throw CompanionError.rejected(errorClass: errorClass, detail: detail, retryable: retryable)
            default:
                throw CompanionError.unexpected
            }
        case .reject(let errorClass, let detail, let retryable):
            throw CompanionError.rejected(errorClass: errorClass, detail: detail, retryable: retryable)
        default:
            throw CompanionError.unexpected
        }
    }
}

public actor CompanionSession {
    private let pipe: any CompanionBytePipe
    private var inbound = Data()

    public init(pipe: any CompanionBytePipe) {
        self.pipe = pipe
    }

    public func send(_ message: CompanionMessage) async throws {
        try await pipe.send(try message.encodedFrame())
    }

    public func receive() async throws -> CompanionMessage {
        while true {
            if let decoded = try CompanionFrame.decodePrefix(inbound) {
                inbound.removeFirst(decoded.consumed)
                return try CompanionMessage.decode(decoded.frame)
            }
            let chunk = try await pipe.receive(max: 4096)
            if chunk.isEmpty { throw CompanionError.truncated }
            inbound.append(chunk)
        }
    }
}
