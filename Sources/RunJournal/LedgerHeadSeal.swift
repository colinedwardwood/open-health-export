import EnginePorts
import Foundation
import WireFormat

public protocol LedgerHeadSeal: Sendable {
    func signedHead(_ head: String) async throws -> String
    func matches(head: String, signature: String) async -> Bool
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
