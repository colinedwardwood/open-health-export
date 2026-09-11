// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

enum CompanionBinary {
    static func u16(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }

    static func u32(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
    }

    static func u64(_ value: UInt64) -> [UInt8] {
        [
            UInt8((value >> 56) & 0xFF),
            UInt8((value >> 48) & 0xFF),
            UInt8((value >> 40) & 0xFF),
            UInt8((value >> 32) & 0xFF),
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
    }

    static func readU16(_ bytes: [UInt8], at i: Int) -> UInt16 {
        (UInt16(bytes[i]) << 8) | UInt16(bytes[i + 1])
    }

    static func readU32(_ bytes: [UInt8], at i: Int) -> UInt32 {
        (UInt32(bytes[i]) << 24)
            | (UInt32(bytes[i + 1]) << 16)
            | (UInt32(bytes[i + 2]) << 8)
            | UInt32(bytes[i + 3])
    }

    static func readU64(_ bytes: [UInt8], at i: Int) -> UInt64 {
        (UInt64(bytes[i]) << 56)
            | (UInt64(bytes[i + 1]) << 48)
            | (UInt64(bytes[i + 2]) << 40)
            | (UInt64(bytes[i + 3]) << 32)
            | (UInt64(bytes[i + 4]) << 24)
            | (UInt64(bytes[i + 5]) << 16)
            | (UInt64(bytes[i + 6]) << 8)
            | UInt64(bytes[i + 7])
    }

    static func writeString(_ string: String, into data: inout Data) throws {
        let utf8 = Array(string.utf8)
        guard utf8.count <= 65_535 else { throw CompanionCodecError.stringTooLong }
        data.append(contentsOf: u16(UInt16(utf8.count)))
        data.append(contentsOf: utf8)
    }

    static func readString(_ bytes: [UInt8], i: inout Int) throws -> String {
        guard i + 2 <= bytes.count else { throw CompanionCodecError.truncated }
        let length = Int(readU16(bytes, at: i))
        i += 2
        guard i + length <= bytes.count else { throw CompanionCodecError.truncated }
        let slice = bytes[i..<(i + length)]
        i += length
        // `String(bytes:encoding:)` goes through Foundation, which silently strips a leading
        // BOM, so a decoded frame would not re-encode to the bytes that arrived.
        guard let string = String(validating: slice, as: UTF8.self) else {
            throw CompanionCodecError.badUTF8
        }
        return string
    }
}

public enum CompanionCodecError: Error, Equatable {
    case truncated
    case badUTF8
    case badBoolean(UInt8)
    case stringTooLong
    case trailingBytes
    case protocolVersion
}
