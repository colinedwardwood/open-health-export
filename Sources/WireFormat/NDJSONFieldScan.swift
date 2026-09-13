// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Extracts unescaped JSON string fields from a single NDJSON object without decoding it.
///
/// Volume ingest only needs `kind` and `metricId`. Those values are closed ASCII tokens
/// in the synthetic corpus, so a byte scan is enough. A backslash in the value returns
/// nil so callers fall back to `JSONDecoder`.
public enum NDJSONFieldScan {
    public static func unescapedString(named field: String, in line: Data) -> String? {
        var needle = Data([0x22])
        needle.append(contentsOf: field.utf8)
        needle.append(contentsOf: [0x22, 0x3A, 0x22])
        guard let range = line.range(of: needle) else { return nil }
        let start = range.upperBound
        var index = start
        while index < line.endIndex {
            let byte = line[index]
            if byte == 0x5C {
                return nil
            }
            if byte == 0x22 {
                return String(data: line[start..<index], encoding: .utf8)
            }
            index = line.index(after: index)
        }
        return nil
    }
}
