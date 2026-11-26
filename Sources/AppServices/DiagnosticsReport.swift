// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import CoreDomain
import DiagnosticBundle
import Foundation
import NetEgress

/// The Settings > Diagnostics content: what the screen lists and what the share sheet
/// hands over are the same lines. Every line is built from allowlisted fields only. The
/// run list comes from the redacted bundle, launch failures show a stage and a known
/// error class, and network activity shows kinds and counts with the host withheld.
public struct DiagnosticsReport: Sendable, Equatable {
    public var buildLines: [String]
    public var exportLines: [String]
    public var launchLines: [String]
    public var networkLines: [String]

    public static let title = "KeepMyMetrics diagnostics"
    public static let noneLine = "None recorded."
    /// SEC-45: the warning shown before the report leaves the app.
    public static let shareDisclosure = ShareDisclosure.copy

    /// A line the screen can wrap at any Dynamic Type size.
    public static func wrappable(_ line: String) -> String {
        DiagnosticPreviewLayout.wrappable(line)
    }

    /// The plain text the share sheet carries.
    public var text: String {
        let sections = [
            ("Build", buildLines),
            ("Last exports", exportLines),
            ("Launch failures", launchLines),
            ("Network activity (hosts withheld)", networkLines),
        ]
        return ([Self.title] + sections.map { title, lines in
            "\n\(title)\n" + lines.joined(separator: "\n")
        }).joined(separator: "\n") + "\n"
    }

    /// `bundlePayload` is the redacted bundle from `BundleAssembler`.
    public static func make(
        bundlePayload: Data,
        launchIssues: [LaunchIssue],
        network: [NetworkActivityRow]
    ) -> DiagnosticsReport {
        let document = (try? JSONSerialization.jsonObject(with: bundlePayload)) as? [String: Any] ?? [:]
        let header = document["header"] as? [String: Any] ?? [:]
        let runs = document["runs"] as? [[String: Any]] ?? []
        let buildKeys = [
            ("App version", "appVersion"), ("Source commit", "sourceCommit"),
            ("Build hash", "buildHash"), ("OS", "osVersion"), ("Device", "deviceModel"),
            ("Generated", "generatedAt"),
        ]
        var buildLines = buildKeys.compactMap { label, key in
            (header[key] as? String).flatMap { $0.isEmpty ? nil : "\(label): \($0)" }
        }
        if let degraded = header["degraded"] as? [String], !degraded.isEmpty {
            buildLines.append("Degraded: " + degraded.joined(separator: ", "))
        }
        let runKeys = ["outcome", "trigger", "errorClass", "samplesRead", "samplesCommitted", "samplesAcked"]
        let exportLines = runs.reversed().map { run in
            runKeys.compactMap { key in run[key].map { "\(key)=\($0)" } }.joined(separator: " ")
        }
        let launchLines = launchIssues.sorted { $0.atEpoch > $1.atEpoch }.map { issue in
            // Only a known class is echoed; anything else could be free text.
            let errorClass = ErrorClass(rawValue: issue.errorClass)?.rawValue ?? "unknown"
            let when = Date(timeIntervalSince1970: issue.atEpoch).ISO8601Format()
            return "\(issue.stage.rawValue) errorClass=\(errorClass) at \(when)"
        }
        let networkLines = network.enumerated().map { index, row in
            "destination \(index + 1): \(row.kinds.sorted().joined(separator: ",")) · \(row.count) attempts · \(row.bytes) bytes"
        }
        return DiagnosticsReport(
            buildLines: buildLines,
            exportLines: exportLines.isEmpty ? [noneLine] : exportLines,
            launchLines: launchLines.isEmpty ? [noneLine] : launchLines,
            networkLines: networkLines.isEmpty ? [noneLine] : networkLines
        )
    }
}

extension TransparencyService {
    public func diagnosticsReport(
        environment: DiagnosticEnvironment,
        launchIssues: [LaunchIssue]
    ) throws -> DiagnosticsReport {
        attachNetworkActivityLedger()
        return DiagnosticsReport.make(
            bundlePayload: try diagnosticBundle(environment: environment).payload,
            launchIssues: launchIssues,
            network: EgressAttemptLog.persistentSnapshot()
        )
    }
}
