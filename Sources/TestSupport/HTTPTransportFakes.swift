import Foundation
import NetEgress

public actor RecordingHTTPTransport: HTTPTransport {
    public private(set) var requests: [OutboundHTTPRequest] = []
    public var response: OutboundHTTPResponse
    public var error: EgressError?
    public var tls: TLSIdentity?

    public init(response: OutboundHTTPResponse, error: EgressError? = nil, tls: TLSIdentity? = nil) {
        self.response = response
        self.error = error
        self.tls = tls
    }

    public func identityProbe() async throws -> TLSIdentity? {
        tls
    }

    public func execute(_ request: OutboundHTTPRequest) async throws -> OutboundHTTPResponse {
        requests.append(request)
        if let error {
            throw error
        }
        return response
    }
}

public struct ForbiddenHTTPTransport: HTTPTransport {
    public init() {}

    public func execute(_ request: OutboundHTTPRequest) async throws -> OutboundHTTPResponse {
        throw EgressError.transport("allowlist must run before connect")
    }
}
