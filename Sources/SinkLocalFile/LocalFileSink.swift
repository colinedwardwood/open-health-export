// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

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
        let destination = directory.appendingPathComponent(
            NativeWire.outputFileName(
                batchID: idempotencyKey,
                demo: try NativeWire.payloadIsDemo(at: source)
            )
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            guard try FileWriteKit.contentsEqual(destination, source) else {
                throw LocalFileSinkError.idempotencyConflict
            }
        } else {
            try FileWriteKit.copyAtomically(from: source, to: destination)
        }
        try? NativeSidecars.write(fromNDJSONAt: destination, beside: destination)
        return DeliveryReceipt(
            batchID: idempotencyKey,
            accepted: try NativeWire.countRecords(at: destination),
            statusOnly: false
        )
    }
}
