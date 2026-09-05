import CoreDomain
import EnginePorts
import FileWriteKit
import Foundation
import WireFormat

public struct LocalFileSink: DestinationSink, Sendable {
    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func send(fileHandle: String, idempotencyKey: BatchID) async throws -> DeliveryReceipt {
        let source = URL(fileURLWithPath: fileHandle)
        let destination = directory.appendingPathComponent("\(idempotencyKey.rawValue).ndjson")
        try FileWriteKit.copyAtomically(from: source, to: destination)
        let text = try String(contentsOf: destination, encoding: .utf8)
        return DeliveryReceipt(
            batchID: idempotencyKey,
            accepted: NativeWire.countRecords(in: text),
            statusOnly: false
        )
    }
}
