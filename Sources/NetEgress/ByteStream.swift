import Foundation

public enum StreamError: Error, Equatable {
    case notOpen
    case closedByPeer
    case connectTimeout
    case transport(String)
    case pinMismatch
    case badPort
    case badServiceName
    case badPreSharedKey
    case serviceNotFound
    case unsupportedPlatform
}

/// A duplex byte stream. `MQTTSink` and `CompanionSink` both ride one of these, so the only
/// socket implementation in the package lives here in `NetEgress`.
public protocol ByteStream: Sendable {
    /// Idempotent: a stream that is already open returns immediately.
    func open() async throws
    func send(_ data: Data) async throws
    func receive(max: Int) async throws -> Data
    func close() async
    /// The peer identity observed during the handshake, once there is one.
    func identity() async -> TLSIdentity?
}

/// A Bonjour service the Mac companion advertises. The name comes from the pairing payload the
/// user scanned, and only an exact match may be dialled — discovery is not authorization.
public struct BonjourService: Sendable, Equatable {
    public static let companionType = "_ohx-recv._tcp"

    public var name: String
    public var type: String
    public var domain: String

    public init(name: String, type: String = BonjourService.companionType, domain: String = "local.") throws {
        guard !name.isEmpty, name.utf8.count <= 63 else { throw StreamError.badServiceName }
        guard type == BonjourService.companionType else { throw StreamError.badServiceName }
        self.name = name
        self.type = type
        self.domain = domain
    }

    /// Picks the paired service out of whatever else is advertising on the network.
    public static func match(candidates: [String], pairedName: String) -> String? {
        candidates.first { $0 == pairedName }
    }
}

/// TLS 1.3 pre-shared key material, established at pairing (R-33) and held by the caller.
public struct PreSharedKey: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public var key: [UInt8]
    public var identity: [UInt8]

    public init(key: [UInt8], identity: [UInt8]) throws {
        guard !key.isEmpty, !identity.isEmpty else { throw StreamError.badPreSharedKey }
        self.key = key
        self.identity = identity
    }

    public var description: String { "PreSharedKey(redacted)" }
    public var debugDescription: String { "PreSharedKey(redacted)" }
}

/// Host, port and TLS-or-not, derived only from a URL that has already passed the allowlist.
public struct StreamEndpoint: Sendable, Equatable {
    public var host: String
    public var port: UInt16
    public var usesTLS: Bool

    public init(host: String, port: UInt16, usesTLS: Bool) throws {
        guard port != 0 else { throw StreamError.badPort }
        self.host = host.lowercased()
        self.port = port
        self.usesTLS = usesTLS
    }

    /// Parses, authorizes against the allowlist, and only then yields something connectable
    /// (R-32 step 1: no DNS and no connect for a host the user has not approved).
    public static func parse(
        _ raw: String,
        allowedHosts: Set<String>,
        allowInsecure: Bool = false
    ) throws -> StreamEndpoint {
        let url = try EgressURL.parse(raw, allowedHosts: allowedHosts, allowInsecureHTTP: allowInsecure)
        guard let host = url.host, let scheme = url.scheme?.lowercased() else {
            throw EgressError.invalidURL
        }
        let usesTLS: Bool
        let defaultPort: UInt16
        switch scheme {
        case "https":
            usesTLS = true
            defaultPort = 443
        case "http":
            usesTLS = false
            defaultPort = 80
        case "mqtts":
            usesTLS = true
            defaultPort = 8883
        case "mqtt":
            usesTLS = false
            defaultPort = 1883
        default:
            throw EgressError.forbiddenScheme(scheme)
        }
        let port: UInt16
        if let explicit = url.port {
            guard let narrowed = UInt16(exactly: explicit), narrowed != 0 else { throw StreamError.badPort }
            port = narrowed
        } else {
            port = defaultPort
        }
        return try StreamEndpoint(host: host, port: port, usesTLS: usesTLS)
    }
}
