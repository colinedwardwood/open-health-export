// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import EnginePorts
import Foundation
import NetEgress
import RunJournal
import StorageSQLite
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

@Test func ledgerHeadRecordDetectsChainRewriteAndIdentityChange() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-ledger-seal-\(UUID().uuidString).json")
    let first = LedgerChain.seal(
        EgressEntry(
            destination: "local-file",
            sampleCount: 1,
            outcomeKind: "attempt",
            wallTimeEpoch: 1
        ),
        sequence: 1,
        previousHash: LedgerChain.genesisHash
    )
    let seal = HashLedgerSeal(secret: "device-a")
    try await LedgerHeadSealRecordFile.update(
        entries: [first],
        seal: seal,
        sealedAtEpoch: 2,
        url: url
    )
    #expect(
        await LedgerHeadSealRecordFile.verify(entries: [first], seal: seal, url: url)
            == .valid(head: first.entryHash, count: 1)
    )
    #expect(
        await LedgerHeadSealRecordFile.verify(
            entries: [first],
            seal: HashLedgerSeal(secret: "device-b"),
            url: url
        ) == .identityChanged
    )
    var rewritten = first
    rewritten.sampleCount = 99
    #expect(
        await LedgerHeadSealRecordFile.verify(entries: [rewritten], seal: seal, url: url)
            == .chainInvalid(sequence: 1)
    )
}

@Test func r30PersistedLedgerTamperIsDetectedAfterStoreRelaunch() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-r30-relaunch-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let database = root.appendingPathComponent("state.sqlite").path
    let sealURL = root.appendingPathComponent("ledger-head-seal.json")
    let seal = HashLedgerSeal(secret: "r30-device")

    let initial = try SQLiteStateStore(path: database)
    try await initial.transact { tx in
        try tx.appendLedger(
            EgressEntry(
                destination: "https",
                sampleCount: 7,
                outcomeKind: "success",
                wallTimeEpoch: 1
            )
        )
        try tx.appendLedger(
            EgressEntry(
                destination: "mqtt",
                sampleCount: 3,
                outcomeKind: "success",
                wallTimeEpoch: 2
            )
        )
    }
    let original = try await initial.transact { try $0.loadLedger() }
    try await LedgerHeadSealRecordFile.update(
        entries: original,
        seal: seal,
        sealedAtEpoch: 3,
        url: sealURL
    )
    try initial.tamperLedgerSampleCountForTesting(sequence: 1, sampleCount: 700)

    let relaunched = try SQLiteStateStore(path: database)
    let reloaded = try await relaunched.transact { try $0.loadLedger() }
    #expect(
        await LedgerHeadSealRecordFile.verify(entries: reloaded, seal: seal, url: sealURL)
            == .chainInvalid(sequence: 1)
    )
}

#if canImport(Security)
@Test func p256LedgerSealSignsAndDetectsHeadChangesWithoutSecureEnclaveInTests() async throws {
    let seal = SecureEnclaveLedgerSeal(
        applicationTag: "app.openhealthexporter.test.ephemeral",
        useSecureEnclave: false,
        permanent: false
    )
    let signature = try await seal.signedHead("head-1")
    #expect(await seal.matches(head: "head-1", signature: signature))
    #expect(!(await seal.matches(head: "head-2", signature: signature)))
}

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
