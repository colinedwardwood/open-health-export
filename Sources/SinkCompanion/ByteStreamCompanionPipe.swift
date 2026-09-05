import Foundation
import NetEgress

/// Carries companion frames over the one socket implementation in `NetEgress`. The phone dials
/// out and the Mac listens (R-34), so there is no listener on this side of the protocol.
public struct ByteStreamCompanionPipe: CompanionBytePipe {
    public var stream: any ByteStream

    public init(stream: any ByteStream) {
        self.stream = stream
    }

    public func send(_ data: Data) async throws {
        try await stream.open()
        try await stream.send(data)
    }

    public func receive(max: Int) async throws -> Data {
        try await stream.open()
        return try await stream.receive(max: max)
    }
}
