// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

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
    public var headers: [String: String]

    public init(status: Int, body: Data, headers: [String: String] = [:]) {
        self.status = status
        self.body = body
        self.headers = headers
    }

    public func header(_ name: String) -> String? {
        let wanted = name.lowercased()
        return headers.first { $0.key.lowercased() == wanted }?.value
    }
}

public protocol HTTPTransport: Sendable {
    func execute(_ request: OutboundHTTPRequest) async throws -> OutboundHTTPResponse
    func identityProbe() async throws -> TLSIdentity?
    /// System transports return a pin-aware `URLSession`. Test fakes keep themselves.
    func applyingPin(_ pin: PinRecord) -> any HTTPTransport
}

public extension HTTPTransport {
    func identityProbe() async throws -> TLSIdentity? { nil }
    func applyingPin(_ pin: PinRecord) -> any HTTPTransport { self }
}

public enum EgressError: Error, Equatable {
    case invalidURL
    case credentialsInURL
    case forbiddenScheme(String)
    case insecureHTTP
    case notAllowlisted(String)
    case notHTTP
    case httpStatus(Int)
    case httpRetryAfter(status: Int, seconds: TimeInterval)
    case transport(String)
    case pinMismatch
}

/// RFC 9110 `Retry-After`: delta-seconds or HTTP-date, capped at 24 hours.
public enum HTTPRetryAfter {
    public static let maximum: TimeInterval = 24 * 60 * 60

    public static func parseDelta(_ raw: String?) -> TimeInterval? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = TimeInterval(trimmed) else { return nil }
        return min(max(0, seconds), maximum)
    }

    public static func parse(_ raw: String?, now: Date) -> TimeInterval? {
        if let delta = parseDelta(raw) { return delta }
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: trimmed) else { return nil }
        return min(max(0, date.timeIntervalSince(now)), maximum)
    }
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

public struct HTTPSDestination: Sendable, Equatable {
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
