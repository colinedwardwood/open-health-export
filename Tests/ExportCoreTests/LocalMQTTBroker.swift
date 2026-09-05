#if canImport(Network)
import Foundation
import MQTTCodec
import Network

/// A localhost MQTT 3.1.1 broker for Darwin tests. Lives in Tests/, not Sources/, so it may
/// use `NWListener` without becoming an iOS listening socket.
actor LocalMQTTBroker {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "ohe.mqtt.loopback")

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async throws -> UInt16 {
        let listener = self.listener
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            let once = OnceResume<UInt16>()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = listener.port {
                        once.resume(continuation, .success(port.rawValue))
                    } else {
                        once.resume(continuation, .failure(MQTTError.truncated))
                    }
                case .failed(let error):
                    once.resume(continuation, .failure(error))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { connection in
                Task { await self.serve(connection) }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
    }

    private func serve(_ connection: NWConnection) async {
        connection.start(queue: queue)
        var inbound = Data()
        while true {
            let chunk: Data = await withCheckedContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, _ in
                    if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else if isComplete {
                        continuation.resume(returning: Data())
                    } else {
                        continuation.resume(returning: Data())
                    }
                }
            }
            if chunk.isEmpty { break }
            inbound.append(chunk)
            while inbound.count >= 2 {
                let packet: (kind: MQTTPacketKind, flags: UInt8, body: Data, consumed: Int)
                do {
                    packet = try MQTTCodec.decode(inbound)
                } catch MQTTError.truncated {
                    break
                } catch {
                    return
                }
                inbound.removeFirst(packet.consumed)
                switch packet.kind {
                case .connect:
                    send(Data([0x20, 0x02, 0x00, 0x00]), on: connection)
                case .publish:
                    if let id = try? MQTTCodec.decodePublishPacketID(flags: packet.flags, body: packet.body) {
                        send(Data([0x40, 0x02, UInt8(id >> 8), UInt8(id & 0xFF)]), on: connection)
                    }
                case .pingreq:
                    send(Data([0xD0, 0x00]), on: connection)
                case .disconnect:
                    connection.cancel()
                    return
                default:
                    break
                }
            }
        }
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in })
    }
}

private final class OnceResume<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func resume(_ continuation: CheckedContinuation<Value, Error>, _ result: Result<Value, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        continuation.resume(with: result)
    }
}
#endif
