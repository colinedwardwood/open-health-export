import CoreDomain
import CoreTemporal
import CSQLite
import EnginePorts
import Foundation

public struct DiagnosticJournalRead: Sendable, Equatable {
    public var events: [RunEvent]
    public var degraded: [String]
    public var skippedRows: Int

    public init(events: [RunEvent], degraded: [String], skippedRows: Int) {
        self.events = events
        self.degraded = degraded
        self.skippedRows = skippedRows
    }
}

/// OBS-09: an independent, read-only diagnostic path that still returns a
/// partial result when the primary state store or individual journal rows fail.
public enum SQLiteDiagnosticReader {
    public static func read(
        path: String,
        maxRuns: Int = 30,
        windowSeconds: TimeInterval = 24 * 60 * 60,
        nowEpoch: TimeInterval = SystemClock().now().timeIntervalSince1970
    ) -> DiagnosticJournalRead {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return DiagnosticJournalRead(
                events: [],
                degraded: ["database_unreadable", "journal_rows_skipped=0;count_unavailable"],
                skippedRows: 0
            )
        }
        defer { sqlite3_close(db) }
        _ = sqlite3_busy_timeout(db, 1_000)

        let integrityPassed = integrityCheck(db)
        let minimumRuns = max(0, maxRuns)
        let cutoffEpoch = nowEpoch - max(0, windowSeconds)
        if integrityPassed,
           let bulk = bulkRead(
               db,
               minimumRuns: minimumRuns,
               cutoffEpoch: cutoffEpoch
           ) {
            var degraded: [String] = []
            if bulk.skipped > 0 {
                degraded.append("journal_rows_skipped=\(bulk.skipped)")
            }
            return DiagnosticJournalRead(
                events: bulk.events,
                degraded: degraded,
                skippedRows: bulk.skipped
            )
        }

        var degraded = ["sqlite_integrity_check_failed"]
        guard let salvaged = salvageRows(
            db,
            minimumRuns: minimumRuns,
            cutoffEpoch: cutoffEpoch
        ) else {
            degraded.append("journal_unreadable")
            degraded.append("journal_rows_skipped=0;count_unavailable")
            return DiagnosticJournalRead(events: [], degraded: degraded, skippedRows: 0)
        }
        degraded.append("journal_rows_skipped=\(salvaged.skipped)")
        return DiagnosticJournalRead(
            events: salvaged.events,
            degraded: degraded,
            skippedRows: salvaged.skipped
        )
    }

    private static func integrityCheck(_ db: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA integrity_check;", -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            sqlite3_finalize(statement)
            return false
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0)
        else {
            return false
        }
        return String(cString: text) == "ok"
    }

    private static func bulkRead(
        _ db: OpaquePointer,
        minimumRuns: Int,
        cutoffEpoch: TimeInterval
    ) -> (events: [RunEvent], skipped: Int)? {
        let sql = """
            SELECT run_id, outcome, detail, trigger,
                   samples_read, samples_committed, samples_acked,
                   wall_time_epoch, error_class
            FROM journal
            WHERE wall_time_epoch >= ?
               OR id IN (SELECT id FROM journal ORDER BY id DESC LIMIT ?)
            ORDER BY id;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            sqlite3_finalize(statement)
            return nil
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, cutoffEpoch)
        sqlite3_bind_int64(statement, 2, sqlite3_int64(minimumRuns))

        var events: [RunEvent] = []
        var skipped = 0
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                if let event = decodeEvent(statement) {
                    events.append(event)
                } else {
                    skipped += 1
                }
            case SQLITE_DONE:
                return (events, skipped)
            default:
                return nil
            }
        }
    }

    private static func salvageRows(
        _ db: OpaquePointer,
        minimumRuns: Int,
        cutoffEpoch: TimeInterval
    ) -> (events: [RunEvent], skipped: Int)? {
        var idsStatement: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            """
            SELECT id FROM journal
            WHERE wall_time_epoch >= ?
               OR id IN (SELECT id FROM journal ORDER BY id DESC LIMIT ?)
            ORDER BY id DESC;
            """,
            -1,
            &idsStatement,
            nil
        ) == SQLITE_OK, let idsStatement else {
            sqlite3_finalize(idsStatement)
            return nil
        }
        sqlite3_bind_double(idsStatement, 1, cutoffEpoch)
        sqlite3_bind_int64(idsStatement, 2, sqlite3_int64(minimumRuns))
        var ids: [Int64] = []
        while sqlite3_step(idsStatement) == SQLITE_ROW {
            ids.append(sqlite3_column_int64(idsStatement, 0))
        }
        sqlite3_finalize(idsStatement)

        var events: [RunEvent] = []
        var skipped = 0
        for id in ids.reversed() {
            if let event = readRow(db, id: id) {
                events.append(event)
            } else {
                skipped += 1
            }
        }
        return (events, skipped)
    }

    private static func readRow(_ db: OpaquePointer, id: Int64) -> RunEvent? {
        let sql = """
            SELECT run_id, outcome, detail, trigger,
                   samples_read, samples_committed, samples_acked,
                   wall_time_epoch, error_class
            FROM journal WHERE id = ?;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            sqlite3_finalize(statement)
            return nil
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return decodeEvent(statement)
    }

    private static func decodeEvent(_ statement: OpaquePointer) -> RunEvent? {
        guard let runIDBytes = sqlite3_column_text(statement, 0),
              let outcomeBytes = sqlite3_column_text(statement, 1),
              let detailBytes = sqlite3_column_text(statement, 2),
              let triggerBytes = sqlite3_column_text(statement, 3)
        else {
            return nil
        }
        let runID = String(cString: runIDBytes)
        let outcome = String(cString: outcomeBytes)
        let detail = String(cString: detailBytes)
        guard !runID.isEmpty,
              !outcome.isEmpty,
              let trigger = RunTrigger(rawValue: String(cString: triggerBytes))
        else {
            return nil
        }
        let read = sqlite3_column_int64(statement, 4)
        let committed = sqlite3_column_int64(statement, 5)
        let acked = sqlite3_column_int64(statement, 6)
        let wallTimeEpoch = sqlite3_column_double(statement, 7)
        let errorClass = sqlite3_column_text(statement, 8).map { String(cString: $0) }
        guard read >= 0, committed >= 0, acked >= 0,
              read <= Int64(Int.max),
              committed <= Int64(Int.max),
              acked <= Int64(Int.max)
        else {
            return nil
        }
        return RunEvent(
            runID: RunID(rawValue: runID),
            outcomeKind: outcome,
            detail: detail,
            trigger: trigger,
            samplesRead: Int(read),
            samplesCommitted: Int(committed),
            samplesAcked: Int(acked),
            wallTimeEpoch: wallTimeEpoch,
            errorClass: errorClass
        )
    }
}
