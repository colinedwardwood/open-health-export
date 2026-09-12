// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

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
                guard inbound.count >= HTTP2Frame.clientPreface.count else { continue }
                guard inbound.prefix(HTTP2Frame.clientPreface.count) == HTTP2Frame.clientPreface else { return }
                inbound.removeSubrange(0 ..< HTTP2Frame.clientPreface.count)
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
