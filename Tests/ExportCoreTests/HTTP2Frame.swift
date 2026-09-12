// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

enum HTTP2Frame {
    static let clientPreface = Data("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".utf8)

    static func pop(from buffer: inout Data) -> (type: UInt8, flags: UInt8, streamID: UInt32, payload: Data)? {
        guard buffer.count >= 9 else { return nil }
        let length = Int(buffer[0]) << 16 | Int(buffer[1]) << 8 | Int(buffer[2])
        guard buffer.count >= 9 + length else { return nil }
        let type = buffer[3]
        let flags = buffer[4]
        let streamID =
            (UInt32(buffer[5]) << 24 | UInt32(buffer[6]) << 16 | UInt32(buffer[7]) << 8 | UInt32(buffer[8]))
            & 0x7FFF_FFFF
        let payload = buffer.subdata(in: 9 ..< (9 + length))
        buffer.removeSubrange(0 ..< (9 + length))
        return (type, flags, streamID, payload)
    }

    static func encode(type: UInt8, flags: UInt8, streamID: UInt32, payload: Data) -> Data {
        var header = Data(count: 9)
        header[0] = UInt8((payload.count >> 16) & 0xFF)
        header[1] = UInt8((payload.count >> 8) & 0xFF)
        header[2] = UInt8(payload.count & 0xFF)
        header[3] = type
        header[4] = flags
        header[5] = UInt8((streamID >> 24) & 0x7F)
        header[6] = UInt8((streamID >> 16) & 0xFF)
        header[7] = UInt8((streamID >> 8) & 0xFF)
        header[8] = UInt8(streamID & 0xFF)
        return header + payload
    }

    static func settings(_ entries: [(UInt16, UInt32)]) -> Data {
        var payload = Data()
        for (id, value) in entries {
            payload.append(UInt8(id >> 8))
            payload.append(UInt8(id & 0xFF))
            payload.append(UInt8((value >> 24) & 0xFF))
            payload.append(UInt8((value >> 16) & 0xFF))
            payload.append(UInt8((value >> 8) & 0xFF))
            payload.append(UInt8(value & 0xFF))
        }
        return encode(type: 0x4, flags: 0, streamID: 0, payload: payload)
    }

    static func settingsAck() -> Data {
        encode(type: 0x4, flags: 0x1, streamID: 0, payload: Data())
    }

    static func pingAck(_ payload: Data) -> Data {
        encode(type: 0x6, flags: 0x1, streamID: 0, payload: payload)
    }

    /// Indexed `:status: 204` (static table index 9).
    static func status204(streamID: UInt32) -> Data {
        encode(type: 0x1, flags: 0x5, streamID: streamID, payload: Data([0x89]))
    }

    /// Indexed `:method POST` / `:scheme http` plus a literal `:path`.
    static func postHeaders(streamID: UInt32, path: String) -> Data {
        var payload = Data([0x83, 0x86, 0x04, UInt8(path.utf8.count)])
        payload.append(contentsOf: path.utf8)
        return encode(type: 0x1, flags: 0x4, streamID: streamID, payload: payload)
    }

    static func data(streamID: UInt32, body: Data, endStream: Bool) -> Data {
        encode(type: 0x0, flags: endStream ? 0x1 : 0, streamID: streamID, payload: body)
    }
}
