import EnginePorts
import Foundation
import NetEgress
import RunJournal
import TestSupport
import Testing

@Test func hashLedgerSealIsIdentityBound() async throws {
    let a = HashLedgerSeal(secret: "device-a")
    let b = HashLedgerSeal(secret: "device-b")
    let head = "seq:1:deadbeef"
    let signature = try await a.signedHead(head)
    #expect(await a.matches(head: head, signature: signature))
    #expect(!(await b.matches(head: head, signature: signature)))
}

#if canImport(Security)
@Test func keychainLedgerSealChangesWhenTheStoredSecretIsReplaced() async throws {
    let handle = SecretHandle(rawValue: "ledger")
    let store = MemorySecretStore()
    let seal = KeychainLedgerSeal(store: store, handle: handle)
    let signature = try await seal.signedHead("head-1")
    #expect(await seal.matches(head: "head-1", signature: signature))
    try await store.delete(handle)
    let rotated = KeychainLedgerSeal(store: store, handle: handle)
    #expect(!(await rotated.matches(head: "head-1", signature: signature)))
}
#endif
