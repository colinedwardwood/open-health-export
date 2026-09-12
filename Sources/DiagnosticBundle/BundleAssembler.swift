// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import EnginePorts
import Foundation
import Redaction

public enum DiagnosticDegradation: String, Sendable, Equatable, CaseIterable {
    case networkUnavailable = "network_unavailable"
    case healthAuthorizationLimited = "health_authorization_limited"
    case destinationConfigurationInvalid = "destination_configuration_invalid"
    case databaseUnreadable = "database_unreadable"
    case sqliteIntegrityCheckFailed = "sqlite_integrity_check_failed"
    case journalUnreadable = "journal_unreadable"
}

public struct DiagnosticHeader: Sendable, Equatable {
    public var appVersion: String
    public var osVersion: String
    public var deviceModel: String
    public var localeIdentifier: String
    public var utcOffsetMinutes: Int
    public var generatedAt: String
    public var degraded: [String]
    public var sourceCommit: String
    public var buildHash: String

    public init(
        appVersion: String,
        osVersion: String,
        deviceModel: String,
        localeIdentifier: String,
        utcOffsetMinutes: Int,
        generatedAt: String,
        degraded: [String] = [],
        sourceCommit: String = "",
        buildHash: String = ""
    ) {
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.localeIdentifier = localeIdentifier
        self.utcOffsetMinutes = utcOffsetMinutes
        self.generatedAt = generatedAt
        self.degraded = degraded
        self.sourceCommit = sourceCommit
        self.buildHash = buildHash
    }
}

public enum DiagnosticBundleError: Error, Equatable {
    case exceedsByteLimit(actual: Int, limit: Int)
}

public struct BundleAssembler: Sendable {
    /// Retained API name; this is the minimum run count in the R-26 union window.
    public var maxRuns: Int
    public var windowSeconds: TimeInterval
    public var maxBytes: Int

    public init(
        maxRuns: Int = 30,
        windowSeconds: TimeInterval = 24 * 60 * 60,
        maxBytes: Int = 200 * 1024
    ) {
        self.maxRuns = maxRuns
        self.windowSeconds = windowSeconds
        self.maxBytes = maxBytes
    }

    public func previewLines(events: [RunEvent]) -> [String] {
        events.enumerated().map { index, event in
            let fields = ["outcome": event.outcomeKind, "runID": "bundle-run-\(index + 1)"]
            return fields.keys.filter { Allowlist.permitted($0, in: .bundle) }.sorted()
                .map { "\($0)=\(fields[$0] ?? "")" }
                .joined(separator: " ")
        }
    }

    public func assemble(header: DiagnosticHeader, events: [RunEvent]) throws -> Data {
        let selected = selectedEvents(events, generatedAt: header.generatedAt)
        let runs: [[String: Any]] = selected.enumerated().map { index, event in
            var candidates: [String: Any] = [
                "runID": "bundle-run-\(index + 1)",
                "outcome": event.outcomeKind,
                "trigger": event.trigger.rawValue,
                "samplesRead": event.samplesRead,
                "samplesCommitted": event.samplesCommitted,
                "samplesAcked": event.samplesAcked,
                // `detail` is intentionally absent: its String type can hold arbitrary text.
            ]
            if let errorClass = event.errorClass {
                candidates["errorClass"] = errorClass
            }
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
                "sourceCommit": header.sourceCommit,
                "buildHash": header.buildHash,
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

    private func selectedEvents(
        _ events: [RunEvent],
        generatedAt: String
    ) -> [RunEvent] {
        let minimumStart = max(0, events.count - max(0, maxRuns))
        guard let generated = ISO8601DateFormatter().date(from: generatedAt) else {
            return Array(events[minimumStart...])
        }
        let cutoff = generated.timeIntervalSince1970 - max(0, windowSeconds)
        return events.enumerated().compactMap { index, event in
            index >= minimumStart || event.wallTimeEpoch >= cutoff ? event : nil
        }
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
