// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import WireFormat

/// Stream `ohe.wire/1` NDJSON from stdin and validate every line against the committed schema.
@main
struct PipelineCheck {
    private static let quantityKind = Data(#""kind":"sample.quantity""#.utf8)
    private static let heartMetric = Data(#""metricId":"heart_rate""#.utf8)
    private static let startField = Data(#""start":""#.utf8)

    static func main() throws {
        let schemaPath = CommandLine.arguments.dropFirst().first
            ?? "spec/v1.0.0/schema/ohe.wire.1.json"
        let compiled = WireJSONSchema.compile(
            try WireJSONSchema.load(Data(contentsOf: URL(fileURLWithPath: schemaPath)))
        )
        var count = 0
        var concentratedHeartPrefix = 0
        var prefixOpen = true
        var years: Set<String> = []
        var reader = NDJSONLineReader(handle: .standardInput)
        while let line = try reader.next() {
            if line.isEmpty { continue }
            let instance = try JSONSerialization.jsonObject(with: line)
            try WireJSONSchema.validate(instance: instance, compiled: compiled)
            if count > 0 {
                let isHeartQuantity = line.range(of: quantityKind) != nil
                    && line.range(of: heartMetric) != nil
                if prefixOpen, isHeartQuantity {
                    concentratedHeartPrefix += 1
                } else {
                    prefixOpen = false
                }
                if let marker = line.range(of: startField) {
                    let start = marker.upperBound
                    let end = line.index(start, offsetBy: 4, limitedBy: line.endIndex)
                    if let end {
                        if let year = String(data: line[start..<end], encoding: .utf8) {
                            years.insert(year)
                        }
                    }
                }
            }
            count += 1
            if count.isMultiple(of: 1_000_000) {
                FileHandle.standardError.write(
                    Data("pipelinecheck validated_lines=\(count)\n".utf8)
                )
            }
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
