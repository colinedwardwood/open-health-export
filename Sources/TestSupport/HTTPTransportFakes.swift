// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import NetEgress

public actor RecordingHTTPTransport: HTTPTransport {
    public private(set) var requests: [OutboundHTTPRequest] = []
    public var response: OutboundHTTPResponse
    public var error: EgressError?
    public var tls: TLSIdentity?

    public var queued: [OutboundHTTPResponse] = []
    public var throwOnce: EgressError?

    public init(response: OutboundHTTPResponse, error: EgressError? = nil, tls: TLSIdentity? = nil) {
        self.response = response
        self.error = error
        self.tls = tls
    }

    public func enqueue(_ next: OutboundHTTPResponse) {
        queued.append(next)
    }

    public func failOnce(_ error: EgressError) {
        throwOnce = error
    }

    public func identityProbe() async throws -> TLSIdentity? {
        tls
    }

    public func execute(_ request: OutboundHTTPRequest) async throws -> OutboundHTTPResponse {
        requests.append(request)
        if let once = throwOnce {
            throwOnce = nil
            throw once
        }
        if let error {
            throw error
        }
        if !queued.isEmpty {
            return queued.removeFirst()
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
