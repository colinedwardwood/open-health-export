import Foundation
import NetEgress

/// Carries MQTT packets over the one socket implementation in `NetEgress`.
public struct ByteStreamMQTTPipe: MQTTBytePipe {
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
