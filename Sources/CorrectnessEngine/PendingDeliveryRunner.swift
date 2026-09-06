import CoreDomain
import DestinationTrust
import EnginePorts

/// Replays committed batches after a crash. Each call performs at most one attempt per batch;
/// scheduling and backoff decide when to call it again.
public struct PendingDeliveryRunner: Sendable {
    public var destination: VerifiedDestination
    public var store: any StateStore
    public var destinationName: String

    public init(
        destination: VerifiedDestination,
        store: any StateStore,
        destinationName: String = "destination"
    ) {
        self.destination = destination
        self.store = store
        self.destinationName = destinationName
    }

    @discardableResult
    public func runOnce() async throws -> [DeliveryReceipt] {
        let batches = try await store.transact { try $0.pendingBatches() }
        var receipts: [DeliveryReceipt] = []
        for batch in batches {
            let receipt = try await DeliveryExecutor.send(
                batch: batch,
                destination: destination,
                destinationName: destinationName,
                store: store
            )
            try await store.transact { try $0.recordDelivery(receipt) }
            receipts.append(receipt)
        }
        return receipts
    }
}
