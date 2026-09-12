// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

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
            "ALTER TABLE pending_batches ADD COLUMN eviction_class TEXT NOT NULL DEFAULT 'normal';",
            "ALTER TABLE gaps ADD COLUMN metric TEXT NOT NULL DEFAULT '';",
            "ALTER TABLE gaps ADD COLUMN range_start_day TEXT;",
            "ALTER TABLE gaps ADD COLUMN range_end_day TEXT;",
            "ALTER TABLE gaps ADD COLUMN expected_records INTEGER NOT NULL DEFAULT 0;",
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
            "ALTER TABLE journal ADD COLUMN projected_at_epoch REAL;",
            "ALTER TABLE journal ADD COLUMN history_facts TEXT;",
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
                error_class TEXT,
                projected_at_epoch REAL,
                history_facts TEXT
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
                range_end_day TEXT,
                eviction_class TEXT NOT NULL DEFAULT 'normal'
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
                range_end_day TEXT,
                expected_records INTEGER NOT NULL DEFAULT 0
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
            CREATE TABLE IF NOT EXISTS anchor_holds (
                metric TEXT PRIMARY KEY,
                reason TEXT NOT NULL,
                detected_at_epoch REAL NOT NULL,
                observed_samples INTEGER NOT NULL DEFAULT 0,
                last_emitted_day TEXT,
                decision TEXT
            );
            CREATE TABLE IF NOT EXISTS destination_scopes (
                destination_id TEXT PRIMARY KEY,
                payload BLOB NOT NULL
            );
            CREATE TABLE IF NOT EXISTS freshness_latencies (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                run_id TEXT NOT NULL,
                destination_id TEXT NOT NULL,
                freshness_class TEXT NOT NULL,
                first_observed_at_epoch REAL NOT NULL,
                observation_latency_seconds REAL NOT NULL,
                delivery_latency_seconds REAL NOT NULL,
                recorded_at_epoch REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_freshness_destination_class
                ON freshness_latencies (destination_id, freshness_class, recorded_at_epoch);
            CREATE TABLE IF NOT EXISTS state_meta (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS open_runs (
                destination_id TEXT NOT NULL,
                metric TEXT NOT NULL,
                phase TEXT NOT NULL,
                trigger TEXT NOT NULL,
                started_at_epoch REAL NOT NULL,
                samples_read INTEGER NOT NULL DEFAULT 0,
                samples_committed INTEGER NOT NULL DEFAULT 0,
                samples_acked INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (destination_id, metric)
            );
            PRAGMA user_version = 18;
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

    /// I6 Red: reclaim WAL pages without dropping live pending batches.
    public func checkpointWAL() throws {
        try exec("PRAGMA wal_checkpoint(TRUNCATE);")
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

    #if DEBUG
    public func tamperLedgerSampleCountForTesting(sequence: Int, sampleCount: Int) throws {
        try exec(
            "UPDATE ledger SET sample_count = \(sampleCount) WHERE sequence = \(sequence);"
        )
    }
    #endif
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
            "INSERT INTO pending_batches (batch_id, payload_url, expected_records, byte_count, metric, created_at_epoch, range_start_day, range_end_day, eviction_class) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(batch_id) DO UPDATE SET payload_url = excluded.payload_url, expected_records = excluded.expected_records, byte_count = excluded.byte_count, metric = excluded.metric, created_at_epoch = COALESCE(pending_batches.created_at_epoch, excluded.created_at_epoch), range_start_day = excluded.range_start_day, range_end_day = excluded.range_end_day, eviction_class = excluded.eviction_class;"
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
        bindText(pending, 9, batch.evictionClass.rawValue)
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
            "SELECT batch_id, payload_url, expected_records, byte_count, metric, created_at_epoch, range_start_day, range_end_day, eviction_class FROM pending_batches ORDER BY rowid;"
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
                    rangeEndDay: optionalText(stmt, 7),
                    evictionClass: QueueEvictionClass(rawValue: text(stmt, 8)) ?? .normal
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
            "SELECT batch_id, range_description, metric, range_start_day, range_end_day, expected_records FROM gaps ORDER BY rowid;"
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
                    rangeEndDay: optionalText(stmt, 4),
                    expectedRecords: Int(sqlite3_column_int64(stmt, 5))
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
            "INSERT INTO gaps (batch_id, range_description, metric, range_start_day, range_end_day, expected_records) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(batch_id) DO UPDATE SET range_description = excluded.range_description, metric = excluded.metric, range_start_day = excluded.range_start_day, range_end_day = excluded.range_end_day, expected_records = excluded.expected_records;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, batchID.rawValue)
        bindText(stmt, 2, recording.rangeDescription)
        bindText(stmt, 3, recording.metric.rawValue)
        bindOptionalText(stmt, 4, recording.rangeStartDay)
        bindOptionalText(stmt, 5, recording.rangeEndDay)
        sqlite3_bind_int64(stmt, 6, sqlite3_int64(recording.expectedRecords))
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

    func deliveredAccepted() throws -> Int {
        let stmt = try store.prepare("SELECT COALESCE(SUM(accepted), 0) FROM deliveries;")
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    func appendJournal(_ event: RunEvent) throws {
        let stmt = try store.prepare(
            "INSERT INTO journal (run_id, outcome, detail, trigger, samples_read, samples_committed, samples_acked, wall_time_epoch, error_class, projected_at_epoch, history_facts) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);"
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
        if let projected = event.projectedAtEpoch {
            sqlite3_bind_double(stmt, 10, projected)
        } else {
            sqlite3_bind_null(stmt, 10)
        }
        bindOptionalText(stmt, 11, event.facts.jsonString())
        try stepDone(stmt)
        // OBS-02: enforced here because this is the one place every journal row goes
        // through. Six call sites across the engine append runs, census records, queue
        // expiries and type purges; a sweep any of them had to remember to call is a
        // sweep that eventually does not get called.
        _ = try pruneJournal(
            sinceEpoch: newestJournalEpoch() - JournalRetention.seconds,
            maximumRuns: JournalRetention.runs
        )
    }

    func upsertOpenRun(_ run: OpenRun) throws {
        let stmt = try store.prepare(
            """
            INSERT INTO open_runs (
                destination_id, metric, phase, trigger, started_at_epoch,
                samples_read, samples_committed, samples_acked
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(destination_id, metric) DO UPDATE SET
                phase = excluded.phase,
                trigger = excluded.trigger,
                started_at_epoch = excluded.started_at_epoch,
                samples_read = excluded.samples_read,
                samples_committed = excluded.samples_committed,
                samples_acked = excluded.samples_acked;
            """
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, run.destinationID)
        bindText(stmt, 2, run.metric.rawValue)
        bindText(stmt, 3, run.phase)
        bindText(stmt, 4, run.trigger.rawValue)
        sqlite3_bind_double(stmt, 5, run.startedAtEpoch)
        sqlite3_bind_int64(stmt, 6, sqlite3_int64(run.samplesRead))
        sqlite3_bind_int64(stmt, 7, sqlite3_int64(run.samplesCommitted))
        sqlite3_bind_int64(stmt, 8, sqlite3_int64(run.samplesAcked))
        try stepDone(stmt)
    }

    func loadOpenRuns() throws -> [OpenRun] {
        let stmt = try store.prepare(
            """
            SELECT destination_id, metric, phase, trigger, started_at_epoch,
                   samples_read, samples_committed, samples_acked
            FROM open_runs
            ORDER BY started_at_epoch, destination_id, metric;
            """
        )
        defer { sqlite3_finalize(stmt) }
        var rows: [OpenRun] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(
                OpenRun(
                    destinationID: text(stmt, 0),
                    metric: MetricID(rawValue: text(stmt, 1)),
                    phase: text(stmt, 2),
                    trigger: RunTrigger(rawValue: text(stmt, 3)) ?? .manual,
                    startedAtEpoch: sqlite3_column_double(stmt, 4),
                    samplesRead: Int(sqlite3_column_int64(stmt, 5)),
                    samplesCommitted: Int(sqlite3_column_int64(stmt, 6)),
                    samplesAcked: Int(sqlite3_column_int64(stmt, 7))
                )
            )
        }
        return rows
    }

    func closeOpenRun(destinationID: String, metric: MetricID) throws {
        let stmt = try store.prepare(
            "DELETE FROM open_runs WHERE destination_id = ? AND metric = ?;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, destinationID)
        bindText(stmt, 2, metric.rawValue)
        try stepDone(stmt)
    }

    func appendFreshnessLatency(_ observation: RunFreshnessLatency) throws {
        let stmt = try store.prepare(
            """
            INSERT INTO freshness_latencies (
                run_id, destination_id, freshness_class, first_observed_at_epoch,
                observation_latency_seconds, delivery_latency_seconds, recorded_at_epoch
            ) VALUES (?, ?, ?, ?, ?, ?, ?);
            """
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, observation.runID.rawValue)
        bindText(stmt, 2, observation.destinationID)
        bindText(stmt, 3, observation.freshnessClass.rawValue)
        sqlite3_bind_double(stmt, 4, observation.firstObservedAtEpoch)
        sqlite3_bind_double(stmt, 5, observation.observationLatencySeconds)
        sqlite3_bind_double(stmt, 6, observation.deliveryLatencySeconds)
        sqlite3_bind_double(stmt, 7, observation.recordedAtEpoch)
        try stepDone(stmt)

        let prune = try store.prepare(
            """
            DELETE FROM freshness_latencies
            WHERE destination_id = ? AND freshness_class = ?
              AND id NOT IN (
                SELECT id FROM freshness_latencies
                WHERE destination_id = ? AND freshness_class = ?
                ORDER BY id DESC LIMIT 10000
              );
            """
        )
        defer { sqlite3_finalize(prune) }
        bindText(prune, 1, observation.destinationID)
        bindText(prune, 2, observation.freshnessClass.rawValue)
        bindText(prune, 3, observation.destinationID)
        bindText(prune, 4, observation.freshnessClass.rawValue)
        try stepDone(prune)
    }

    func loadFreshnessLatencies(
        destinationID: String,
        freshnessClass: FreshnessClass
    ) throws -> [RunFreshnessLatency] {
        let stmt = try store.prepare(
            """
            SELECT run_id, first_observed_at_epoch, observation_latency_seconds,
                   delivery_latency_seconds, recorded_at_epoch
            FROM freshness_latencies
            WHERE destination_id = ? AND freshness_class = ?
            ORDER BY recorded_at_epoch, id;
            """
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, destinationID)
        bindText(stmt, 2, freshnessClass.rawValue)
        var observations: [RunFreshnessLatency] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let observation = RunFreshnessLatency(
                runID: RunID(rawValue: text(stmt, 0)),
                destinationID: destinationID,
                freshnessClass: freshnessClass,
                firstObservedAtEpoch: sqlite3_column_double(stmt, 1),
                observationLatencySeconds: sqlite3_column_double(stmt, 2),
                deliveryLatencySeconds: sqlite3_column_double(stmt, 3),
                recordedAtEpoch: sqlite3_column_double(stmt, 4)
            ) else {
                continue
            }
            observations.append(observation)
        }
        return observations
    }

    /// The table's own newest row rather than the wall clock: retention then stays
    /// deterministic under test and cannot be moved by a device whose clock jumped.
    private func newestJournalEpoch() throws -> TimeInterval {
        let stmt = try store.prepare("SELECT MAX(wall_time_epoch) FROM journal;")
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return sqlite3_column_double(stmt, 0)
    }

    func pruneJournal(sinceEpoch: TimeInterval, maximumRuns: Int) throws -> Int {
        var removed = 0

        let byAge = try store.prepare("DELETE FROM journal WHERE wall_time_epoch < ?;")
        defer { sqlite3_finalize(byAge) }
        sqlite3_bind_double(byAge, 1, sinceEpoch)
        try stepDone(byAge)
        removed += Int(sqlite3_changes(store.db))

        // `id` is the insertion order, so the newest rows are the highest ids. Offset
        // rather than a count keeps this one statement regardless of table size.
        let byCount = try store.prepare(
            """
            DELETE FROM journal WHERE id NOT IN (
                SELECT id FROM journal ORDER BY id DESC LIMIT ?
            );
            """
        )
        defer { sqlite3_finalize(byCount) }
        sqlite3_bind_int64(byCount, 1, sqlite3_int64(max(0, maximumRuns)))
        try stepDone(byCount)
        removed += Int(sqlite3_changes(store.db))

        return removed
    }

    func unprojectedJournal(limit: Int) throws -> [RunEvent] {
        let stmt = try store.prepare(
            "SELECT run_id, outcome, detail, trigger, samples_read, samples_committed, samples_acked, wall_time_epoch, error_class, projected_at_epoch, history_facts FROM journal WHERE projected_at_epoch IS NULL ORDER BY id LIMIT ?;"
        )
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, sqlite3_int64(max(0, limit)))
        return try readJournalRows(stmt)
    }

    func markJournalProjected(runIDs: [RunID], atEpoch: TimeInterval) throws {
        for runID in runIDs {
            let stmt = try store.prepare(
                "UPDATE journal SET projected_at_epoch = ? WHERE run_id = ? AND projected_at_epoch IS NULL;"
            )
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, atEpoch)
            bindText(stmt, 2, runID.rawValue)
            try stepDone(stmt)
        }
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

    func loadCensusDays(metric: MetricID) throws -> [String] {
        let stmt = try store.prepare(
            "SELECT day FROM census WHERE metric = ? ORDER BY day;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, metric.rawValue)
        var days: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            days.append(String(cString: sqlite3_column_text(stmt, 0)))
        }
        return days
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

    func latestEmittedDay(metric: MetricID) throws -> String? {
        let stmt = try store.prepare(
            "SELECT day FROM emitted_index WHERE metric = ? ORDER BY day DESC LIMIT 1;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, metric.rawValue)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return text(stmt, 0)
    }

    func emittedIndexRowCount() throws -> Int {
        let stmt = try store.prepare("SELECT COUNT(*) FROM emitted_index;")
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    func oldestEvictableEmittedDay(excluding metrics: Set<MetricID>) throws -> String? {
        try emittedIndexMinDay(excluding: metrics)
    }

    func emittedIndexMetrics(day: String, excluding metrics: Set<MetricID>) throws -> [MetricID] {
        let listed = metrics.sorted { $0.rawValue < $1.rawValue }
        let sql: String
        if listed.isEmpty {
            sql = "SELECT DISTINCT metric FROM emitted_index WHERE day = ? ORDER BY metric;"
        } else {
            let placeholders = Array(repeating: "?", count: listed.count).joined(separator: ",")
            sql = "SELECT DISTINCT metric FROM emitted_index WHERE day = ? AND metric NOT IN (\(placeholders)) ORDER BY metric;"
        }
        let stmt = try store.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, day)
        for (offset, metric) in listed.enumerated() {
            bindText(stmt, Int32(offset + 2), metric.rawValue)
        }
        var ids: [MetricID] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            ids.append(MetricID(rawValue: text(stmt, 0)))
        }
        return ids
    }

    func removeEmittedIndex(day: String, excluding metrics: Set<MetricID>) throws {
        let listed = metrics.sorted { $0.rawValue < $1.rawValue }
        let sql: String
        if listed.isEmpty {
            sql = "DELETE FROM emitted_index WHERE day = ?;"
        } else {
            let placeholders = Array(repeating: "?", count: listed.count).joined(separator: ",")
            sql = "DELETE FROM emitted_index WHERE day = ? AND metric NOT IN (\(placeholders));"
        }
        let stmt = try store.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, day)
        for (offset, metric) in listed.enumerated() {
            bindText(stmt, Int32(offset + 2), metric.rawValue)
        }
        try stepDone(stmt)
    }

    func emittedIndexHorizonDay(excluding metrics: Set<MetricID>) throws -> String? {
        try emittedIndexMinDay(excluding: metrics)
    }

    func loadIndexHorizonDay() throws -> String? {
        try loadStateMeta("indexHorizonDay")
    }

    func upsertIndexHorizonDay(_ day: String) throws {
        try upsertStateMeta("indexHorizonDay", value: day)
    }

    func loadVerifiedThroughDay(metric: MetricID) throws -> String? {
        try loadStateMeta("verifiedThrough:\(metric.rawValue)")
    }

    func clampVerifiedThroughDay(metric: MetricID, horizonDay: String) throws {
        let key = "verifiedThrough:\(metric.rawValue)"
        if let current = try loadStateMeta(key) {
            try upsertStateMeta(key, value: current < horizonDay ? current : horizonDay)
        } else {
            try upsertStateMeta(key, value: horizonDay)
        }
    }

    private func emittedIndexMinDay(excluding metrics: Set<MetricID>) throws -> String? {
        let listed = metrics.sorted { $0.rawValue < $1.rawValue }
        let sql: String
        if listed.isEmpty {
            sql = "SELECT MIN(day) FROM emitted_index;"
        } else {
            let placeholders = Array(repeating: "?", count: listed.count).joined(separator: ",")
            sql = "SELECT MIN(day) FROM emitted_index WHERE metric NOT IN (\(placeholders));"
        }
        let stmt = try store.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        for (offset, metric) in listed.enumerated() {
            bindText(stmt, Int32(offset + 1), metric.rawValue)
        }
        guard sqlite3_step(stmt) == SQLITE_ROW, sqlite3_column_type(stmt, 0) != SQLITE_NULL else {
            return nil
        }
        return text(stmt, 0)
    }

    private func loadStateMeta(_ key: String) throws -> String? {
        let stmt = try store.prepare("SELECT value FROM state_meta WHERE key = ? LIMIT 1;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, key)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return text(stmt, 0)
    }

    private func upsertStateMeta(_ key: String, value: String) throws {
        let stmt = try store.prepare(
            "INSERT INTO state_meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, key)
        bindText(stmt, 2, value)
        try stepDone(stmt)
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
            "SELECT run_id, outcome, detail, trigger, samples_read, samples_committed, samples_acked, wall_time_epoch, error_class, projected_at_epoch, history_facts FROM journal ORDER BY id;"
        )
        defer { sqlite3_finalize(stmt) }
        return try readJournalRows(stmt)
    }

    private func readJournalRows(_ stmt: OpaquePointer) throws -> [RunEvent] {
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
                        : text(stmt, 8),
                    projectedAtEpoch: sqlite3_column_type(stmt, 9) == SQLITE_NULL
                        ? nil
                        : sqlite3_column_double(stmt, 9),
                    facts: RunHistoryFacts.decode(
                        sqlite3_column_type(stmt, 10) == SQLITE_NULL
                            ? nil
                            : text(stmt, 10)
                    )
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

    func loadAnchorHold(metric: MetricID) throws -> AnchorHold? {
        let stmt = try store.prepare(
            "SELECT reason, detected_at_epoch, observed_samples, last_emitted_day, decision FROM anchor_holds WHERE metric = ? LIMIT 1;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, metric.rawValue)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return hold(from: stmt, metric: metric)
    }

    func loadAnchorHolds() throws -> [AnchorHold] {
        let stmt = try store.prepare(
            "SELECT reason, detected_at_epoch, observed_samples, last_emitted_day, decision, metric FROM anchor_holds ORDER BY metric;"
        )
        defer { sqlite3_finalize(stmt) }
        var holds: [AnchorHold] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            holds.append(hold(from: stmt, metric: MetricID(rawValue: text(stmt, 5))))
        }
        return holds
    }

    private func hold(from stmt: OpaquePointer, metric: MetricID) -> AnchorHold {
        AnchorHold(
            metric: metric,
            // An unreadable reason still holds the metric. Forgetting why we stopped is
            // not a reason to start re-exporting again.
            reason: AnchorHold.Reason(rawValue: text(stmt, 0)) ?? .cursorLost,
            detectedAtEpoch: sqlite3_column_double(stmt, 1),
            observedSamples: Int(sqlite3_column_int64(stmt, 2)),
            lastEmittedDay: sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : text(stmt, 3),
            decision: sqlite3_column_type(stmt, 4) == SQLITE_NULL
                ? nil
                : AnchorHold.Decision(rawValue: text(stmt, 4))
        )
    }

    func upsertAnchorHold(_ hold: AnchorHold) throws {
        let stmt = try store.prepare(
            "INSERT INTO anchor_holds (metric, reason, detected_at_epoch, observed_samples, last_emitted_day, decision) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(metric) DO UPDATE SET reason = excluded.reason, detected_at_epoch = excluded.detected_at_epoch, observed_samples = excluded.observed_samples, last_emitted_day = excluded.last_emitted_day, decision = excluded.decision;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, hold.metric.rawValue)
        bindText(stmt, 2, hold.reason.rawValue)
        sqlite3_bind_double(stmt, 3, hold.detectedAtEpoch)
        sqlite3_bind_int64(stmt, 4, Int64(hold.observedSamples))
        if let day = hold.lastEmittedDay {
            bindText(stmt, 5, day)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        if let decision = hold.decision {
            bindText(stmt, 6, decision.rawValue)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        try stepDone(stmt)
    }

    func clearAnchorHold(metric: MetricID) throws {
        let stmt = try store.prepare("DELETE FROM anchor_holds WHERE metric = ?;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, metric.rawValue)
        try stepDone(stmt)
    }

    func loadDestinationScope(destinationID: String) throws -> DestinationExportScope? {
        let stmt = try store.prepare(
            "SELECT payload FROM destination_scopes WHERE destination_id = ? LIMIT 1;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, destinationID)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        // SEC-16: bytes we cannot read grant nothing. Returning nil instead would read as
        // "never configured" and invite the app migration to write a default grant over a
        // scope somebody chose.
        let payload = blob(stmt, 0)
        if let stored = try? DestinationScopePayload.decoded(
            payload,
            destinationID: destinationID
        ) {
            return stored
        }
        return try DestinationExportScope(destinationID: destinationID)
    }

    func upsertDestinationScope(_ scope: DestinationExportScope) throws {
        let stmt = try store.prepare(
            "INSERT INTO destination_scopes (destination_id, payload) VALUES (?, ?) ON CONFLICT(destination_id) DO UPDATE SET payload = excluded.payload;"
        )
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, scope.destinationID)
        bindBlob(stmt, 2, try DestinationScopePayload.encoded(scope))
        try stepDone(stmt)
    }

    func loadDestinationBreaker(destinationID: String) throws -> Data? {
        guard let text = try loadStateMeta("breaker:\(destinationID)") else { return nil }
        return Data(text.utf8)
    }

    func upsertDestinationBreaker(destinationID: String, bytes: Data) throws {
        try upsertStateMeta("breaker:\(destinationID)", value: String(decoding: bytes, as: UTF8.self))
    }

    func purgeMetricState(metric: MetricID) throws {
        for table in ["cursors", "census", "dirty", "emitted_index", "anchor_holds"] {
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
            "backfill_checkpoints", "anchor_holds", "destination_scopes",
            "freshness_latencies", "state_meta", "open_runs",
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

/// One row, one scope: the document wrapper belongs to the preference file, not to a
/// table that already keys by destination.
private enum DestinationScopePayload {
    static func encoded(_ scope: DestinationExportScope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(scope)
    }

    static func decoded(_ data: Data, destinationID: String) throws -> DestinationExportScope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let stored = try decoder.decode(DestinationExportScope.self, from: data)
        guard stored.destinationID == destinationID else {
            throw StorageError.execFailed("destination scope identity mismatch")
        }
        // The synthesised decoder skips the initialiser, so the interval check has to run
        // here: a range the type rejects is not one the row gets to keep.
        return try DestinationExportScope(
            destinationID: stored.destinationID,
            metrics: stored.metrics,
            startInclusive: stored.startInclusive,
            endExclusive: stored.endExclusive
        )
    }
}
