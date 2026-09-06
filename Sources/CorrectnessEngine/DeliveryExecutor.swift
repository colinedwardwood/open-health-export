import CoreDomain
import DestinationTrust
import EnginePorts
import Foundation

/// One transport attempt with a durable begin/outcome pair (R-30). There is deliberately no
/// retry loop here; the scheduler may invoke it once again in a later wake.
enum DeliveryExecutor {
    static func send(
        batch: PendingBatch,
        destination: VerifiedDestination,
        destinationName: String,
        store: any StateStore
    ) async throws -> DeliveryReceipt {
        let attemptID = UUID().uuidString.lowercased()
        try await append(
            phase: "attempt",
            attemptID: attemptID,
            batch: batch,
            destinationName: destinationName,
            store: store
        )
        do {
            let receipt = try await destination.sink.send(
                fileHandle: batch.payloadURL,
                idempotencyKey: batch.id
            )
            let phase: String
            if receipt.unconfirmed > 0 {
                phase = "unknown_ack"
            } else if receipt.accepted < batch.expectedRecords {
                phase = "partial"
            } else {
                phase = "acknowledged"
            }
            try await append(
                phase: phase,
                attemptID: attemptID,
                batch: batch,
                destinationName: destinationName,
                store: store
            )
            return receipt
        } catch {
            try await append(
                phase: "failed",
                attemptID: attemptID,
                batch: batch,
                destinationName: destinationName,
                store: store
            )
            throw error
        }
    }

    private static func append(
        phase: String,
        attemptID: String,
        batch: PendingBatch,
        destinationName: String,
        store: any StateStore
    ) async throws {
        try await store.transact {
            try $0.appendLedger(
                EgressEntry(
                    destination: destinationName,
                    sampleCount: batch.expectedRecords,
                    outcomeKind: "\(attemptID):\(phase)"
                )
            )
        }
    }
}
