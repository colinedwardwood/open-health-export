import Foundation
import MQTTCodec
import SinkMQTT

public actor LoopbackMQTTBroker: MQTTBytePipe {
    private var outbox = Data()
    private var waiters: [CheckedContinuation<Data, Error>] = []
    public private(set) var lastPublishTopic: String?

    public init() {}

    public func send(_ data: Data) async throws {
        var rest = data
        while !rest.isEmpty {
            let packet = try MQTTCodec.decode(rest)
            rest = Data(rest.dropFirst(packet.consumed))
            switch packet.kind {
            case .connect:
                enqueue(Data([0x20, 0x02, 0x00, 0x00]))
            case .publish:
                lastPublishTopic = try MQTTCodec.decodePublishTopic(body: packet.body)
                if let id = try MQTTCodec.decodePublishPacketID(flags: packet.flags, body: packet.body) {
                    enqueue(Data([0x40, 0x02, UInt8(id >> 8), UInt8(id & 0xFF)]))
                }
            case .pingreq:
                enqueue(Data([0xD0, 0x00]))
            case .disconnect:
                break
            default:
                break
            }
        }
    }

    public func receive(max: Int) async throws -> Data {
        if !outbox.isEmpty {
            let n = min(max, outbox.count)
            let chunk = outbox.prefix(n)
            outbox.removeFirst(n)
            return Data(chunk)
        }
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func enqueue(_ data: Data) {
        if waiters.isEmpty {
            outbox.append(data)
        } else {
            let waiter = waiters.removeFirst()
            waiter.resume(returning: data)
        }
    }
}
