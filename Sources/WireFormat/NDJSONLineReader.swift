// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Incrementally reads newline-delimited records without retaining the input stream.
public struct NDJSONLineReader {
    private let handle: FileHandle
    private let chunkSize: Int
    private let maximumLineBytes: Int
    private var buffer = Data()
    private var reachedEOF = false

    public init(
        handle: FileHandle,
        chunkSize: Int = 64 * 1_024,
        maximumLineBytes: Int = 1 * 1_024 * 1_024
    ) {
        self.handle = handle
        self.chunkSize = chunkSize
        self.maximumLineBytes = maximumLineBytes
    }

    public mutating func next() throws -> Data? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                guard newline <= maximumLineBytes else {
                    throw NDJSONLineReaderError.lineTooLong(maximumBytes: maximumLineBytes)
                }
                var line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if line.last == 0x0D {
                    line.removeLast()
                }
                return line
            }
            if reachedEOF {
                guard !buffer.isEmpty else { return nil }
                guard buffer.count <= maximumLineBytes else {
                    throw NDJSONLineReaderError.lineTooLong(maximumBytes: maximumLineBytes)
                }
                let line = buffer
                buffer.removeAll(keepingCapacity: true)
                return line
            }
            guard buffer.count <= maximumLineBytes else {
                throw NDJSONLineReaderError.lineTooLong(maximumBytes: maximumLineBytes)
            }
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty {
                reachedEOF = true
            } else {
                buffer.append(chunk)
            }
        }
    }
}

public enum NDJSONLineReaderError: Error, Equatable {
    case lineTooLong(maximumBytes: Int)
}
