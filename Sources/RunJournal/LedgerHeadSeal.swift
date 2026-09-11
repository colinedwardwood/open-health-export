// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import EnginePorts
import Foundation
import WireFormat

public protocol LedgerHeadSeal: Sendable {
    func signedHead(_ head: String) async throws -> String
    func matches(head: String, signature: String) async -> Bool
}

public protocol ResettableLedgerHeadSeal: LedgerHeadSeal {
    func destroyIdentity() async throws
}

public struct LedgerHeadSealRecord: Sendable, Equatable, Codable {
    public var schemaVersion: Int
    public var head: String
    public var signature: String
    public var sealedAtEpoch: TimeInterval

    public init(head: String, signature: String, sealedAtEpoch: TimeInterval) {
        self.schemaVersion = 1
        self.head = head
        self.signature = signature
        self.sealedAtEpoch = sealedAtEpoch
    }
}

public enum LedgerHeadSealVerification: Sendable, Equatable {
    case valid(head: String, count: Int)
    case chainInvalid(sequence: Int)
    case sealMissing
    case headMismatch
    case identityChanged
}

public enum LedgerHeadSealRecordError: Error, Equatable {
    case chainInvalid(sequence: Int)
}

public enum LedgerHeadSealRecordFile {
    public static func update(
        entries: [EgressEntry],
        seal: any LedgerHeadSeal,
        sealedAtEpoch: TimeInterval,
        url: URL
    ) async throws {
        let head: String
        switch LedgerChain.verify(entries) {
        case .valid(let verifiedHead, _):
            head = verifiedHead
        case .invalid(let sequence):
            throw LedgerHeadSealRecordError.chainInvalid(sequence: sequence)
        }
        let record = LedgerHeadSealRecord(
            head: head,
            signature: try await seal.signedHead(head),
            sealedAtEpoch: sealedAtEpoch
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(record)
        try data.write(to: url, options: .atomic)
    }

    public static func verify(
        entries: [EgressEntry],
        seal: any LedgerHeadSeal,
        url: URL
    ) async -> LedgerHeadSealVerification {
        let head: String
        let count: Int
        switch LedgerChain.verify(entries) {
        case .valid(let verifiedHead, let verifiedCount):
            head = verifiedHead
            count = verifiedCount
        case .invalid(let sequence):
            return .chainInvalid(sequence: sequence)
        }
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(LedgerHeadSealRecord.self, from: data)
        else {
            return .sealMissing
        }
        guard record.head == head else { return .headMismatch }
        guard await seal.matches(head: head, signature: record.signature) else {
            return .identityChanged
        }
        return .valid(head: head, count: count)
    }
}

/// Portable seal: SHA-256 over a local secret. Not a Secure Enclave key.
public struct HashLedgerSeal: LedgerHeadSeal, Sendable {
    public var secret: String

    public init(secret: String) {
        self.secret = secret
    }

    public func signedHead(_ head: String) async throws -> String {
        ContentSHA256.hex(Data("ohe.ledger-head/1\n\(secret)\n\(head)".utf8))
    }

    public func matches(head: String, signature: String) async -> Bool {
        (try? await signedHead(head)) == signature
    }
}
