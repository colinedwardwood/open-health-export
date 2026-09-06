import CoreDomain
import DestinationTrust
import EnginePorts

/// Replays committed batches after a crash. Each call performs at most one transport attempt for
/// this sink, using the oldest batch; scheduling and backoff decide when to call it again.
public struct PendingDeliveryRunner: Sendable {
    public var destination: VerifiedDestination
    public var store: any StateStore
    public var destinationName: String
    #if DEBUG
    public var faults: any ExportFaultInjector = NoExportFaults()
    #endif

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
        guard let batch = batches.first else { return [] }
        #if DEBUG
        let receipt = try await DeliveryExecutor.send(
            batch: batch,
            destination: destination,
            destinationName: destinationName,
            store: store,
            faults: faults
        )
        #else
        let receipt = try await DeliveryExecutor.send(
            batch: batch,
            destination: destination,
            destinationName: destinationName,
            store: store
        )
        #endif
        #if DEBUG
        try faults.hit(.afterAckBeforeRelease)
        #endif
        try await store.transact { try $0.recordDelivery(receipt) }
        return [receipt]
    }
}
