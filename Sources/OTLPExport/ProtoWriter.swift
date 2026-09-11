// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Length-delimited and varint protobuf enough for ExportTraceServiceRequest.
enum ProtoWriter {
    static func field(_ number: UInt32, string: String) -> Data {
        field(number, bytes: Data(string.utf8))
    }

    static func field(_ number: UInt32, bytes: Data) -> Data {
        var out = varint(UInt64(number << 3 | 2))
        out.append(varint(UInt64(bytes.count)))
        out.append(bytes)
        return out
    }

    static func field(_ number: UInt32, uint64: UInt64) -> Data {
        var out = varint(UInt64(number << 3 | 0))
        out.append(varint(uint64))
        return out
    }

    static func fieldFixed64(_ number: UInt32, value: UInt64) -> Data {
        var out = varint(UInt64(number << 3 | 1))
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { out.append(contentsOf: $0) }
        return out
    }

    static func varint(_ value: UInt64) -> Data {
        var remaining = value
        var out = Data()
        while remaining >= 0x80 {
            out.append(UInt8(remaining & 0x7F) | 0x80)
            remaining >>= 7
        }
        out.append(UInt8(remaining))
        return out
    }
}
