import Foundation

public struct OutboundHTTPRequest: Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var bodyFile: URL

    public init(method: String, url: URL, headers: [String: String], bodyFile: URL) {
        self.method = method
        self.url = url
        self.headers = headers
        self.bodyFile = bodyFile
    }
}

public struct OutboundHTTPResponse: Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

public protocol HTTPTransport: Sendable {
    func execute(_ request: OutboundHTTPRequest) async throws -> OutboundHTTPResponse
    func identityProbe() async throws -> TLSIdentity?
}

public extension HTTPTransport {
    func identityProbe() async throws -> TLSIdentity? { nil }
}

public enum EgressError: Error, Equatable {
    case invalidURL
    case credentialsInURL
    case forbiddenScheme(String)
    case insecureHTTP
    case notAllowlisted(String)
    case notHTTP
    case httpStatus(Int)
    case transport(String)
    case pinMismatch
}

/// Parse and authorize a destination URL before any DNS or connect (R-32 step 1).
public enum EgressURL {
    public static func parse(
        _ raw: String,
        allowedHosts: Set<String>,
        allowInsecureHTTP: Bool
    ) throws -> URL {
        guard let url = URL(string: raw) else {
            throw EgressError.invalidURL
        }
        guard url.user == nil, url.password == nil else {
            throw EgressError.credentialsInURL
        }
        guard let scheme = url.scheme?.lowercased() else {
            throw EgressError.invalidURL
        }
        switch scheme {
        case "https", "mqtts":
            break
        case "http", "mqtt":
            guard allowInsecureHTTP else { throw EgressError.insecureHTTP }
        default:
            throw EgressError.forbiddenScheme(scheme)
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            throw EgressError.invalidURL
        }
        let allowed = Set(allowedHosts.map { $0.lowercased() })
        guard allowed.contains(host) else {
            throw EgressError.notAllowlisted(host)
        }
        return url
    }
}

public struct HTTPSDestination: Sendable {
    public var url: URL
    public var allowInsecureHTTP: Bool
    public var authorizationBearer: String?

    public init(
        urlString: String,
        allowedHosts: Set<String>,
        allowInsecureHTTP: Bool = false,
        authorizationBearer: String? = nil
    ) throws {
        self.url = try EgressURL.parse(
            urlString,
            allowedHosts: allowedHosts,
            allowInsecureHTTP: allowInsecureHTTP
        )
        self.allowInsecureHTTP = allowInsecureHTTP
        self.authorizationBearer = authorizationBearer
    }
}
