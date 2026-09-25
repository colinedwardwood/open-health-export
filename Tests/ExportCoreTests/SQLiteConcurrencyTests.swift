// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import EnginePorts
import Foundation
import StorageSQLite
import Testing

/// #25: a first launch opens the store from several places at once. Before the busy
/// timeout moved ahead of the journal-mode change, most of these opens failed with
/// "database is locked".
@Test func concurrentOpensOfAFreshStoreAllSucceed() async throws {
    for iteration in 0..<40 {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohe-fresh-\(iteration)-\(UUID().uuidString).sqlite").path
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: path + suffix)
            }
        }
        let sequences = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    let store = try SQLiteStateStore(path: path)
                    return try await store.transact {
                        try $0.reserveBatchSequence(exporterID: "fresh")
                    }
                }
            }
            var collected: [Int] = []
            for try await sequence in group { collected.append(sequence) }
            return collected
        }
        #expect(sequences.sorted() == Array(1...8))
    }
}

/// #26: one instance shared by many tasks. Without a lock held from BEGIN to COMMIT,
/// one task's COMMIT could land inside another's transaction.
@Test func concurrentTransactionsOnOneSharedStoreSerialize() async throws {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-shared-\(UUID().uuidString).sqlite").path
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
    }
    let store = try SQLiteStateStore(path: path)
    let sequences = try await withThrowingTaskGroup(of: Int.self) { group in
        for _ in 0..<200 {
            group.addTask {
                try await store.transact { try $0.reserveBatchSequence(exporterID: "shared") }
            }
        }
        var collected: [Int] = []
        for try await sequence in group { collected.append(sequence) }
        return collected
    }
    #expect(sequences.sorted() == Array(1...200))
    #expect(try await store.transact { try $0.reserveBatchSequence(exporterID: "shared") } == 201)
}

@Test func storageErrorsDescribeThemselves() {
    let error: any Error = StorageError.execFailed("database is locked")
    #expect(error.localizedDescription.contains("database is locked"))
    #expect(!error.localizedDescription.contains("StorageError"))
}
