#if canImport(Network)
import Foundation
import NetEgress
import Network
import Security

/// Minimal HTTP/2 over TLS loopback for Darwin QA-10. Speaks enough of the framing
/// to accept a `URLSession` POST and reply 204. Lives in Tests/.
actor LocalHTTP2Server {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "ohe.http2.loopback")
    private var sawPreface = false
    private var requests = 0

    static func tlsParameters(identity: SecIdentity) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let security = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(security, .TLSv12)
        sec_protocol_options_set_local_identity(security, sec_identity_create(identity)!)
        sec_protocol_options_add_tls_application_protocol(security, "h2")
        return NWParameters(tls: tls)
    }

    init(parameters: NWParameters) throws {
        listener = try NWListener(using: parameters, on: .any)
    }

    func start() async throws -> UInt16 {
        let listener = self.listener
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            let once = OnceResumeHTTP2()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = listener.port {
                        once.resume(continuation, .success(port.rawValue))
                    } else {
                        once.resume(continuation, .failure(StreamError.badPort))
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

    func prefaceSeen() -> Bool { sawPreface }
    func requestCount() -> Int { requests }

    private func serve(_ connection: NWConnection) async {
        connection.start(queue: queue)
        var inbound = Data()
        var prefaceOK = false
        while true {
            let chunk: Data = await withCheckedContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, _ in
                    if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(returning: Data())
                    }
                    _ = isComplete
                }
            }
            if chunk.isEmpty { break }
            inbound.append(chunk)
            if !prefaceOK {
                let magic = Data("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".utf8)
                guard inbound.count >= magic.count else { continue }
                guard inbound.prefix(magic.count) == magic else { return }
                inbound.removeSubrange(0 ..< magic.count)
                prefaceOK = true
                sawPreface = true
                await send(connection, HTTP2Frame.settings([]))
            }
            while let frame = HTTP2Frame.pop(from: &inbound) {
                switch frame.type {
                case 0x4 where frame.flags & 0x1 == 0:
                    await send(connection, HTTP2Frame.settingsAck())
                case 0x6:
                    await send(connection, HTTP2Frame.pingAck(frame.payload))
                case 0x1, 0x0:
                    if frame.flags & 0x1 == 0x1 {
                        requests += 1
                        await send(connection, HTTP2Frame.status204(streamID: frame.streamID))
                        connection.cancel()
                        return
                    }
                default:
                    break
                }
            }
        }
    }

    private func send(_ connection: NWConnection, _ frame: Data) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: frame, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
    }
}

private enum HTTP2Frame {
    static func pop(from buffer: inout Data) -> (type: UInt8, flags: UInt8, streamID: UInt32, payload: Data)? {
        guard buffer.count >= 9 else { return nil }
        let length = Int(buffer[0]) << 16 | Int(buffer[1]) << 8 | Int(buffer[2])
        guard buffer.count >= 9 + length else { return nil }
        let type = buffer[3]
        let flags = buffer[4]
        let streamID =
            (UInt32(buffer[5]) << 24 | UInt32(buffer[6]) << 16 | UInt32(buffer[7]) << 8 | UInt32(buffer[8]))
            & 0x7FFF_FFFF
        let payload = buffer.subdata(in: 9 ..< (9 + length))
        buffer.removeSubrange(0 ..< (9 + length))
        return (type, flags, streamID, payload)
    }

    static func encode(type: UInt8, flags: UInt8, streamID: UInt32, payload: Data) -> Data {
        var header = Data(count: 9)
        header[0] = UInt8((payload.count >> 16) & 0xFF)
        header[1] = UInt8((payload.count >> 8) & 0xFF)
        header[2] = UInt8(payload.count & 0xFF)
        header[3] = type
        header[4] = flags
        header[5] = UInt8((streamID >> 24) & 0x7F)
        header[6] = UInt8((streamID >> 16) & 0xFF)
        header[7] = UInt8((streamID >> 8) & 0xFF)
        header[8] = UInt8(streamID & 0xFF)
        return header + payload
    }

    static func settings(_ entries: [(UInt16, UInt32)]) -> Data {
        var payload = Data()
        for (id, value) in entries {
            payload.append(UInt8(id >> 8))
            payload.append(UInt8(id & 0xFF))
            payload.append(UInt8((value >> 24) & 0xFF))
            payload.append(UInt8((value >> 16) & 0xFF))
            payload.append(UInt8((value >> 8) & 0xFF))
            payload.append(UInt8(value & 0xFF))
        }
        return encode(type: 0x4, flags: 0, streamID: 0, payload: payload)
    }

    static func settingsAck() -> Data {
        encode(type: 0x4, flags: 0x1, streamID: 0, payload: Data())
    }

    static func pingAck(_ payload: Data) -> Data {
        encode(type: 0x6, flags: 0x1, streamID: 0, payload: payload)
    }

    /// Indexed `:status: 204` (static table index 9).
    static func status204(streamID: UInt32) -> Data {
        encode(type: 0x1, flags: 0x5, streamID: streamID, payload: Data([0x89]))
    }
}

private final class OnceResumeHTTP2: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func resume(_ continuation: CheckedContinuation<UInt16, Error>, _ result: Result<UInt16, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        continuation.resume(with: result)
    }
}
#endif
