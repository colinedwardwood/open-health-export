// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Incrementally reads newline-delimited records without retaining the input stream.
public struct NDJSONLineReader {
    private let handle: FileHandle
    private let chunkSize: Int
    private let maximumLineBytes: Int
    private var buffer: [UInt8] = []
    private var consumed = 0
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
            if let newline = newlineIndex() {
                let length = newline - consumed
                guard length <= maximumLineBytes else {
                    throw NDJSONLineReaderError.lineTooLong(maximumBytes: maximumLineBytes)
                }
                var line = Data(buffer[consumed..<newline])
                consumed = newline + 1
                if line.last == 0x0D {
                    line.removeLast()
                }
                compactIfStale()
                return line
            }
            if reachedEOF {
                let remaining = buffer.count - consumed
                guard remaining > 0 else { return nil }
                guard remaining <= maximumLineBytes else {
                    throw NDJSONLineReaderError.lineTooLong(maximumBytes: maximumLineBytes)
                }
                let line = Data(buffer[consumed..<buffer.count])
                buffer.removeAll(keepingCapacity: true)
                consumed = 0
                return line
            }
            let pending = buffer.count - consumed
            guard pending <= maximumLineBytes else {
                throw NDJSONLineReaderError.lineTooLong(maximumBytes: maximumLineBytes)
            }
            compactIfStale()
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty {
                reachedEOF = true
            } else {
                buffer.append(contentsOf: chunk)
            }
        }
    }

    private func newlineIndex() -> Int? {
        var index = consumed
        while index < buffer.count {
            if buffer[index] == 0x0A {
                return index
            }
            index += 1
        }
        return nil
    }

    /// Drop already-returned prefix in bulk so each line is not an O(buffer) memmove.
    private mutating func compactIfStale() {
        guard consumed > 0 else { return }
        if consumed == buffer.count {
            buffer.removeAll(keepingCapacity: true)
            consumed = 0
            return
        }
        guard consumed >= chunkSize else { return }
        buffer.removeFirst(consumed)
        consumed = 0
    }
}

public enum NDJSONLineReaderError: Error, Equatable {
    case lineTooLong(maximumBytes: Int)
}
