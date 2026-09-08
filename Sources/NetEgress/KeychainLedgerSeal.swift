#if canImport(Security)
import EnginePorts
import Foundation
import RunJournal
import Security

/// Keychain-backed ledger-head secret by default. Generates 32 random bytes on first use.
/// This is tamper-evidence of identity change after a wipe, not an SE signature.
public struct KeychainLedgerSeal: ResettableLedgerHeadSeal, Sendable {
    public var store: any SecretStore
    public var handle: SecretHandle

    public init(
        store: any SecretStore = KeychainSecretStore(service: "app.openhealthexporter.ledger"),
        handle: SecretHandle = SecretHandle(rawValue: "ledger-head")
    ) {
        self.store = store
        self.handle = handle
    }

    public func signedHead(_ head: String) async throws -> String {
        try await HashLedgerSeal(secret: secret()).signedHead(head)
    }

    public func matches(head: String, signature: String) async -> Bool {
        await HashLedgerSeal(secret: (try? await secret()) ?? "").matches(head: head, signature: signature)
    }

    public func destroyIdentity() async throws {
        try await store.delete(handle)
    }

    private func secret() async throws -> String {
        if let existing = try? await store.load(handle) {
            return Data(existing).base64EncodedString()
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw SecretStoreError.notFound }
        try await store.store(bytes, handle: handle)
        return Data(bytes).base64EncodedString()
    }
}
#endif
