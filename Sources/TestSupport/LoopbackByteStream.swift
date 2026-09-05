import Foundation
import NetEgress

/// Presents a loopback broker as a `ByteStream`, so the sink pipe adapters are exercised
/// without a socket.
public struct LoopbackByteStream: ByteStream {
    private let sendBytes: @Sendable (Data) async throws -> Void
    private let receiveBytes: @Sendable (Int) async throws -> Data

    public init(mqtt broker: LoopbackMQTTBroker) {
        sendBytes = { try await broker.send($0) }
        receiveBytes = { try await broker.receive(max: $0) }
    }

    public init(companion broker: LoopbackCompanionBroker) {
        sendBytes = { try await broker.send($0) }
        receiveBytes = { try await broker.receive(max: $0) }
    }

    public func open() async throws {}
    public func close() async {}
    public func identity() async -> TLSIdentity? { nil }

    public func send(_ data: Data) async throws {
        try await sendBytes(data)
    }

    public func receive(max: Int) async throws -> Data {
        try await receiveBytes(max)
    }
}
