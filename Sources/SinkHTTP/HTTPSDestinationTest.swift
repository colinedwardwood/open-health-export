// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import DestinationTrust
import FileWriteKit
import Foundation
import MetricCatalog
import NetEgress
import WireFormat

/// R-25 HTTPS/HA test: resolve → TLS → pin → authenticate → send canary → read response.
public enum HTTPSDestinationTest {
    public static func run(
        destination: HTTPSDestination,
        transport: any HTTPTransport,
        pin: PinRecord? = nil,
        canary: Data,
        observedAt: String = "1970-01-01T00:00:00Z",
        entityURL: URL? = nil,
        expected: MetricDeclaration? = nil,
        onProgress: DestinationTestProgress? = nil
    ) async -> DestinationTestReport {
        let total = pin == nil ? 5 : 6
        var steps: [DestinationTestStepReport] = []
        onProgress?(1, total, .resolveHost)
        guard let host = destination.url.host, !host.isEmpty else {
            return .failed(at: .resolveHost)
        }
        steps.append(DestinationTestStepReport(name: .resolveHost, outcome: .passed, detail: host))

        onProgress?(2, total, .tlsHandshake)
        let identity: TLSIdentity?
        do {
            identity = try await transport.identityProbe()
        } catch {
            return .failed(at: .tlsHandshake, prior: steps)
        }
        if destination.url.scheme?.lowercased() == "https", identity == nil {
            return .failed(at: .tlsHandshake, prior: steps)
        }
        steps.append(DestinationTestStepReport(name: .tlsHandshake, outcome: .passed))

        if let pin {
            onProgress?(3, total, .confirmCertificate)
            switch PinGate.evaluate(observed: identity, stored: pin, policy: pin.policy, observedAt: observedAt) {
            case .matched, .noTLS:
                steps.append(DestinationTestStepReport(name: .confirmCertificate, outcome: .passed))
            default:
                return .failed(at: .confirmCertificate, prior: steps)
            }
        }

        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohe-https-canary-\(UUID().uuidString).ndjson")
        do {
            try FileWriteKit.writeAtomically(canary, to: file)
        } catch {
            return .failed(at: .sendCanary, prior: steps)
        }
        var headers: [String: String] = ["Content-Type": "application/x-ndjson; profile=\"ohe.wire/1\""]
        if let bearer = destination.authorizationBearer {
            headers["Authorization"] = "Bearer " + bearer
        }
        let preview = HTTPPreview.render(
            method: "POST",
            url: destination.url.absoluteString,
            headers: headers,
            body: Data()
        )
        let previewText = String(decoding: preview, as: UTF8.self)
        let authenticateIndex = pin == nil ? 3 : 4
        onProgress?(authenticateIndex, total, .authenticate)
        guard !previewText.contains(destination.authorizationBearer ?? "\u{0}") || destination.authorizationBearer == nil else {
            return .failed(at: .authenticate, prior: steps)
        }

        let post: OutboundHTTPResponse
        do {
            post = try await transport.execute(
                OutboundHTTPRequest(
                    method: "POST",
                    url: destination.url,
                    headers: headers,
                    bodyFile: file
                )
            )
        } catch {
            return .failed(at: .sendCanary, prior: steps)
        }
        if post.status == 401 || post.status == 403 {
            return .failed(at: .authenticate, prior: steps)
        }
        steps.append(DestinationTestStepReport(name: .authenticate, outcome: .passed))
        onProgress?(authenticateIndex + 1, total, .sendCanary)
        guard (200..<300).contains(post.status) else {
            return .failed(at: .sendCanary, prior: steps)
        }
        steps.append(DestinationTestStepReport(name: .sendCanary, outcome: .passed))
        onProgress?(authenticateIndex + 2, total, .readResponse)
        steps.append(DestinationTestStepReport(name: .readResponse, outcome: .passed))

        if let entityURL, let expected {
            let get: OutboundHTTPResponse
            do {
                get = try await transport.execute(
                    OutboundHTTPRequest(method: "GET", url: entityURL, headers: headers, bodyFile: file)
                )
            } catch {
                return .failed(at: .readResponse, prior: steps)
            }
            guard (200..<300).contains(get.status),
                  HAEntityReadback.matches(declaration: expected, json: get.body)
            else {
                return .failed(at: .readResponse, prior: steps)
            }
        }

        return DestinationTestReport(verdict: .passed, steps: steps)
    }
}

public enum HAEntityReadback {
    public static func matches(declaration: MetricDeclaration, json: Data) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
            let attributes = object["attributes"] as? [String: Any]
        else {
            return false
        }
        if let unit = declaration.haUnit {
            guard attributes["unit_of_measurement"] as? String == unit else { return false }
        }
        if let deviceClass = declaration.haDeviceClass {
            guard attributes["device_class"] as? String == deviceClass else { return false }
        }
        if let stateClass = declaration.haStateClass {
            guard attributes["state_class"] as? String == stateClass else { return false }
        }
        return true
    }
}
