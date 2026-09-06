import CoreDomain
import EnginePorts
import Foundation
import Redaction

public struct DiagnosticHeader: Sendable, Equatable {
    public var appVersion: String
    public var osVersion: String
    public var deviceModel: String
    public var localeIdentifier: String
    public var utcOffsetMinutes: Int
    public var generatedAt: String
    public var degraded: [String]

    public init(
        appVersion: String,
        osVersion: String,
        deviceModel: String,
        localeIdentifier: String,
        utcOffsetMinutes: Int,
        generatedAt: String,
        degraded: [String] = []
    ) {
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.localeIdentifier = localeIdentifier
        self.utcOffsetMinutes = utcOffsetMinutes
        self.generatedAt = generatedAt
        self.degraded = degraded
    }
}

public enum DiagnosticBundleError: Error, Equatable {
    case exceedsByteLimit(actual: Int, limit: Int)
}

public struct BundleAssembler: Sendable {
    public var maxRuns: Int
    public var maxBytes: Int

    public init(maxRuns: Int = 200, maxBytes: Int = 200 * 1024) {
        self.maxRuns = maxRuns
        self.maxBytes = maxBytes
    }

    public func previewLines(events: [RunEvent]) -> [String] {
        events.suffix(maxRuns).enumerated().map { index, event in
            let fields = ["outcome": event.outcomeKind, "runID": "bundle-run-\(index + 1)"]
            return fields.keys.filter { Allowlist.permitted($0, in: .bundle) }.sorted()
                .map { "\($0)=\(fields[$0] ?? "")" }
                .joined(separator: " ")
        }
    }

    public func assemble(header: DiagnosticHeader, events: [RunEvent]) throws -> Data {
        let runs: [[String: Any]] = events.suffix(maxRuns).enumerated().map { index, event in
            let candidates: [String: Any] = [
                "runID": "bundle-run-\(index + 1)",
                "outcome": event.outcomeKind,
                "trigger": event.trigger.rawValue,
                "samplesRead": event.samplesRead,
                "samplesCommitted": event.samplesCommitted,
                "samplesAcked": event.samplesAcked,
                // `detail` is intentionally absent: its String type can hold arbitrary text.
            ]
            return Dictionary(
                uniqueKeysWithValues: Allowlist.manifest.compactMap { permission in
                    guard permission.sinks.contains(.bundle),
                          let value = candidates[permission.key]
                    else { return nil }
                    return (permission.key, value)
                }
            )
        }
        let document: [String: Any] = [
            "schema": "ohe.diagnostic/1",
            "header": [
                "appVersion": header.appVersion,
                "osVersion": header.osVersion,
                "deviceModel": header.deviceModel,
                "localeIdentifier": header.localeIdentifier,
                "utcOffsetMinutes": header.utcOffsetMinutes,
                "generatedAt": header.generatedAt,
                "degraded": header.degraded.sorted(),
            ],
            "runs": runs,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: document,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        guard data.count <= maxBytes else {
            throw DiagnosticBundleError.exceedsByteLimit(actual: data.count, limit: maxBytes)
        }
        return data
    }
}

/// UI-facing existence gate: there is no share payload until full-content review is recorded.
public struct DiagnosticPreviewGate: Sendable {
    public private(set) var sharePayload: Data?

    public init() {}

    public mutating func reachedEnd(of fullPayload: Data) {
        sharePayload = fullPayload
    }
}
