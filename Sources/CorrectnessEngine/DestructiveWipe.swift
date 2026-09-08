import EnginePorts
import Foundation
import RunJournal

public enum DestructiveWipeError: Error, Equatable {
    case cleanupFailed(count: Int)
}

/// R-43 coordinator: credentials and device identity are destroyed before durable
/// state is reset. The successor genesis is then sealed with a fresh identity.
public enum DestructiveWipe {
    public static func perform(
        store: any StateStore,
        secretStores: [any SecretStore],
        ledgerSeal: any ResettableLedgerHeadSeal,
        ledgerSealURL: URL,
        atEpoch: TimeInterval
    ) async throws {
        var cleanupFailures = 0
        do {
            try await ledgerSeal.destroyIdentity()
        } catch {
            cleanupFailures += 1
        }
        for secretStore in secretStores {
            do {
                try await secretStore.deleteAll()
            } catch {
                cleanupFailures += 1
            }
        }

        try await store.wipe(atEpoch: atEpoch)
        let successor = try await store.transact { tx in
            try tx.loadLedger()
        }
        try await LedgerHeadSealRecordFile.update(
            entries: successor,
            seal: ledgerSeal,
            sealedAtEpoch: atEpoch,
            url: ledgerSealURL
        )

        guard cleanupFailures == 0 else {
            throw DestructiveWipeError.cleanupFailed(count: cleanupFailures)
        }
    }
}
