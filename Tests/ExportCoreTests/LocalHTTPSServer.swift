#if canImport(Network)
import Foundation
import NetEgress
import Network
import Security

/// Local HTTPS/1.1 listener for Darwin contract tests (QA-10 TLS). Lives in Tests/.
actor LocalHTTPSServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "ohe.https.loopback")
    private var status = 204
    private var body = Data()

    static func tlsParameters(identity: SecIdentity) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, sec_identity_create(identity)!)
        return NWParameters(tls: tls)
    }

    init(parameters: NWParameters, status: Int = 204, body: Data = Data()) throws {
        self.status = status
        self.body = body
        listener = try NWListener(using: parameters, on: .any)
    }

    func start() async throws -> UInt16 {
        let listener = self.listener
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            let once = OnceResumeHTTPS()
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

    private func serve(_ connection: NWConnection) async {
        connection.start(queue: queue)
        var inbound = Data()
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
            guard inbound.range(of: Data("\r\n\r\n".utf8)) != nil else { continue }
            let payload = body
            let response = "HTTP/1.1 \(status) OK\r\nConnection: close\r\nContent-Length: \(payload.count)\r\n\r\n"
            var outgoing = Data(response.utf8)
            outgoing.append(payload)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                connection.send(content: outgoing, completion: .contentProcessed { _ in
                    continuation.resume()
                })
            }
            connection.cancel()
            return
        }
    }
}

private final class OnceResumeHTTPS: @unchecked Sendable {
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
