// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import EnginePorts
import Foundation
import NetEgress

public enum OTLPExportError: Error, Equatable {
    case previewRequired
    case endpointRequired
}

public struct OTLPExportSettings: Sendable, Equatable {
    public var enabled: Bool
    public var endpoint: HTTPSDestination?

    public init(enabled: Bool = false, endpoint: HTTPSDestination? = nil) {
        self.enabled = enabled
        self.endpoint = endpoint
    }

    public static let disabled = OTLPExportSettings()
}

public struct OTLPExporter: Sendable {
    public var settings: OTLPExportSettings
    public var transport: any HTTPTransport

    public init(settings: OTLPExportSettings, transport: any HTTPTransport) {
        self.settings = settings
        self.transport = transport
    }

    /// Returns false when disabled so callers can skip work. Never constructs a request then.
    public func export(events: [RunEvent], bodyDirectory: URL) async throws -> Bool {
        guard settings.enabled, let destination = settings.endpoint, !events.isEmpty else {
            return false
        }
        let payload = OTLPProjector.traces(events: events)
        return try await post(
            payload,
            filename: "otlp-traces.pb",
            destination: destination,
            bodyDirectory: bodyDirectory
        )
    }

    public func exportMetrics(
        destinations: [OTLPMetricsDestination],
        nowEpoch: TimeInterval,
        endpoint: HTTPSDestination,
        bodyDirectory: URL
    ) async throws -> Bool {
        guard settings.enabled, !destinations.isEmpty else { return false }
        return try await post(
            OTLPMetricsProjector.metrics(destinations: destinations, nowEpoch: nowEpoch),
            filename: "otlp-metrics.pb",
            destination: endpoint,
            bodyDirectory: bodyDirectory
        )
    }

    private func post(
        _ payload: Data,
        filename: String,
        destination: HTTPSDestination,
        bodyDirectory: URL
    ) async throws -> Bool {
        let file = bodyDirectory.appendingPathComponent(filename)
        try payload.write(to: file, options: .atomic)
        let request = OutboundHTTPRequest(
            method: "POST",
            url: destination.url,
            headers: [
                "Content-Type": "application/x-protobuf",
            ],
            bodyFile: file
        )
        let response = try await transport.execute(request)
        guard (200 ..< 300).contains(response.status) else {
            throw EgressError.httpStatus(response.status)
        }
        return true
    }
}
