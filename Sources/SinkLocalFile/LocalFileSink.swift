import CoreDomain
import EnginePorts
import FileWriteKit
import Foundation
import WireFormat

public enum LocalFileSinkError: Error, Equatable {
    case idempotencyConflict
}

public struct LocalFileSink: DestinationSink, Sendable {
    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func send(fileHandle: String, idempotencyKey: BatchID) async throws -> DeliveryReceipt {
        let source = URL(fileURLWithPath: fileHandle)
        let sourceData = try Data(contentsOf: source)
        let destination = directory.appendingPathComponent(
            NativeWire.outputFileName(
                batchID: idempotencyKey,
                demo: NativeWire.payloadIsDemo(sourceData)
            )
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            guard try Data(contentsOf: destination) == sourceData else {
                throw LocalFileSinkError.idempotencyConflict
            }
        } else {
            try FileWriteKit.writeAtomically(sourceData, to: destination)
        }
        let text = String(decoding: sourceData, as: UTF8.self)
        return DeliveryReceipt(
            batchID: idempotencyKey,
            accepted: NativeWire.countRecords(in: text),
            statusOnly: false
        )
    }
}
