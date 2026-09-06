import CoreDomain
import CSQLite
import EnginePorts
import Foundation

public struct SQLiteOpenPolicy: Sendable {
    public var protectionClassFlag: Int32?

    public init(
        protectionClassFlag: Int32? = {
            #if os(iOS) || os(macOS)
            SQLITE_OPEN_FILEPROTECTION_COMPLETEUNTILFIRSTUSERAUTHENTICATION
            #else
            nil
            #endif
        }()
    ) {
        self.protectionClassFlag = protectionClassFlag
    }
}

public enum StorageError: Error {
    case openFailed(String)
    case execFailed(String)
    case bindFailed
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class SQLiteStateStore: StateStore, @unchecked Sendable {
    fileprivate var db: OpaquePointer?
    private let policy: SQLiteOpenPolicy

    public init(path: String, policy: SQLiteOpenPolicy = SQLiteOpenPolicy()) throws {
        self.policy = policy
        var flags: Int32 = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if let extra = policy.protectionClassFlag {
            flags |= extra
        }
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(path, &handle, flags, nil)
        guard status == SQLITE_OK, let handle else {
            throw StorageError.openFailed(String(cString: sqlite3_errmsg(handle)))
        }
        db = handle
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA synchronous=FULL;")
        try exec("PRAGMA busy_timeout=5000;")
        try exec("PRAGMA journal_size_limit=4194304;")
        try exec("PRAGMA wal_autocheckpoint=1000;")
        try migrate()
        do {
            try exec("ALTER TABLE pending_batches ADD COLUMN byte_count INTEGER NOT NULL DEFAULT 0;")
        } catch {
            _ = error
        }
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    private func migrate() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS journal (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                run_id TEXT NOT NULL,
                outcome TEXT NOT NULL,
                detail TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS ledger (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                destination TEXT NOT NULL,
                sample_count INTEGER NOT NULL,
                outcome TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS cursors (
                metric TEXT PRIMARY KEY,
                epoch INTEGER NOT NULL,
                anchor BLOB NOT NULL
            );
            CREATE TABLE IF NOT EXISTS census (
                metric TEXT NOT NULL,
                day TEXT NOT NULL,
                sample_count INTEGER NOT NULL,
                digest TEXT NOT NULL,
                PRIMARY KEY (metric, day)
            );
            CREATE TABLE IF NOT EXISTS dirty (
                metric TEXT NOT NULL,
                day TEXT NOT NULL,
                PRIMARY KEY (metric, day)
            );
            CREATE TABLE IF NOT EXISTS pending_batches (
                batch_id TEXT PRIMARY KEY,
                payload_url TEXT NOT NULL,
                expected_records INTEGER NOT NULL,
                byte_count INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS deliveries (
                batch_id TEXT PRIMARY KEY,
                accepted INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS gaps (
                batch_id TEXT PRIMARY KEY,
                range_description TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS emitted_index (
                uuid TEXT PRIMARY KEY,
                metric TEXT NOT NULL,
                day TEXT NOT NULL,
                digest TEXT NOT NULL,
                batch_id TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_emitted_metric_day ON emitted_index (metric, day);
            PRAGMA user_version = 5;
            """)
    }

    public func transact<T: Sendable>(
        _ body: (any StateTransaction) throws -> T
    ) async throws -> T {
        try exec("BEGIN IMMEDIATE;")
        do {
            let tx = SQLiteTransaction(store: self)
            let result = try body(tx)
            try exec("COMMIT;")
            return result
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    fileprivate func exec(_ sql: String) throws {
        guard let db else { throw StorageError.openFailed("closed") }
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

    fileprivate func prepare(_ sql: String) throws -> OpaquePointer {
        guard let db else { throw StorageError.openFailed("closed") }
        var stmt: OpaquePointer?
        let status = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard status == SQLITE_OK, let stmt else {
            throw StorageError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
        return stmt
    }
}

private final class SQLiteTransaction: StateTransaction {
    unowned let store: SQLiteStateStore

    init(store: SQLiteStateStore) {
        self.store = store
    }

    func loadCursor(metric: MetricID) throws -> CursorSnapshot? {
        let stmt = try store.prepare("SELECT epoch, anchor FROM cursors WHERE metric = ? LIMIT 1;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, metric.rawValue)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        _ = sqlite3_column_int64(stmt, 0)
        let blob = blob(stmt, 1)
        let checkpoint = try CheckpointEnvelope.decoded(blob)
        return CursorSnapshot(
            metric: metric,
            epoch: checkpoint.epoch,
            anchorBlob: checkpoint.adapterAnchor
        )
    }

    func commitBatch(_ batch: PendingBatch, advancing: CursorAdvance) throws {
        let pending = try store.prepare(
            "INSERT INTO pending_batches (batch_id, payload_url, expected_records, byte_count) VALUES (?, ?, ?, ?) ON CONFLICT(batch_id) DO UPDATE SET payload_url = excluded.payload_url, expected_records = excluded.expected_records, byte_count = excluded.byte_count;"
        )
        defer { sqlite3_finalize(pending) }
        bindText(pending, 1, batch.id.rawValue)
        bindText(pending, 2, batch.payloadURL)
        sqlite3_bind_int64(pending, 3, sqlite3_int64(batch.expectedRecords))
        sqlite3_bind_int64(pending, 4, sqlite3_int64(batch.byteCount))
        try stepDone(pending)

        let snap = advancing.snapshot
        let envelope = CheckpointEnvelope(
            tzDatabaseVersion: advancing.tzDatabaseVersion,
            epoch: snap.epoch,
            adapterAnchor: snap.anchorBlob
        )
        let stmt = try store.prepare(
            "INSERT INTO cursors (metric, epoch, anchor) VALUES (?, ?, ?) ON CONFLICT(metric) DO UPDATE SET epoch = excluded.epoch, anchor = excluded.anchor;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, snap.metric.rawValue)
        sqlite3_bind_int64(stmt, 2, sqlite3_int64(snap.epoch))
        bindBlob(stmt, 3, envelope.encoded())
        try stepDone(stmt)
    }

    func pendingBatches() throws -> [PendingBatch] {
        let stmt = try store.prepare(
            "SELECT batch_id, payload_url, expected_records, byte_count FROM pending_batches ORDER BY rowid;"
        )
        defer { sqlite3_finalize(stmt) }
        var batches: [PendingBatch] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            batches.append(
                PendingBatch(
                    id: BatchID(rawValue: text(stmt, 0)),
                    payloadURL: text(stmt, 1),
                    expectedRecords: Int(sqlite3_column_int64(stmt, 2)),
                    byteCount: Int(sqlite3_column_int64(stmt, 3))
                )
            )
        }
        return batches
    }

    func queuedBytes() throws -> Int {
        let stmt = try store.prepare("SELECT COALESCE(SUM(byte_count), 0) FROM pending_batches;")
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    func loadGaps() throws -> [GapRecord] {
        let stmt = try store.prepare("SELECT batch_id, range_description FROM gaps ORDER BY rowid;")
        defer { sqlite3_finalize(stmt) }
        var gaps: [GapRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            gaps.append(
                GapRecord(
                    batchID: BatchID(rawValue: text(stmt, 0)),
                    rangeDescription: text(stmt, 1)
                )
            )
        }
        return gaps
    }

    func evict(_ batchID: BatchID, recording: GapRecord) throws {
        let delete = try store.prepare("DELETE FROM pending_batches WHERE batch_id = ?;")
        bindText(delete, 1, batchID.rawValue)
        do {
            try stepDone(delete)
            sqlite3_finalize(delete)
        } catch {
            sqlite3_finalize(delete)
            throw error
        }
        let stmt = try store.prepare(
            "INSERT INTO gaps (batch_id, range_description) VALUES (?, ?) ON CONFLICT(batch_id) DO UPDATE SET range_description = excluded.range_description;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, batchID.rawValue)
        bindText(stmt, 2, recording.rangeDescription)
        try stepDone(stmt)
    }

    func recordDelivery(_ receipt: DeliveryReceipt) throws {
        let stmt = try store.prepare(
            "INSERT INTO deliveries (batch_id, accepted) VALUES (?, ?) ON CONFLICT(batch_id) DO UPDATE SET accepted = excluded.accepted;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, receipt.batchID.rawValue)
        sqlite3_bind_int64(stmt, 2, sqlite3_int64(receipt.accepted))
        try stepDone(stmt)
        guard receipt.unconfirmed == 0 else { return }
        let delete = try store.prepare(
            "DELETE FROM pending_batches WHERE batch_id = ? AND expected_records <= ?;"
        )
        defer { sqlite3_finalize(delete) }
        bindText(delete, 1, receipt.batchID.rawValue)
        sqlite3_bind_int64(delete, 2, sqlite3_int64(receipt.accepted))
        try stepDone(delete)
    }

    func appendJournal(_ event: RunEvent) throws {
        let stmt = try store.prepare("INSERT INTO journal (run_id, outcome, detail) VALUES (?, ?, ?);")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, event.runID.rawValue)
        bindText(stmt, 2, event.outcomeKind)
        bindText(stmt, 3, event.detail)
        try stepDone(stmt)
    }

    func appendLedger(_ entry: EgressEntry) throws {
        let stmt = try store.prepare("INSERT INTO ledger (destination, sample_count, outcome) VALUES (?, ?, ?);")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, entry.destination)
        sqlite3_bind_int64(stmt, 2, sqlite3_int64(entry.sampleCount))
        bindText(stmt, 3, entry.outcomeKind)
        try stepDone(stmt)
    }

    func upsertCensus(_ row: CensusRow) throws {
        let stmt = try store.prepare(
            "INSERT INTO census (metric, day, sample_count, digest) VALUES (?, ?, ?, ?) ON CONFLICT(metric, day) DO UPDATE SET sample_count = excluded.sample_count, digest = excluded.digest;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, row.metric.rawValue)
        bindText(stmt, 2, row.day)
        sqlite3_bind_int64(stmt, 3, sqlite3_int64(row.sampleCount))
        bindText(stmt, 4, row.digest)
        try stepDone(stmt)
    }

    func loadCensus(metric: MetricID, day: String) throws -> CensusRow? {
        let stmt = try store.prepare(
            "SELECT sample_count, digest FROM census WHERE metric = ? AND day = ? LIMIT 1;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, metric.rawValue)
        bindText(stmt, 2, day)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let count = Int(sqlite3_column_int64(stmt, 0))
        let digest: String
        if let cStr = sqlite3_column_text(stmt, 1) {
            digest = String(cString: cStr)
        } else {
            digest = ""
        }
        return CensusRow(metric: metric, day: day, sampleCount: count, digest: digest)
    }

    func markDirty(metric: MetricID, day: String) throws {
        let stmt = try store.prepare("INSERT OR IGNORE INTO dirty (metric, day) VALUES (?, ?);")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, metric.rawValue)
        bindText(stmt, 2, day)
        try stepDone(stmt)
    }

    func dirtyDays(metric: MetricID) throws -> [String] {
        let stmt = try store.prepare("SELECT day FROM dirty WHERE metric = ? ORDER BY day;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, metric.rawValue)
        var days: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            days.append(String(cString: sqlite3_column_text(stmt, 0)))
        }
        return days
    }

    func upsertEmittedIndex(_ row: EmittedIndexRow) throws {
        let stmt = try store.prepare(
            "INSERT INTO emitted_index (uuid, metric, day, digest, batch_id) VALUES (?, ?, ?, ?, ?) ON CONFLICT(uuid) DO UPDATE SET metric = excluded.metric, day = excluded.day, digest = excluded.digest, batch_id = excluded.batch_id;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, row.uuid)
        bindText(stmt, 2, row.metric.rawValue)
        bindText(stmt, 3, row.day)
        bindText(stmt, 4, row.digest)
        bindText(stmt, 5, row.batchID.rawValue)
        try stepDone(stmt)
    }

    func loadEmittedIndex(uuid: String) throws -> EmittedIndexRow? {
        let stmt = try store.prepare(
            "SELECT metric, day, digest, batch_id FROM emitted_index WHERE uuid = ? LIMIT 1;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, uuid)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return EmittedIndexRow(
            uuid: uuid,
            metric: MetricID(rawValue: text(stmt, 0)),
            day: text(stmt, 1),
            digest: text(stmt, 2),
            batchID: BatchID(rawValue: text(stmt, 3))
        )
    }

    func removeEmittedIndex(uuid: String) throws {
        let stmt = try store.prepare("DELETE FROM emitted_index WHERE uuid = ?;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, uuid)
        try stepDone(stmt)
    }

    func loadEmittedIndex(metric: MetricID, day: String) throws -> [EmittedIndexRow] {
        let stmt = try store.prepare(
            "SELECT uuid, digest, batch_id FROM emitted_index WHERE metric = ? AND day = ? ORDER BY uuid;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, metric.rawValue)
        bindText(stmt, 2, day)
        var rows: [EmittedIndexRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(
                EmittedIndexRow(
                    uuid: text(stmt, 0),
                    metric: metric,
                    day: day,
                    digest: text(stmt, 1),
                    batchID: BatchID(rawValue: text(stmt, 2))
                )
            )
        }
        return rows
    }

    private func bindText(_ stmt: OpaquePointer, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, sqliteTransient)
    }

    private func bindBlob(_ stmt: OpaquePointer, _ index: Int32, _ data: Data) {
        data.withUnsafeBytes { raw in
            _ = sqlite3_bind_blob(stmt, index, raw.baseAddress, Int32(data.count), sqliteTransient)
        }
    }

    private func blob(_ stmt: OpaquePointer, _ index: Int32) -> Data {
        guard let ptr = sqlite3_column_blob(stmt, index) else { return Data() }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return Data(bytes: ptr, count: count)
    }

    private func text(_ stmt: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: value)
    }

    private func stepDone(_ stmt: OpaquePointer) throws {
        let status = sqlite3_step(stmt)
        guard status == SQLITE_DONE else {
            throw StorageError.execFailed("step \(status)")
        }
    }
}
