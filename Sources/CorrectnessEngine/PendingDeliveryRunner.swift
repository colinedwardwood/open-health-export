// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CoreTemporal
import DestinationTrust
import EnginePorts

/// Replays committed batches after a crash. Each call performs at most one transport attempt for
/// this sink, using the oldest owed delivery for this destination when fan-out rows exist,
/// otherwise the oldest unmigrated global batch.
public struct PendingDeliveryRunner: Sendable {
    public var destination: VerifiedDestination
    public var store: any StateStore
    public var destinationName: String
    public var clock: any Clock
    public var scope: DestinationExportScope?
    #if DEBUG
    public var faults: any ExportFaultInjector = NoExportFaults()
    #endif

    public init(
        destination: VerifiedDestination,
        store: any StateStore,
        destinationName: String = "local-file",
        clock: any Clock = SystemClock(),
        scope: DestinationExportScope? = nil
    ) {
        self.destination = destination
        self.store = store
        self.destinationName = destinationName
        self.clock = clock
        self.scope = scope
    }

    @discardableResult
    public func runOnce() async throws -> [DeliveryReceipt] {
        let owed = try await store.transact {
            try $0.pendingDeliveries(
                destinationID: DestinationID(rawValue: destinationName),
                limit: 1
            )
        }
        if let delivery = owed.first {
            return try await HTTPTransferSchedule.$current.withValue(.discretionaryRetry) {
                try await sendOnce(batch: delivery.batch)
            }
        }
        let batches = try await store.transact { tx in
            try tx.pendingBatches().filter { batch in
                try !tx.hasDeliveryObligations(batchID: batch.id)
            }
        }
        guard let batch = batches.first else { return [] }
        return try await HTTPTransferSchedule.$current.withValue(.discretionaryRetry) {
            try await sendOnce(batch: batch)
        }
    }

    private func sendOnce(batch: PendingBatch) async throws -> [DeliveryReceipt] {
        #if DEBUG
        let receipt = try await DeliveryExecutor.send(
            batch: batch,
            destination: destination,
            destinationName: destinationName,
            store: store,
            faults: faults,
            clock: clock,
            scope: scope
        )
        #else
        let receipt = try await DeliveryExecutor.send(
            batch: batch,
            destination: destination,
            destinationName: destinationName,
            store: store,
            clock: clock,
            scope: scope
        )
        #endif
        #if DEBUG
        try faults.hit(.afterAckBeforeRelease)
        #endif
        try await store.transact { tx in
            _ = try FanoutObligation.settle(
                receipt: receipt,
                destinationID: destinationName,
                on: tx
            )
        }
        return [receipt]
    }
}
