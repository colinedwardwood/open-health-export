import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The only type in ExportCore allowed to talk to `URLSession` (R-32).
public struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func execute(_ request: OutboundHTTPRequest) async throws -> OutboundHTTPResponse {
        EgressAttemptLog.record(kind: .http, host: request.url.host ?? request.url.absoluteString)
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        urlRequest.httpBody = try Data(contentsOf: request.bodyFile)
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw EgressError.notHTTP
        }
        return OutboundHTTPResponse(status: http.statusCode, body: data)
    }
}

public enum SystemHTTPTransport {
    public static func make() -> any HTTPTransport {
        URLSessionHTTPTransport()
    }

    public static func make(
        probing url: URL,
        allowedHosts: Set<String>,
        allowInsecureHTTP: Bool = false
    ) throws -> any HTTPTransport {
        #if canImport(Network)
        let endpoint = try StreamEndpoint.parse(
            url.absoluteString,
            allowedHosts: allowedHosts,
            allowInsecure: allowInsecureHTTP
        )
        return IdentityProbingHTTPTransport(
            http: URLSessionHTTPTransport(),
            endpoint: endpoint
        )
        #else
        _ = try EgressURL.parse(
            url.absoluteString,
            allowedHosts: allowedHosts,
            allowInsecureHTTP: allowInsecureHTTP
        )
        return URLSessionHTTPTransport()
        #endif
    }
}

#if canImport(Network)
private struct IdentityProbingHTTPTransport: HTTPTransport {
    var http: URLSessionHTTPTransport
    var endpoint: StreamEndpoint

    func execute(_ request: OutboundHTTPRequest) async throws -> OutboundHTTPResponse {
        try await http.execute(request)
    }

    func identityProbe() async throws -> TLSIdentity? {
        guard endpoint.usesTLS else { return nil }
        let stream = NWByteStream(
            endpoint: endpoint,
            options: .init(failFastOnWaiting: true)
        )
        try await stream.open()
        let identity = await stream.identity()
        await stream.close()
        return identity
    }
}
#endif
