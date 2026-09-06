#if canImport(Network)
import Foundation
import Network
import Security

/// Written to by the TLS verify block, which runs on a dispatch queue and not on the actor.
final class TLSObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TLSIdentity?

    var current: TLSIdentity? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ identity: TLSIdentity) {
        lock.lock()
        value = identity
        lock.unlock()
    }
}

/// The only socket in the package. TLS pinning is enforced inside the handshake's verify block,
/// so a mismatched pin fails the connection before any application byte is written.
public actor NWByteStream: ByteStream {
    public struct Options: Sendable {
        public var pin: PinRecord?
        public var requireTLS13: Bool
        public var connectTimeout: Duration
        /// A refused or unroutable destination sits in `.waiting` and retries rather than
        /// failing. Set this for the R-31 destination test, where the user holds a spinner.
        public var failFastOnWaiting: Bool
        /// Set for the Mac companion: TLS 1.3 PSK from pairing, no certificates involved.
        public var preSharedKey: PreSharedKey?

        public init(
            pin: PinRecord? = nil,
            requireTLS13: Bool = false,
            connectTimeout: Duration = .seconds(10),
            failFastOnWaiting: Bool = false,
            preSharedKey: PreSharedKey? = nil
        ) {
            self.pin = pin
            self.requireTLS13 = requireTLS13
            self.connectTimeout = connectTimeout
            self.failFastOnWaiting = failFastOnWaiting
            self.preSharedKey = preSharedKey
        }
    }

    private enum Target: Sendable {
        case hostPort(StreamEndpoint)
        case bonjour(BonjourService)
    }

    private let target: Target
    private let options: Options
    private let queue: DispatchQueue
    private let observation = TLSObservation()
    private var connection: NWConnection?
    private var openContinuation: CheckedContinuation<Void, Error>?
    private var isReady = false
    private var resolvedAddress: String?
    private var lastWaitingError: StreamError?

    public init(endpoint: StreamEndpoint, options: Options = Options()) {
        self.target = .hostPort(endpoint)
        self.options = options
        self.queue = DispatchQueue(label: "app.openhealthexporter.egress.\(endpoint.host)")
    }

    /// Dials the paired Mac companion by service name; the phone never listens (R-34).
    public init(service: BonjourService, options: Options) {
        self.target = .bonjour(service)
        self.options = options
        self.queue = DispatchQueue(label: "app.openhealthexporter.egress.\(service.name)")
    }

    public func identity() async -> TLSIdentity? {
        guard let observed = observation.current else { return nil }
        guard let resolvedAddress else { return observed }
        var merged = observed
        merged.resolvedAddress = resolvedAddress
        merged.addressClass = AddressClassifying.classify(resolvedAddress)
        return merged
    }

    public func open() async throws {
        if isReady { return }
        let connection: NWConnection
        switch target {
        case .hostPort(let endpoint):
            guard let port = NWEndpoint.Port(rawValue: endpoint.port) else { throw StreamError.badPort }
            connection = NWConnection(
                host: NWEndpoint.Host(endpoint.host),
                port: port,
                using: parameters()
            )
        case .bonjour(let service):
            connection = NWConnection(
                to: .service(name: service.name, type: service.type, domain: service.domain, interface: nil),
                using: parameters()
            )
        }
        self.connection = connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            openContinuation = continuation
            connection.stateUpdateHandler = { [weak self] state in
                Task { await self?.handle(state: state) }
            }
            connection.start(queue: queue)
            armConnectTimeout()
        }
        isReady = true
        resolvedAddress = remoteAddress(of: connection)
    }

    public func send(_ data: Data) async throws {
        try await open()
        guard let connection else { throw StreamError.notOpen }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: StreamError.transport(String(describing: error)))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    public func receive(max: Int) async throws -> Data {
        try await open()
        guard let connection else { throw StreamError.notOpen }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: max) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: StreamError.transport(String(describing: error)))
                    return
                }
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                    return
                }
                if isComplete {
                    continuation.resume(throwing: StreamError.closedByPeer)
                    return
                }
                continuation.resume(returning: Data())
            }
        }
    }

    public func close() async {
        connection?.cancel()
        connection = nil
        isReady = false
    }

    private func handle(state: NWConnection.State) {
        switch state {
        case .ready:
            finishOpen(nil)
        case .failed(let error):
            finishOpen(classify(error))
        case .cancelled:
            finishOpen(StreamError.closedByPeer)
        case .waiting(let error):
            lastWaitingError = classify(error)
            if options.failFastOnWaiting {
                finishOpen(lastWaitingError)
                connection?.cancel()
            }
        case .setup, .preparing:
            break
        @unknown default:
            break
        }
    }

    /// A TLS failure after we saw an identity that does not satisfy the pin is a pin change,
    /// not a generic transport error — the two carry different user consequences (R-31/R-40).
    private func classify(_ error: NWError) -> StreamError {
        if let pin = options.pin, let observed = observation.current {
            do {
                try PinGate.requireMatch(observed: observed, stored: pin)
            } catch {
                return StreamError.pinMismatch
            }
        }
        return StreamError.transport(String(describing: error))
    }

    private func finishOpen(_ error: Error?) {
        guard let continuation = openContinuation else { return }
        openContinuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    private func armConnectTimeout() {
        let timeout = options.connectTimeout
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            await self?.timeoutIfStillOpening()
        }
    }

    /// Prefer the reason the connection was stuck waiting over a bare timeout: "connection
    /// refused" is actionable, "timed out" is not.
    private func timeoutIfStillOpening() {
        guard openContinuation != nil else { return }
        finishOpen(lastWaitingError ?? StreamError.connectTimeout)
        connection?.cancel()
    }

    private func remoteAddress(of connection: NWConnection) -> String? {
        guard case .hostPort(let host, _) = connection.currentPath?.remoteEndpoint else { return nil }
        switch host {
        case .ipv4(let address):
            return "\(address)".split(separator: "%").first.map(String.init)
        case .ipv6(let address):
            return "\(address)".split(separator: "%").first.map(String.init)
        case .name(let name, _):
            return name
        @unknown default:
            return nil
        }
    }

    private func parameters() -> NWParameters {
        let host: String
        switch target {
        case .hostPort(let endpoint):
            guard endpoint.usesTLS else { return NWParameters.tcp }
            host = endpoint.host
        case .bonjour(let service):
            host = service.name
        }
        if let psk = options.preSharedKey {
            return TLSParameters.preSharedKey(psk)
        }
        let tls = NWProtocolTLS.Options()
        let security = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(
            security,
            options.requireTLS13 ? .TLSv13 : .TLSv12
        )
        sec_protocol_options_set_tls_server_name(security, host)
        let observation = self.observation
        let pin = options.pin
        sec_protocol_options_set_verify_block(security, { metadata, trustRef, complete in
            let trust = sec_trust_copy_ref(trustRef).takeRetainedValue()
            guard
                let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
                let leaf = chain.first,
                let leafSPKI = try? SPKIDigest.sha256Hex(certificateDER: SecCertificateCopyData(leaf) as Data)
            else {
                complete(false)
                return
            }
            let issuer = chain.dropFirst().first
            let issuerSPKI = issuer
                .flatMap { try? SPKIDigest.sha256Hex(certificateDER: SecCertificateCopyData($0) as Data) }
            let identity = TLSIdentity(
                leafSPKISha256: leafSPKI,
                issuerSPKISha256: issuerSPKI ?? "",
                tlsVersion: Self.versionName(sec_protocol_metadata_get_negotiated_tls_protocol_version(metadata)),
                cipherSuite: String(
                    format: "0x%04X",
                    sec_protocol_metadata_get_negotiated_tls_ciphersuite(metadata).rawValue
                ),
                leafSubject: SecCertificateCopySubjectSummary(leaf) as String? ?? host,
                leafIssuer: issuer.flatMap { SecCertificateCopySubjectSummary($0) as String? } ?? "",
                notBefore: "",
                notAfter: "",
                resolvedAddress: "",
                addressClass: .unknown,
                trustAnchorKind: "systemTrustStore"
            )
            observation.set(identity)
            if let pin {
                do {
                    try PinGate.requireMatch(observed: identity, stored: pin)
                    // A matching pin is the trust decision (R-31). Home MQTTS brokers
                    // are often self-signed; the system trust store must not override TOFU.
                    complete(true)
                } catch {
                    complete(false)
                }
                return
            }
            var trustError: CFError?
            complete(SecTrustEvaluateWithError(trust, &trustError))
        }, queue)
        return NWParameters(tls: tls)
    }

    private static func versionName(_ version: tls_protocol_version_t) -> String {
        switch version {
        case .TLSv12: return "TLS1.2"
        case .TLSv13: return "TLS1.3"
        case .DTLSv12: return "DTLS1.2"
        default: return "unknown"
        }
    }
}
#endif
