// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import EnginePorts
import Foundation

/// R-09 / R-84: gap records from a seeded fill-the-queue run are byte-stable NDJSON.
public enum GapRecordCanonical {
    private struct Line: Encodable {
        var batchID: String
        var expectedRecords: Int
        var metric: String
        var rangeDescription: String
        var rangeEndDay: String?
        var rangeStartDay: String?
    }

    public static func ndjson(_ gaps: [GapRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let lines = try gaps.map { gap in
            let data = try encoder.encode(
                Line(
                    batchID: gap.batchID.rawValue,
                    expectedRecords: gap.expectedRecords,
                    metric: gap.metric.rawValue,
                    rangeDescription: gap.rangeDescription,
                    rangeEndDay: gap.rangeEndDay,
                    rangeStartDay: gap.rangeStartDay
                )
            )
            return String(decoding: data, as: UTF8.self)
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }
}
