// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CSQLite
import EnginePorts
import Foundation
import StorageSQLite

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// QA-31's pre-release on-disk shape, before the current store's `ALTER TABLE`
/// expansions (`PRAGMA user_version = 1`). It lives in TestSupport rather than
/// StorageSQLite so a fixture generator is not shipped in the production graph.
public enum SQLiteV1Fixture {
    public static func write(
        path: String,
        metric: MetricID,
        checkpoint: CheckpointEnvelope,
        runID: String,
        deliveries: [(batchID: String, accepted: Int)] = []
    ) throws {
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(
            path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE,
            nil
        )
        guard status == SQLITE_OK, let db = handle else {
            throw StorageError.openFailed("legacy fixture")
        }
        defer { sqlite3_close(db) }
        try exec(
            db,
            """
            CREATE TABLE journal (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                run_id TEXT NOT NULL,
                outcome TEXT NOT NULL,
                detail TEXT NOT NULL
            );
            CREATE TABLE cursors (
                metric TEXT PRIMARY KEY,
                epoch INTEGER NOT NULL,
                anchor BLOB NOT NULL
            );
            INSERT INTO journal (run_id, outcome, detail)
                VALUES ('\(runID)', 'success', 'legacy');
            PRAGMA user_version = 1;
            """
        )
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            "INSERT INTO cursors (metric, epoch, anchor) VALUES (?, ?, ?);",
            -1,
            &stmt,
            nil
        ) == SQLITE_OK, let stmt else {
            throw StorageError.execFailed("legacy cursor")
        }
        defer { sqlite3_finalize(stmt) }
        let blob = checkpoint.encoded()
        sqlite3_bind_text(stmt, 1, metric.rawValue, -1, sqliteTransient)
        sqlite3_bind_int64(stmt, 2, sqlite3_int64(checkpoint.epoch))
        blob.withUnsafeBytes { raw in
            _ = sqlite3_bind_blob(stmt, 3, raw.baseAddress, Int32(blob.count), sqliteTransient)
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.execFailed("legacy cursor insert")
        }
        guard !deliveries.isEmpty else { return }
        // Every schema through 19 keyed the audit by batch alone.
        try exec(
            db,
            """
            CREATE TABLE deliveries (
                batch_id TEXT PRIMARY KEY,
                accepted INTEGER NOT NULL
            );
            """
        )
        for delivery in deliveries {
            try exec(
                db,
                """
                INSERT INTO deliveries (batch_id, accepted)
                    VALUES ('\(delivery.batchID)', \(delivery.accepted));
                """
            )
        }
    }

    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(db, sql, nil, nil, &err)
        if let err {
            let message = String(cString: err)
            sqlite3_free(err)
            if status != SQLITE_OK { throw StorageError.execFailed(message) }
        } else if status != SQLITE_OK {
            throw StorageError.execFailed("sqlite status \(status)")
        }
    }
}
