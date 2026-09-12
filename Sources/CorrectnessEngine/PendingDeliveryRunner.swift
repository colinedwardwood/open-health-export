// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CoreTemporal
import DestinationTrust
import EnginePorts

/// Replays committed batches after a crash. Each call performs at most one transport attempt for
/// this sink, using the oldest batch; scheduling and backoff decide when to call it again.
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
        destinationName: String = "destination",
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
        let batches = try await store.transact { try $0.pendingBatches() }
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
        try await store.transact { try $0.recordDelivery(receipt) }
        return [receipt]
    }
}
