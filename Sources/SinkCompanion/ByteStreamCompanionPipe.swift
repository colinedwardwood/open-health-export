// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import NetEgress

/// Carries companion frames over the one socket implementation in `NetEgress`. The phone dials
/// out and the Mac listens (R-34), so there is no listener on this side of the protocol.
public struct ByteStreamCompanionPipe: CompanionBytePipe {
    public var stream: any ByteStream

    public init(stream: any ByteStream) {
        self.stream = stream
    }

    /// The socket's `StreamError` is normalized here, at the boundary where it leaves the
    /// transport: `DeliveryExecutor` only classifies `DestinationSendError` and treats
    /// anything else as transient, so an un-normalized Local Network denial would be
    /// retried forever instead of telling the user to change a setting (R-21).
    public func send(_ data: Data) async throws {
        try await TransportFault.normalizing {
            try await stream.open()
            try await stream.send(data)
        }
    }

    public func receive(max: Int) async throws -> Data {
        try await TransportFault.normalizing {
            try await stream.open()
            return try await stream.receive(max: max)
        }
    }
}
