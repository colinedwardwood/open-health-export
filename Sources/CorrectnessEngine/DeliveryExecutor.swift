// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

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
        clock: any Clock = SystemClock(),
        scope: DestinationExportScope? = nil
    ) async throws -> DeliveryReceipt {
        try await sendImpl(
            batch: batch,
            destination: destination,
            destinationName: destinationName,
            store: store,
            clock: clock,
            scope: scope,
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
        clock: any Clock = SystemClock(),
        scope: DestinationExportScope? = nil
    ) async throws -> DeliveryReceipt {
        try await sendImpl(
            batch: batch,
            destination: destination,
            destinationName: destinationName,
            store: store,
            clock: clock,
            scope: scope,
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
        scope: DestinationExportScope?,
        beforeAckObservation: () throws -> Void
    ) async throws -> DeliveryReceipt {
        if let scope {
            try ExportScopeGate.require(
                metric: batch.metric,
                rangeStartDay: batch.rangeStartDay,
                rangeEndDay: batch.rangeEndDay,
                scope: scope
            )
        }
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
            if receipt.traceparentAutoDisabled {
                try await store.transact { tx in
                    try tx.appendJournal(
                        RunEvent(
                            runID: RunID(rawValue: batch.id.rawValue),
                            outcomeKind: "traceparent_auto_disabled",
                            detail: "retried_without_header",
                            wallTimeEpoch: clock.now().timeIntervalSince1970
                        )
                    )
                }
            }
            try beforeAckObservation()
            let phase: String
            let result: DeliveryAttemptResult
            if receipt.unconfirmed > 0 {
                phase = "unknown_ack"
                result = .unknownAck
            } else if receipt.accepted < batch.expectedRecords {
                phase = "partial"
                result = .failed(.transientServer)
            } else {
                phase = "acknowledged"
                result = .acknowledged
            }
            try await append(
                phase: phase,
                attemptID: attemptID,
                batch: batch,
                destinationName: destinationName,
                store: store,
                atEpoch: clock.now().timeIntervalSince1970
            )
            try await recordBreaker(result, destinationName: destinationName, store: store, clock: clock)
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
            try await recordBreaker(
                .failed(retryClass(from: error)),
                destinationName: destinationName,
                store: store,
                clock: clock
            )
            throw error
        }
    }

    private static func retryClass(from error: Error) -> RetryClass {
        guard let send = error as? DestinationSendError else {
            return .transientNetwork
        }
        switch send {
        case .destinationUnreachable:
            return .transientNetwork
        case .localNetworkDenied:
            return .auth
        case .cancelledBySystem, .budgetExhausted, .deviceLocked, .lowPowerMode:
            return .storeLocked
        case .healthDataRestricted:
            return .auth
        case .internalFault:
            return .protocol
        }
    }

    private static func recordBreaker(
        _ result: DeliveryAttemptResult,
        destinationName: String,
        store: any StateStore,
        clock: any Clock
    ) async throws {
        let now = clock.now()
        try await store.transact { tx in
            let current = RetryPolicy.age(
                snapshot: try DestinationBreaker.load(from: tx, destinationID: destinationName),
                now: now
            )
            let next = RetryPolicy.record(result, snapshot: current, now: now, jitter: 1)
            try DestinationBreaker.save(next, to: tx, destinationID: destinationName)
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
