// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import StorageSQLite

/// One `SQLiteStateStore` per database file for the life of the process (#26). Opening
/// the store from every call site gave each its own connection and re-ran the schema
/// check on every open; a first launch raced four of them against one fresh file.
///
/// A store that opened under a no-migration policy is only cached once it has opened,
/// which means its schema is already current, so later callers that may migrate lose
/// nothing by sharing it.
enum StateStoreHost {
    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var stores: [String: SQLiteStateStore] = [:]
    }

    private static let cache = Cache()

    static func store(
        path: String,
        policy: SQLiteOpenPolicy = SQLiteOpenPolicy()
    ) throws -> SQLiteStateStore {
        try cache.lock.withLock {
            if let existing = cache.stores[path] {
                return existing
            }
            let opened = try SQLiteStateStore(path: path, policy: policy)
            cache.stores[path] = opened
            return opened
        }
    }

    /// Call before deleting a database file, so no later caller gets a connection to
    /// the unlinked file.
    static func evict(path: String) {
        cache.lock.withLock {
            _ = cache.stores.removeValue(forKey: path)
        }
    }
}
