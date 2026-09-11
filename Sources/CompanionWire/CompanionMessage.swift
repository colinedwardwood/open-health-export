// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public struct CompanionOffer: Sendable, Equatable {
    public var batchID: String
    public var idempotencyKey: String
    public var format: String
    public var schemaVersion: String
    public var byteCount: UInt64
    public var digest: String
    public var traceparent: String?

    public init(
        batchID: String,
        idempotencyKey: String,
        format: String = "ohe.wire/1",
        schemaVersion: String = "1.0",
        byteCount: UInt64,
        digest: String,
        traceparent: String? = nil
    ) {
        self.batchID = batchID
        self.idempotencyKey = idempotencyKey
        self.format = format
        self.schemaVersion = schemaVersion
        self.byteCount = byteCount
        self.digest = digest
        self.traceparent = traceparent
    }
}

public enum CompanionMessage: Sendable, Equatable {
    case hello(protocolVersion: UInt8, installationID: String, capabilities: [String])
    case offer(CompanionOffer)
    case resume(fromChunk: UInt32)
    case receipt(batchID: String, digest: String)
    case reject(errorClass: String, detail: String, retryable: Bool)
    case chunk(seq: UInt32, bytes: Data)
    case chunkAck(seq: UInt32)
    case commit(digest: String)

    public var frameType: CompanionFrameType {
        switch self {
        case .hello: return .hello
        case .offer: return .offer
        case .resume: return .resume
        case .receipt: return .receipt
        case .reject: return .reject
        case .chunk: return .chunk
        case .chunkAck: return .chunkAck
        case .commit: return .commit
        }
    }

    public func encodedFrame() throws -> Data {
        try CompanionFrame(type: frameType, payload: encodePayload()).encode()
    }

    public static func decode(_ frame: CompanionFrame) throws -> CompanionMessage {
        let bytes = [UInt8](frame.payload)
        var i = 0
        switch frame.type {
        case .hello:
            guard i < bytes.count else { throw CompanionCodecError.truncated }
            let version = bytes[i]
            i += 1
            let installationID = try CompanionBinary.readString(bytes, i: &i)
            guard i < bytes.count else { throw CompanionCodecError.truncated }
            let capCount = Int(bytes[i])
            i += 1
            var capabilities: [String] = []
            capabilities.reserveCapacity(capCount)
            for _ in 0..<capCount {
                try capabilities.append(CompanionBinary.readString(bytes, i: &i))
            }
            guard i == bytes.count else { throw CompanionCodecError.trailingBytes }
            return .hello(protocolVersion: version, installationID: installationID, capabilities: capabilities)
        case .offer:
            let batchID = try CompanionBinary.readString(bytes, i: &i)
            let idempotencyKey = try CompanionBinary.readString(bytes, i: &i)
            let format = try CompanionBinary.readString(bytes, i: &i)
            let schemaVersion = try CompanionBinary.readString(bytes, i: &i)
            guard i + 8 <= bytes.count else { throw CompanionCodecError.truncated }
            let byteCount = CompanionBinary.readU64(bytes, at: i)
            i += 8
            let digest = try CompanionBinary.readString(bytes, i: &i)
            var traceparent: String?
            if i < bytes.count {
                traceparent = try CompanionBinary.readString(bytes, i: &i)
                if traceparent?.isEmpty == true {
                    traceparent = nil
                }
            }
            guard i == bytes.count else { throw CompanionCodecError.trailingBytes }
            return .offer(CompanionOffer(
                batchID: batchID,
                idempotencyKey: idempotencyKey,
                format: format,
                schemaVersion: schemaVersion,
                byteCount: byteCount,
                digest: digest,
                traceparent: traceparent
            ))
        case .resume:
            guard bytes.count == 4 else { throw CompanionCodecError.trailingBytes }
            return .resume(fromChunk: CompanionBinary.readU32(bytes, at: 0))
        case .receipt:
            let batchID = try CompanionBinary.readString(bytes, i: &i)
            let digest = try CompanionBinary.readString(bytes, i: &i)
            guard i == bytes.count else { throw CompanionCodecError.trailingBytes }
            return .receipt(batchID: batchID, digest: digest)
        case .reject:
            guard i < bytes.count else { throw CompanionCodecError.truncated }
            // Only the two canonical encodings: widening every non-zero byte to `true` would
            // let 255 distinct wire frames decode to one message.
            guard bytes[i] <= 1 else { throw CompanionCodecError.badBoolean(bytes[i]) }
            let retryable = bytes[i] == 1
            i += 1
            let errorClass = try CompanionBinary.readString(bytes, i: &i)
            let detail = try CompanionBinary.readString(bytes, i: &i)
            guard i == bytes.count else { throw CompanionCodecError.trailingBytes }
            return .reject(errorClass: errorClass, detail: detail, retryable: retryable)
        case .chunk:
            guard bytes.count >= 4 else { throw CompanionCodecError.truncated }
            let seq = CompanionBinary.readU32(bytes, at: 0)
            return .chunk(seq: seq, bytes: Data(bytes.dropFirst(4)))
        case .chunkAck:
            guard bytes.count == 4 else { throw CompanionCodecError.trailingBytes }
            return .chunkAck(seq: CompanionBinary.readU32(bytes, at: 0))
        case .commit:
            let digest = try CompanionBinary.readString(bytes, i: &i)
            guard i == bytes.count else { throw CompanionCodecError.trailingBytes }
            return .commit(digest: digest)
        }
    }

    private func encodePayload() throws -> Data {
        var data = Data()
        switch self {
        case .hello(let version, let installationID, let capabilities):
            data.append(version)
            try CompanionBinary.writeString(installationID, into: &data)
            guard capabilities.count <= 255 else { throw CompanionCodecError.stringTooLong }
            data.append(UInt8(capabilities.count))
            for capability in capabilities {
                try CompanionBinary.writeString(capability, into: &data)
            }
        case .offer(let offer):
            try CompanionBinary.writeString(offer.batchID, into: &data)
            try CompanionBinary.writeString(offer.idempotencyKey, into: &data)
            try CompanionBinary.writeString(offer.format, into: &data)
            try CompanionBinary.writeString(offer.schemaVersion, into: &data)
            data.append(contentsOf: CompanionBinary.u64(offer.byteCount))
            try CompanionBinary.writeString(offer.digest, into: &data)
            if let traceparent = offer.traceparent, !traceparent.isEmpty {
                try CompanionBinary.writeString(traceparent, into: &data)
            }
        case .resume(let fromChunk):
            data.append(contentsOf: CompanionBinary.u32(fromChunk))
        case .receipt(let batchID, let digest):
            try CompanionBinary.writeString(batchID, into: &data)
            try CompanionBinary.writeString(digest, into: &data)
        case .reject(let errorClass, let detail, let retryable):
            data.append(retryable ? 1 : 0)
            try CompanionBinary.writeString(errorClass, into: &data)
            try CompanionBinary.writeString(detail, into: &data)
        case .chunk(let seq, let bytes):
            data.append(contentsOf: CompanionBinary.u32(seq))
            data.append(bytes)
        case .chunkAck(let seq):
            data.append(contentsOf: CompanionBinary.u32(seq))
        case .commit(let digest):
            try CompanionBinary.writeString(digest, into: &data)
        }
        return data
    }
}

public enum CompanionChunks {
    public static func split(_ payload: Data, size: Int) -> [Data] {
        let chunkSize = max(1, size)
        if payload.isEmpty { return [] }
        var parts: [Data] = []
        var offset = 0
        while offset < payload.count {
            let end = min(offset + chunkSize, payload.count)
            parts.append(payload.subdata(in: offset..<end))
            offset = end
        }
        return parts
    }
}
