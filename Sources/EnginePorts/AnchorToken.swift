// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Opaque to the core. `format` is bumped when the adapter encoding changes (R-86).
public struct AnchorToken: Sendable, Hashable, Codable {
    public var format: Int
    public var bytes: Data

    public init(format: Int, bytes: Data) {
        self.format = format
        self.bytes = bytes
    }

    public static let currentFormat = 1

    public func envelope() -> Data {
        var data = Data("OHEA".utf8)
        data.append(UInt8(format))
        let count = UInt32(bytes.count)
        data.append(UInt8((count >> 24) & 0xFF))
        data.append(UInt8((count >> 16) & 0xFF))
        data.append(UInt8((count >> 8) & 0xFF))
        data.append(UInt8(count & 0xFF))
        data.append(bytes)
        return data
    }

    public static func fromEnvelope(_ data: Data) throws -> AnchorToken {
        guard data.count >= 9, data.prefix(4) == Data("OHEA".utf8) else {
            throw AnchorTokenError.corrupt
        }
        let format = Int(data[4])
        let countBytes = Array(data[5..<9])
        let count = UInt32(countBytes[0]) << 24
            | UInt32(countBytes[1]) << 16
            | UInt32(countBytes[2]) << 8
            | UInt32(countBytes[3])
        let payload = data.dropFirst(9)
        guard payload.count == Int(count) else { throw AnchorTokenError.corrupt }
        return AnchorToken(format: format, bytes: Data(payload))
    }
}

public enum AnchorTokenError: Error {
    case corrupt
    case unsupportedFormat
}
