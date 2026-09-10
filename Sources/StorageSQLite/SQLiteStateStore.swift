import CoreDomain
import CSQLite
import EnginePorts
import Foundation
import RunJournal

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
        for sql in [
            "ALTER TABLE pending_batches ADD COLUMN byte_count INTEGER NOT NULL DEFAULT 0;",
            "ALTER TABLE pending_batches ADD COLUMN metric TEXT NOT NULL DEFAULT '';",
            "ALTER TABLE pending_batches ADD COLUMN created_at_epoch REAL;",
            "ALTER TABLE pending_batches ADD COLUMN range_start_day TEXT;",
            "ALTER TABLE pending_batches ADD COLUMN range_end_day TEXT;",
            "ALTER TABLE gaps ADD COLUMN metric TEXT NOT NULL DEFAULT '';",
            "ALTER TABLE gaps ADD COLUMN range_start_day TEXT;",
            "ALTER TABLE gaps ADD COLUMN range_end_day TEXT;",
            "ALTER TABLE journal ADD COLUMN trigger TEXT NOT NULL DEFAULT 'manual';",
            "ALTER TABLE journal ADD COLUMN samples_read INTEGER NOT NULL DEFAULT 0;",
            "ALTER TABLE journal ADD COLUMN samples_committed INTEGER NOT NULL DEFAULT 0;",
            "ALTER TABLE journal ADD COLUMN samples_acked INTEGER NOT NULL DEFAULT 0;",
            "ALTER TABLE ledger ADD COLUMN sequence INTEGER NOT NULL DEFAULT 0;",
            "ALTER TABLE ledger ADD COLUMN previous_hash TEXT NOT NULL DEFAULT '';",
            "ALTER TABLE ledger ADD COLUMN entry_hash TEXT NOT NULL DEFAULT '';",
            "ALTER TABLE ledger ADD COLUMN byte_count INTEGER NOT NULL DEFAULT 0;",
            "ALTER TABLE ledger ADD COLUMN detail TEXT NOT NULL DEFAULT '';",
            "ALTER TABLE ledger ADD COLUMN wall_time_epoch REAL NOT NULL DEFAULT 0;",
            "ALTER TABLE type_status ADD COLUMN generation INTEGER NOT NULL DEFAULT 1;",
            "ALTER TABLE journal ADD COLUMN wall_time_epoch REAL NOT NULL DEFAULT 0;",
            "ALTER TABLE journal ADD COLUMN error_class TEXT;",
        ] {
            do { try exec(sql) } catch { _ = error }
        }
        try migrateLedgerChain()
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
                detail TEXT NOT NULL,
                trigger TEXT NOT NULL DEFAULT 'manual',
                samples_read INTEGER NOT NULL DEFAULT 0,
                samples_committed INTEGER NOT NULL DEFAULT 0,
                samples_acked INTEGER NOT NULL DEFAULT 0,
                wall_time_epoch REAL NOT NULL DEFAULT 0,
                error_class TEXT
            );
            CREATE TABLE IF NOT EXISTS ledger (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                destination TEXT NOT NULL,
                sample_count INTEGER NOT NULL,
                outcome TEXT NOT NULL,
                sequence INTEGER NOT NULL DEFAULT 0,
                previous_hash TEXT NOT NULL DEFAULT '',
                entry_hash TEXT NOT NULL DEFAULT '',
                byte_count INTEGER NOT NULL DEFAULT 0,
                detail TEXT NOT NULL DEFAULT '',
                wall_time_epoch REAL NOT NULL DEFAULT 0
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
                byte_count INTEGER NOT NULL DEFAULT 0,
                metric TEXT NOT NULL DEFAULT '',
                created_at_epoch REAL,
                range_start_day TEXT,
                range_end_day TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_pending_metric ON pending_batches (metric);
            CREATE TABLE IF NOT EXISTS deliveries (
                batch_id TEXT PRIMARY KEY,
                accepted INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS gaps (
                batch_id TEXT PRIMARY KEY,
                range_description TEXT NOT NULL,
                metric TEXT NOT NULL DEFAULT '',
                range_start_day TEXT,
                range_end_day TEXT
            );
            CREATE TABLE IF NOT EXISTS emitted_index (
                uuid TEXT PRIMARY KEY,
                metric TEXT NOT NULL,
                day TEXT NOT NULL,
                digest TEXT NOT NULL,
                batch_id TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_emitted_metric_day ON emitted_index (metric, day);
            CREATE TABLE IF NOT EXISTS aggregate_emit (
                bucket_key TEXT PRIMARY KEY,
                emit_seq INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS type_status (
                metric TEXT PRIMARY KEY,
                disabled INTEGER NOT NULL,
                reason TEXT NOT NULL,
                generation INTEGER NOT NULL DEFAULT 1
            );
            CREATE TABLE IF NOT EXISTS backfill_checkpoints (
                job_id TEXT PRIMARY KEY,
                payload BLOB NOT NULL
            );
            PRAGMA user_version = 10;
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

    public func wipe(atEpoch: TimeInterval) async throws {
        let urls = try await transact { try $0.wipe(atEpoch: atEpoch) }
        for path in urls {
            try? FileManager.default.removeItem(atPath: path)
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

    private func migrateLedgerChain() throws {
        let tx = SQLiteTransaction(store: self)
        let entries = try tx.loadLedger()
        guard entries.contains(where: { $0.sequence == 0 || $0.entryHash.isEmpty }) else {
            return
        }
        try exec("DELETE FROM ledger;")
        for entry in entries {
            try tx.appendLedger(
                EgressEntry(
                    destination: entry.destination,
                    sampleCount: entry.sampleCount,
                    outcomeKind: entry.outcomeKind,
                    byteCount: entry.byteCount,
                    detail: entry.detail,
                    wallTimeEpoch: entry.wallTimeEpoch
                )
            )
        }
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

    func loadBackfillCheckpoint(jobID: String) throws -> Data? {
        let stmt = try store.prepare(
            "SELECT payload FROM backfill_checkpoints WHERE job_id = ? LIMIT 1;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, jobID)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return blob(stmt, 0)
    }

    func upsertBackfillCheckpoint(jobID: String, bytes: Data) throws {
        let stmt = try store.prepare(
            "INSERT INTO backfill_checkpoints (job_id, payload) VALUES (?, ?) ON CONFLICT(job_id) DO UPDATE SET payload = excluded.payload;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, jobID)
        bindBlob(stmt, 2, bytes)
        try stepDone(stmt)
    }

    func enqueuePending(_ batch: PendingBatch) throws {
        let pending = try store.prepare(
            "INSERT INTO pending_batches (batch_id, payload_url, expected_records, byte_count, metric, created_at_epoch, range_start_day, range_end_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(batch_id) DO UPDATE SET payload_url = excluded.payload_url, expected_records = excluded.expected_records, byte_count = excluded.byte_count, metric = excluded.metric, created_at_epoch = COALESCE(pending_batches.created_at_epoch, excluded.created_at_epoch), range_start_day = excluded.range_start_day, range_end_day = excluded.range_end_day;"
        )
        defer { sqlite3_finalize(pending) }
        bindText(pending, 1, batch.id.rawValue)
        bindText(pending, 2, batch.payloadURL)
        sqlite3_bind_int64(pending, 3, sqlite3_int64(batch.expectedRecords))
        sqlite3_bind_int64(pending, 4, sqlite3_int64(batch.byteCount))
        bindText(pending, 5, batch.metric.rawValue)
        if let createdAtEpoch = batch.createdAtEpoch {
            sqlite3_bind_double(pending, 6, createdAtEpoch)
        } else {
            sqlite3_bind_null(pending, 6)
        }
        bindOptionalText(pending, 7, batch.rangeStartDay)
        bindOptionalText(pending, 8, batch.rangeEndDay)
        try stepDone(pending)
    }

    func commitBatch(_ batch: PendingBatch, advancing: CursorAdvance) throws {
        try enqueuePending(batch)

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
            "SELECT batch_id, payload_url, expected_records, byte_count, metric, created_at_epoch, range_start_day, range_end_day FROM pending_batches ORDER BY rowid;"
        )
        defer { sqlite3_finalize(stmt) }
        var batches: [PendingBatch] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            batches.append(
                PendingBatch(
                    id: BatchID(rawValue: text(stmt, 0)),
                    payloadURL: text(stmt, 1),
                    expectedRecords: Int(sqlite3_column_int64(stmt, 2)),
                    byteCount: Int(sqlite3_column_int64(stmt, 3)),
                    metric: MetricID(rawValue: text(stmt, 4)),
                    createdAtEpoch: sqlite3_column_type(stmt, 5) == SQLITE_NULL
                        ? nil
                        : sqlite3_column_double(stmt, 5),
                    rangeStartDay: optionalText(stmt, 6),
                    rangeEndDay: optionalText(stmt, 7)
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
        let stmt = try store.prepare(
            "SELECT batch_id, range_description, metric, range_start_day, range_end_day FROM gaps ORDER BY rowid;"
        )
        defer { sqlite3_finalize(stmt) }
        var gaps: [GapRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            gaps.append(
                GapRecord(
                    batchID: BatchID(rawValue: text(stmt, 0)),
                    rangeDescription: text(stmt, 1),
                    metric: MetricID(rawValue: text(stmt, 2)),
                    rangeStartDay: optionalText(stmt, 3),
                    rangeEndDay: optionalText(stmt, 4)
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
            "INSERT INTO gaps (batch_id, range_description, metric, range_start_day, range_end_day) VALUES (?, ?, ?, ?, ?) ON CONFLICT(batch_id) DO UPDATE SET range_description = excluded.range_description, metric = excluded.metric, range_start_day = excluded.range_start_day, range_end_day = excluded.range_end_day;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, batchID.rawValue)
        bindText(stmt, 2, recording.rangeDescription)
        bindText(stmt, 3, recording.metric.rawValue)
        bindOptionalText(stmt, 4, recording.rangeStartDay)
        bindOptionalText(stmt, 5, recording.rangeEndDay)
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
        let stmt = try store.prepare(
            "INSERT INTO journal (run_id, outcome, detail, trigger, samples_read, samples_committed, samples_acked, wall_time_epoch, error_class) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, event.runID.rawValue)
        bindText(stmt, 2, event.outcomeKind)
        bindText(stmt, 3, event.detail)
        bindText(stmt, 4, event.trigger.rawValue)
        sqlite3_bind_int64(stmt, 5, sqlite3_int64(event.samplesRead))
        sqlite3_bind_int64(stmt, 6, sqlite3_int64(event.samplesCommitted))
        sqlite3_bind_int64(stmt, 7, sqlite3_int64(event.samplesAcked))
        sqlite3_bind_double(stmt, 8, event.wallTimeEpoch)
        if let errorClass = event.errorClass {
            bindText(stmt, 9, errorClass)
        } else {
            sqlite3_bind_null(stmt, 9)
        }
        try stepDone(stmt)
    }

    func appendLedger(_ entry: EgressEntry) throws {
        let head = try ledgerHead()
        let sealed = LedgerChain.seal(
            entry,
            sequence: head.sequence + 1,
            previousHash: head.hash
        )
        let stmt = try store.prepare(
            "INSERT INTO ledger (destination, sample_count, outcome, sequence, previous_hash, entry_hash, byte_count, detail, wall_time_epoch) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, sealed.destination)
        sqlite3_bind_int64(stmt, 2, sqlite3_int64(sealed.sampleCount))
        bindText(stmt, 3, sealed.outcomeKind)
        sqlite3_bind_int64(stmt, 4, sqlite3_int64(sealed.sequence))
        bindText(stmt, 5, sealed.previousHash)
        bindText(stmt, 6, sealed.entryHash)
        sqlite3_bind_int64(stmt, 7, sqlite3_int64(sealed.byteCount))
        bindText(stmt, 8, sealed.detail)
        sqlite3_bind_double(stmt, 9, sealed.wallTimeEpoch)
        try stepDone(stmt)
    }

    private func ledgerHead() throws -> (sequence: Int, hash: String) {
        let stmt = try store.prepare(
            "SELECT sequence, entry_hash FROM ledger ORDER BY id DESC LIMIT 1;"
        )
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return (0, LedgerChain.genesisHash)
        }
        return (Int(sqlite3_column_int64(stmt, 0)), text(stmt, 1))
    }

    func loadLedger() throws -> [EgressEntry] {
        let stmt = try store.prepare(
            "SELECT destination, sample_count, outcome, sequence, previous_hash, entry_hash, byte_count, detail, wall_time_epoch FROM ledger ORDER BY id;"
        )
        defer { sqlite3_finalize(stmt) }
        var entries: [EgressEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            entries.append(
                EgressEntry(
                    destination: text(stmt, 0),
                    sampleCount: Int(sqlite3_column_int64(stmt, 1)),
                    outcomeKind: text(stmt, 2),
                    byteCount: Int(sqlite3_column_int64(stmt, 6)),
                    detail: text(stmt, 7),
                    wallTimeEpoch: sqlite3_column_double(stmt, 8),
                    sequence: Int(sqlite3_column_int64(stmt, 3)),
                    previousHash: text(stmt, 4),
                    entryHash: text(stmt, 5)
                )
            )
        }
        return entries
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

    func clearDirty(metric: MetricID, day: String) throws {
        let stmt = try store.prepare("DELETE FROM dirty WHERE metric = ? AND day = ?;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, metric.rawValue)
        bindText(stmt, 2, day)
        try stepDone(stmt)
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

    func loadAggregateEmitSeq(bucketKey: String) throws -> Int? {
        let stmt = try store.prepare(
            "SELECT emit_seq FROM aggregate_emit WHERE bucket_key = ? LIMIT 1;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, bucketKey)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    func upsertAggregateEmitSeq(bucketKey: String, emitSeq: Int) throws {
        let stmt = try store.prepare(
            "INSERT INTO aggregate_emit (bucket_key, emit_seq) VALUES (?, ?) ON CONFLICT(bucket_key) DO UPDATE SET emit_seq = excluded.emit_seq;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, bucketKey)
        sqlite3_bind_int64(stmt, 2, sqlite3_int64(emitSeq))
        try stepDone(stmt)
    }

    func loadJournal() throws -> [RunEvent] {
        let stmt = try store.prepare(
            "SELECT run_id, outcome, detail, trigger, samples_read, samples_committed, samples_acked, wall_time_epoch, error_class FROM journal ORDER BY id;"
        )
        defer { sqlite3_finalize(stmt) }
        var events: [RunEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            events.append(
                RunEvent(
                    runID: RunID(rawValue: text(stmt, 0)),
                    outcomeKind: text(stmt, 1),
                    detail: text(stmt, 2),
                    trigger: RunTrigger(rawValue: text(stmt, 3)) ?? .manual,
                    samplesRead: Int(sqlite3_column_int64(stmt, 4)),
                    samplesCommitted: Int(sqlite3_column_int64(stmt, 5)),
                    samplesAcked: Int(sqlite3_column_int64(stmt, 6)),
                    wallTimeEpoch: sqlite3_column_double(stmt, 7),
                    errorClass: sqlite3_column_type(stmt, 8) == SQLITE_NULL
                        ? nil
                        : text(stmt, 8)
                )
            )
        }
        return events
    }

    func loadTypeStatus(metric: MetricID) throws -> TypeStatus? {
        let stmt = try store.prepare(
            "SELECT disabled, reason, generation FROM type_status WHERE metric = ? LIMIT 1;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, metric.rawValue)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return TypeStatus(
            metric: metric,
            disabled: sqlite3_column_int64(stmt, 0) != 0,
            reason: text(stmt, 1),
            generation: UInt32(clamping: sqlite3_column_int64(stmt, 2))
        )
    }

    func upsertTypeStatus(_ status: TypeStatus) throws {
        let stmt = try store.prepare(
            "INSERT INTO type_status (metric, disabled, reason, generation) VALUES (?, ?, ?, ?) ON CONFLICT(metric) DO UPDATE SET disabled = excluded.disabled, reason = excluded.reason, generation = excluded.generation;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, status.metric.rawValue)
        sqlite3_bind_int64(stmt, 2, status.disabled ? 1 : 0)
        bindText(stmt, 3, status.reason)
        sqlite3_bind_int64(stmt, 4, Int64(status.generation))
        try stepDone(stmt)
    }

    func purgeMetricState(metric: MetricID) throws {
        for table in ["cursors", "census", "dirty", "emitted_index"] {
            let stmt = try store.prepare("DELETE FROM \(table) WHERE metric = ?;")
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, metric.rawValue)
            try stepDone(stmt)
        }
    }

    func wipe(atEpoch: TimeInterval) throws -> [String] {
        let stmt = try store.prepare("SELECT payload_url FROM pending_batches;")
        defer { sqlite3_finalize(stmt) }
        var urls: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            urls.append(text(stmt, 0))
        }
        let ledger = try loadLedger()
        let destroyedCount = ledger.count
        let previousHead = ledger.last?.entryHash ?? LedgerChain.genesisHash
        for table in [
            "journal", "ledger", "cursors", "census", "dirty", "pending_batches",
            "deliveries", "gaps", "emitted_index", "aggregate_emit", "type_status",
            "backfill_checkpoints",
        ] {
            try store.exec("DELETE FROM \(table);")
        }
        try appendLedger(
            EgressEntry(
                destination: "local-device",
                sampleCount: 0,
                outcomeKind: "genesis_after_wipe",
                detail: "destroyed_count=\(destroyedCount) previous_head=\(previousHead)",
                wallTimeEpoch: atEpoch
            )
        )
        return urls
    }

    private func bindText(_ stmt: OpaquePointer, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, sqliteTransient)
    }

    private func bindOptionalText(
        _ stmt: OpaquePointer,
        _ index: Int32,
        _ value: String?
    ) {
        if let value {
            bindText(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
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

    private func optionalText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return text(stmt, index)
    }

    private func stepDone(_ stmt: OpaquePointer) throws {
        let status = sqlite3_step(stmt)
        guard status == SQLITE_DONE else {
            throw StorageError.execFailed("step \(status)")
        }
    }
}
