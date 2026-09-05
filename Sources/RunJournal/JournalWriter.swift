import CoreDomain
import EnginePorts

public enum JournalWriter {
    public static func record(run: RunID, outcome: RunOutcome, into store: any StateStore) async throws {
        try await store.transact { tx in
            try tx.appendJournal(
                RunEvent(runID: run, outcomeKind: outcome.kind.rawValue, detail: outcome.partialCause ?? "")
            )
        }
    }
}
