// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import EnginePorts
import Foundation
import NetEgress
import OTLPExport

@main
struct OTLPContract {
    static func main() async throws {
        let raw = ProcessInfo.processInfo.environment["OHE_OTLP_ENDPOINT"]
            ?? "http://127.0.0.1:4318/v1/traces"
        guard let url = URL(string: raw), let host = url.host else {
            throw ContractError.endpoint
        }
        let destination = try HTTPSDestination(
            urlString: raw,
            allowedHosts: [host],
            allowInsecureHTTP: url.scheme == "http"
        )
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ohe-otlp-contract-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let event = RunEvent(
            runID: RunID(rawValue: "00000000-0000-4000-8000-000000000053"),
            outcomeKind: RunOutcome.Kind.success.rawValue,
            detail: "",
            trigger: .manual,
            wallTimeEpoch: 1_700_000_000
        )
        let sent = try await OTLPExporter(
            settings: OTLPExportSettings(enabled: true, endpoint: destination),
            transport: SystemHTTPTransport.make()
        ).export(events: [event], bodyDirectory: directory)
        guard sent else { throw ContractError.notSent }
        print("otlpcontract: sent one export.run span")
    }
}

enum ContractError: Error {
    case endpoint
    case notSent
}
