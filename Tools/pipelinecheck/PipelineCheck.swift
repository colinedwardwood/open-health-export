// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import WireFormat

/// Stream `ohe.wire/1` NDJSON from stdin and validate every line against the committed schema.
@main
struct PipelineCheck {
    static func main() throws {
        let schemaPath = CommandLine.arguments.dropFirst().first
            ?? "spec/v1.0.0/schema/ohe.wire.1.json"
        let schema = try WireJSONSchema.load(Data(contentsOf: URL(fileURLWithPath: schemaPath)))
        var count = 0
        var concentratedHeartPrefix = 0
        var prefixOpen = true
        var years: Set<String> = []
        while let line = readLine(strippingNewline: true) {
            if line.isEmpty { continue }
            try WireJSONSchema.validateNDJSON(line, schema: schema)
            if count > 0 {
                let isHeartQuantity = line.contains(#""kind":"sample.quantity""#)
                    && line.contains(#""metricId":"heart_rate""#)
                if prefixOpen, isHeartQuantity {
                    concentratedHeartPrefix += 1
                } else {
                    prefixOpen = false
                }
                if let marker = line.range(of: #""start":""#) {
                    let start = marker.upperBound
                    let end = line.index(start, offsetBy: 4, limitedBy: line.endIndex)
                    if let end {
                        years.insert(String(line[start ..< end]))
                    }
                }
            }
            count += 1
        }
        let yearRange = years.isEmpty
            ? "none"
            : "\(years.min()!)-\(years.max()!)"
        FileHandle.standardOutput.write(
            Data(
                """
                pipelinecheck lines=\(count)
                pipelinecheck concentrated_heart_prefix=\(concentratedHeartPrefix) year_range=\(yearRange) distinct_years=\(years.count)

                """.utf8
            )
        )
        if count == 0 {
            FileHandle.standardError.write(Data("pipelinecheck received no records\n".utf8))
            exit(1)
        }
    }
}
