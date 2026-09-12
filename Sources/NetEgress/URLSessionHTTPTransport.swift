// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import EnginePorts
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Security)
import Security
#endif

/// The only type in ExportCore allowed to talk to `URLSession` (R-32).
public final class URLSessionHTTPTransport: HTTPTransport, @unchecked Sendable {
    public enum Role: Sendable {
        /// Health export payloads (HK-18).
        case exportPayload
        /// OTLP, probes, and tests that must not join the payload background session.
        case auxiliary
    }

    private let session: URLSession
    private let delegate: HTTPSessionDelegate
    private let resolver: any AddressResolver
    private let pin: PinRecord?
    private let role: Role

    public init(
        pin: PinRecord? = nil,
        resolver: any AddressResolver = SystemAddressResolver(),
        role: Role = .auxiliary
    ) {
        let delegate = HTTPSessionDelegate(pin: pin, resolver: resolver)
        self.delegate = delegate
        self.resolver = resolver
        self.pin = pin
        self.role = role
        session = URLSession(
            configuration: .ephemeral,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    public func execute(_ request: OutboundHTTPRequest) async throws -> OutboundHTTPResponse {
        let bodyBytes = (try? FileManager.default.attributesOfItem(
            atPath: request.bodyFile.path
        )[.size] as? NSNumber)?.intValue ?? 0
        EgressAttemptLog.record(
            kind: .http,
            host: request.url.host ?? request.url.absoluteString,
            bytes: bodyBytes
        )
        let connectionURL = try await connectTimeURL(for: request.url)
        guard FileManager.default.isReadableFile(atPath: request.bodyFile.path) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        if let pin, let host = request.url.host {
            HTTPBackgroundSession.storePin(pin, host: host)
        }
        var urlRequest = URLRequest(url: connectionURL)
        urlRequest.timeoutInterval = 30
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        if connectionURL != request.url, let host = request.url.host {
            let defaultPort = request.url.port == nil || request.url.port == 80
            urlRequest.setValue(
                defaultPort ? host : "\(host):\(request.url.port!)",
                forHTTPHeaderField: "Host"
            )
        }
        let session = payloadSessionIfNeeded()
        let (data, response) = try await session.upload(for: urlRequest, fromFile: request.bodyFile)
        guard let http = response as? HTTPURLResponse else {
            throw EgressError.notHTTP
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let name = key as? String, let text = value as? String {
                headers[name] = text
            }
        }
        return OutboundHTTPResponse(status: http.statusCode, body: data, headers: headers)
    }

    public func applyingPin(_ pin: PinRecord) -> any HTTPTransport {
        URLSessionHTTPTransport(pin: pin, resolver: resolver, role: role)
    }

    private func payloadSessionIfNeeded() -> URLSession {
        guard role == .exportPayload else { return session }
        #if os(iOS)
        return HTTPBackgroundSession.payloadSession(
            schedule: HTTPTransferSchedule.current,
            pin: pin,
            resolver: resolver
        )
        #else
        return session
        #endif
    }

    /// Plain HTTP is a local-network-only opt-in. Resolve and pin its numeric address before
    /// constructing the task, so URLSession cannot perform a second DNS lookup after the gate.
    /// Private-approved HTTPS is re-checked but remains hostname-based for SNI and PKI/ATS.
    private func connectTimeURL(for url: URL) async throws -> URL {
        guard let scheme = url.scheme?.lowercased(), let host = url.host else { return url }
        let hostClass = AddressClassifying.classify(host)
        let privateApproved = scheme == "http"
            || AddressClassifying.hostnameLooksLikeMDNS(host)
            || hostClass == .loopback
            || hostClass == .privateRFC1918
            || hostClass == .linkLocal
        guard privateApproved else { return url }
        let resolver = self.resolver
        let address = try await Task.detached {
            try ConnectTimeAddressGate.connectionAddress(
                host: host,
                policy: .requireLocal,
                resolver: resolver
            )
        }.value
        guard scheme == "http" else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw EgressError.invalidURL
        }
        components.host = address
        guard let resolved = components.url else { throw EgressError.invalidURL }
        return resolved
    }
}

/// Redirects are not followed: a 3xx host is not re-checked against the allowlist (T-04).
/// Server trust follows the pin when one exists, otherwise R-31 TOFU.
final class HTTPSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    let pin: PinRecord?
    let resolver: any AddressResolver

    init(pin: PinRecord?, resolver: any AddressResolver) {
        self.pin = pin
        self.resolver = resolver
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        #if canImport(Security)
        let host = challenge.protectionSpace.host
        let hostClass = AddressClassifying.classify(host)
        if AddressClassifying.hostnameLooksLikeMDNS(host)
            || hostClass == .loopback
            || hostClass == .privateRFC1918
            || hostClass == .linkLocal
        {
            do {
                _ = try ConnectTimeAddressGate.connectionAddress(
                    host: host,
                    policy: .requireLocal,
                    resolver: resolver
                )
            } catch {
                // TLS trust challenges happen before URLSession releases request body bytes.
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        }
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust,
            let identity = TLSIdentity.fromServerTrust(
                trust,
                host: challenge.protectionSpace.host
            )
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        if let pin = HTTPBackgroundSession.pin(for: host) ?? pin {
            do {
                try PinGate.requireMatch(observed: identity, stored: pin)
                completionHandler(.useCredential, URLCredential(trust: trust))
            } catch {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
        #else
        completionHandler(.performDefaultHandling, nil)
        #endif
    }

    #if os(iOS)
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        HTTPBackgroundSession.completeEvents(for: session)
    }
    #endif
}

public enum SystemHTTPTransport {
    public static func make() -> any HTTPTransport {
        URLSessionHTTPTransport(role: .exportPayload)
    }

    public static func make(
        probing url: URL,
        allowedHosts: Set<String>,
        allowInsecureHTTP: Bool = false,
        pin: PinRecord? = nil
    ) throws -> any HTTPTransport {
        #if canImport(Network)
        let endpoint = try StreamEndpoint.parse(
            url.absoluteString,
            allowedHosts: allowedHosts,
            allowInsecure: allowInsecureHTTP
        )
        return IdentityProbingHTTPTransport(
            http: URLSessionHTTPTransport(pin: pin, role: .exportPayload),
            endpoint: endpoint
        )
        #else
        _ = try EgressURL.parse(
            url.absoluteString,
            allowedHosts: allowedHosts,
            allowInsecureHTTP: allowInsecureHTTP
        )
        return URLSessionHTTPTransport(pin: pin, role: .exportPayload)
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

    func applyingPin(_ pin: PinRecord) -> any HTTPTransport {
        IdentityProbingHTTPTransport(http: URLSessionHTTPTransport(pin: pin, role: .exportPayload), endpoint: endpoint)
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
