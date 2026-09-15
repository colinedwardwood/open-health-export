// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CoreTemporal
import DestinationTrust
import EnginePorts
import Foundation

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
                try await sendOnce(delivery: delivery)
            }
        }
        let batches = try await store.transact { tx in
            try tx.pendingBatches().filter { batch in
                try !tx.hasDeliveryObligations(batchID: batch.id)
            }
        }
        guard let batch = batches.first else { return [] }
        return try await HTTPTransferSchedule.$current.withValue(.discretionaryRetry) {
            try await sendAttempt(
                batch: batch,
                expectedRecords: batch.expectedRecords,
                grant: scope,
                project: false
            )
        }
    }

    private func sendOnce(delivery: PendingDelivery) async throws -> [DeliveryReceipt] {
        try await sendAttempt(
            batch: delivery.batch,
            expectedRecords: delivery.expectedRecords,
            grant: scope ?? delivery.scopeSnapshot,
            project: true
        )
    }

    private func sendAttempt(
        batch: PendingBatch,
        expectedRecords: Int,
        grant: DestinationExportScope?,
        project: Bool
    ) async throws -> [DeliveryReceipt] {
        if expectedRecords == 0 {
            let receipt = DeliveryReceipt(
                batchID: batch.id,
                accepted: 0,
                statusOnly: false
            )
            let settlement = try await store.transact { tx in
                try FanoutObligation.settle(
                    receipt: receipt,
                    destinationID: destinationName,
                    on: tx
                )
            }
            FanoutObligation.unlink(settlement)
            return [receipt]
        }
        var attempt = batch
        var skipRangeGate = false
        if project {
            let scratch = URL(fileURLWithPath: batch.payloadURL).deletingLastPathComponent()
            let url = try FanoutPayload.attemptURL(
                canonical: batch,
                destinationID: destinationName,
                expectedRecords: expectedRecords,
                scope: grant,
                scratchDirectory: scratch
            )
            attempt.payloadURL = url.path
            skipRangeGate = url.path != batch.payloadURL
        }
        attempt.expectedRecords = expectedRecords
        defer {
            if attempt.payloadURL != batch.payloadURL {
                try? FileManager.default.removeItem(atPath: attempt.payloadURL)
            }
        }
        #if DEBUG
        let receipt = try await DeliveryExecutor.send(
            batch: attempt,
            destination: destination,
            destinationName: destinationName,
            store: store,
            faults: faults,
            clock: clock,
            scope: grant,
            skipRangeGate: skipRangeGate
        )
        #else
        let receipt = try await DeliveryExecutor.send(
            batch: attempt,
            destination: destination,
            destinationName: destinationName,
            store: store,
            clock: clock,
            scope: grant,
            skipRangeGate: skipRangeGate
        )
        #endif
        #if DEBUG
        try faults.hit(.afterAckBeforeRelease)
        #endif
        let settlement = try await store.transact { tx in
            try FanoutObligation.settle(
                receipt: receipt,
                destinationID: destinationName,
                on: tx
            )
        }
        FanoutObligation.unlink(settlement)
        return [receipt]
    }
}
