// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import WireFormat

public struct CompanionCommitted: Sendable, Equatable {
    public var batchID: String
    public var digest: String
    public var payload: Data

    public init(batchID: String, digest: String, payload: Data) {
        self.batchID = batchID
        self.digest = digest
        self.payload = payload
    }
}

public struct CompanionTurn: Sendable, Equatable {
    public var replies: [CompanionMessage]
    public var committed: CompanionCommitted?
    /// Set when the inbound HELLO names the peer. The Mac uses this to compute the SAS.
    public var peerInstallationID: String?

    public init(
        replies: [CompanionMessage],
        committed: CompanionCommitted? = nil,
        peerInstallationID: String? = nil
    ) {
        self.replies = replies
        self.committed = committed
        self.peerInstallationID = peerInstallationID
    }
}

public struct CompanionReceiver: Sendable {
    public static let protocolVersion: UInt8 = 1
    public static let capabilities = ["resume", "ohe.wire/1", "traceparent"]

    public var installationID: String
    private var receipts: [String: String]
    private var inflight: Inflight?

    public init(installationID: String, receipts: [String: String] = [:]) {
        self.installationID = installationID
        self.receipts = receipts
    }

    public mutating func handle(_ message: CompanionMessage) -> [CompanionMessage] {
        process(message).replies
    }

    public mutating func process(_ message: CompanionMessage) -> CompanionTurn {
        switch message {
        case .hello(let version, let peerID, _):
            if version != Self.protocolVersion {
                return CompanionTurn(replies: [
                    .reject(errorClass: "internalFault", detail: "protocolVersion", retryable: false)
                ])
            }
            // Inbound trace context, if a peer ever sent one, is ignored: this hello starts a root.
            return CompanionTurn(
                replies: [.hello(
                    protocolVersion: Self.protocolVersion,
                    installationID: installationID,
                    capabilities: Self.capabilities
                )],
                peerInstallationID: peerID
            )
        case .offer(let offer):
            return CompanionTurn(replies: [respond(to: offer)])
        case .chunk(let seq, let bytes):
            guard inflight != nil else {
                return CompanionTurn(replies: [
                    .reject(errorClass: "internalFault", detail: "chunkWithoutOffer", retryable: false)
                ])
            }
            inflight?.chunks[seq] = bytes
            return CompanionTurn(replies: [.chunkAck(seq: seq)])
        case .commit(let digest):
            return commit(digest: digest)
        default:
            return CompanionTurn(replies: [
                .reject(errorClass: "internalFault", detail: "unexpected", retryable: false)
            ])
        }
    }

    public func storedDigest(batchID: String) -> String? {
        receipts[batchID]
    }

    public func exportReceipts() -> [String: String] {
        receipts
    }

    private mutating func respond(to offer: CompanionOffer) -> CompanionMessage {
        var offer = offer
        offer.traceparent = nil
        if let stored = receipts[offer.batchID] {
            if stored == offer.digest {
                return .receipt(batchID: offer.batchID, digest: stored)
            }
            return .reject(errorClass: "internalFault", detail: "digestMismatch", retryable: false)
        }
        if let current = inflight, current.offer.batchID == offer.batchID {
            if current.offer.digest != offer.digest {
                return .reject(errorClass: "internalFault", detail: "digestMismatch", retryable: false)
            }
            return .resume(fromChunk: current.nextContiguous)
        }
        inflight = Inflight(offer: offer, chunks: [:])
        return .resume(fromChunk: 0)
    }

    private mutating func commit(digest: String) -> CompanionTurn {
        guard let current = inflight else {
            return CompanionTurn(replies: [
                .reject(errorClass: "internalFault", detail: "commitWithoutOffer", retryable: false)
            ])
        }
        let assembled = current.assembled
        guard UInt64(assembled.count) == current.offer.byteCount else {
            return CompanionTurn(replies: [
                .reject(errorClass: "internalFault", detail: "byteCount", retryable: true)
            ])
        }
        let computed = ContentSHA256.digest(assembled)
        guard computed == current.offer.digest, computed == digest else {
            return CompanionTurn(replies: [
                .reject(errorClass: "internalFault", detail: "digestMismatch", retryable: false)
            ])
        }
        receipts[current.offer.batchID] = computed
        inflight = nil
        return CompanionTurn(
            replies: [.receipt(batchID: current.offer.batchID, digest: computed)],
            committed: CompanionCommitted(batchID: current.offer.batchID, digest: computed, payload: assembled)
        )
    }
}

private struct Inflight: Sendable {
    var offer: CompanionOffer
    var chunks: [UInt32: Data]

    var nextContiguous: UInt32 {
        var seq: UInt32 = 0
        while chunks[seq] != nil { seq += 1 }
        return seq
    }

    var assembled: Data {
        var data = Data()
        var seq: UInt32 = 0
        while let part = chunks[seq] {
            data.append(part)
            seq += 1
        }
        return data
    }
}
