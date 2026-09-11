import EnginePorts
import Foundation
import NetEgress

public struct OTLPExportSettings: Sendable {
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
        let file = bodyDirectory.appendingPathComponent("otlp-traces.pb")
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
