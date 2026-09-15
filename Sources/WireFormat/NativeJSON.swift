// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

enum NativeJSON {
    static let maxDocumentBytes = 2 * 1024 * 1024 * 1024

    static func document(
        fromNDJSON data: Data,
        maxBytes: Int = maxDocumentBytes
    ) throws -> (canonical: Data, pretty: Data) {
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            .map(String.init)
        var headerLine: String?
        var footerLine: String?
        var recordLines: [String] = []
        for line in lines {
            guard let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let kind = object["kind"] as? String
            else {
                throw WireError.utf8
            }
            switch kind {
            case "batch.header":
                headerLine = line
            case "batch.footer":
                footerLine = line
            default:
                recordLines.append(line)
            }
        }
        guard let headerLine, let footerLine else { throw WireError.utf8 }
        let canonical = "{\"footer\":\(footerLine),\"header\":\(headerLine),\"records\":[\(recordLines.joined(separator: ","))]}\n"
        let pretty = CanonicalJSON.prettyPrint(canonical)
        let canonicalData = Data(canonical.utf8)
        let prettyData = Data(pretty.utf8)
        guard canonicalData.count <= maxBytes, prettyData.count <= maxBytes else {
            throw WireError.documentExceedsByteLimit
        }
        return (canonicalData, prettyData)
    }

    /// Stream the JSON sidecar pair from an NDJSON file. Header/footer stay as two
    /// lines; records are copied through a temp file so the assembled document is
    /// never held together with pretty-print output.
    static func writeDocuments(
        fromNDJSONAt url: URL,
        canonical destCanonical: URL,
        pretty destPretty: URL,
        maxBytes: Int = maxDocumentBytes
    ) throws {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var reader = NDJSONLineReader(handle: input)
        var headerLine: String?
        var footerLine: String?
        let recordsTemp = destCanonical.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).records")
        FileManager.default.createFile(atPath: recordsTemp.path, contents: nil)
        let records = try FileHandle(forWritingTo: recordsTemp)
        defer {
            try? records.close()
            try? FileManager.default.removeItem(at: recordsTemp)
        }
        var recordBytes = 0
        var recordCount = 0
        while let line = try reader.next() {
            guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let kind = object["kind"] as? String
            else {
                throw WireError.utf8
            }
            switch kind {
            case "batch.header":
                headerLine = String(decoding: line, as: UTF8.self)
            case "batch.footer":
                footerLine = String(decoding: line, as: UTF8.self)
            default:
                if recordCount > 0 {
                    try records.write(contentsOf: Data(",".utf8))
                    recordBytes += 1
                }
                try records.write(contentsOf: line)
                recordBytes += line.count
                recordCount += 1
            }
        }
        guard let headerLine, let footerLine else { throw WireError.utf8 }
        try records.synchronize()
        let prefix = "{\"footer\":\(footerLine),\"header\":\(headerLine),\"records\":["
        let suffix = "]}\n"
        let total = prefix.utf8.count + recordBytes + suffix.utf8.count
        guard total <= maxBytes else {
            throw WireError.documentExceedsByteLimit
        }
        FileManager.default.createFile(atPath: destCanonical.path, contents: nil)
        let canonical = try FileHandle(forWritingTo: destCanonical)
        defer { try? canonical.close() }
        try canonical.write(contentsOf: Data(prefix.utf8))
        let replay = try FileHandle(forReadingFrom: recordsTemp)
        defer { try? replay.close() }
        while true {
            let chunk = try replay.read(upToCount: 64 * 1_024) ?? Data()
            if chunk.isEmpty { break }
            try canonical.write(contentsOf: chunk)
        }
        try canonical.write(contentsOf: Data(suffix.utf8))
        try canonical.synchronize()

        let compact = try Data(contentsOf: destCanonical, options: [.mappedIfSafe])
        FileManager.default.createFile(atPath: destPretty.path, contents: nil)
        let pretty = try FileHandle(forWritingTo: destPretty)
        defer { try? pretty.close() }
        try CanonicalJSON.prettyPrint(compact, to: pretty)
        try pretty.synchronize()
        let prettySize = try FileManager.default.attributesOfItem(atPath: destPretty.path)[.size]
            as? NSNumber
        guard (prettySize?.intValue ?? Int.max) <= maxBytes else {
            throw WireError.documentExceedsByteLimit
        }
    }
}
