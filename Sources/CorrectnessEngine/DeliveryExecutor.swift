import CoreDomain
import CoreTemporal
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
        store: any StateStore,
        clock: any Clock = SystemClock()
    ) async throws -> DeliveryReceipt {
        try await sendImpl(
            batch: batch,
            destination: destination,
            destinationName: destinationName,
            store: store,
            clock: clock,
            beforeAckObservation: {}
        )
    }

    #if DEBUG
    static func send(
        batch: PendingBatch,
        destination: VerifiedDestination,
        destinationName: String,
        store: any StateStore,
        faults: any ExportFaultInjector,
        clock: any Clock = SystemClock()
    ) async throws -> DeliveryReceipt {
        try await sendImpl(
            batch: batch,
            destination: destination,
            destinationName: destinationName,
            store: store,
            clock: clock,
            beforeAckObservation: { try faults.hit(.afterDestinationWriteBeforeAck) }
        )
    }
    #endif

    private static func sendImpl(
        batch: PendingBatch,
        destination: VerifiedDestination,
        destinationName: String,
        store: any StateStore,
        clock: any Clock,
        beforeAckObservation: () throws -> Void
    ) async throws -> DeliveryReceipt {
        let attemptID = UUID().uuidString.lowercased()
        try await append(
            phase: "attempt",
            attemptID: attemptID,
            batch: batch,
            destinationName: destinationName,
            store: store,
            atEpoch: clock.now().timeIntervalSince1970
        )
        do {
            let receipt = try await destination.sink.send(
                fileHandle: batch.payloadURL,
                idempotencyKey: batch.id
            )
            try beforeAckObservation()
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
                store: store,
                atEpoch: clock.now().timeIntervalSince1970
            )
            return receipt
        } catch {
            try await append(
                phase: "failed",
                attemptID: attemptID,
                batch: batch,
                destinationName: destinationName,
                store: store,
                atEpoch: clock.now().timeIntervalSince1970
            )
            throw error
        }
    }

    private static func append(
        phase: String,
        attemptID: String,
        batch: PendingBatch,
        destinationName: String,
        store: any StateStore,
        atEpoch: TimeInterval
    ) async throws {
        try await store.transact {
            try $0.appendLedger(
                EgressEntry(
                    destination: destinationName,
                    sampleCount: batch.expectedRecords,
                    outcomeKind: "\(attemptID):\(phase)",
                    byteCount: batch.byteCount,
                    wallTimeEpoch: atEpoch
                )
            )
        }
    }
}
