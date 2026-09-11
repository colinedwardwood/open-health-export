// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public enum CompanionFrameError: Error, Equatable {
    case truncated
    case tooLarge
    case badType(UInt8)
}

public enum CompanionFrameType: UInt8, Sendable {
    case hello = 1
    case offer = 2
    case resume = 3
    case receipt = 4
    case reject = 5
    case chunk = 6
    case chunkAck = 7
    case commit = 8
}

/// Length-prefixed frames. Pure codec — no Network.framework.
public struct CompanionFrame: Sendable, Equatable {
    public static let maxPayload = 1_048_576

    public var type: CompanionFrameType
    public var payload: Data

    public init(type: CompanionFrameType, payload: Data) {
        self.type = type
        self.payload = payload
    }

    public func encode() throws -> Data {
        guard payload.count <= Self.maxPayload else { throw CompanionFrameError.tooLarge }
        let length = UInt32(payload.count)
        var data = Data(CompanionBinary.u32(length))
        data.append(type.rawValue)
        data.append(payload)
        return data
    }

    /// Returns nil when `data` does not yet contain a full frame.
    public static func decodePrefix(_ data: Data) throws -> (frame: CompanionFrame, consumed: Int)? {
        let bytes = [UInt8](data)
        guard bytes.count >= 5 else { return nil }
        let length = CompanionBinary.readU32(bytes, at: 0)
        if length > UInt32(maxPayload) { throw CompanionFrameError.tooLarge }
        let total = 5 + Int(length)
        guard bytes.count >= total else { return nil }
        guard let type = CompanionFrameType(rawValue: bytes[4]) else {
            throw CompanionFrameError.badType(bytes[4])
        }
        let payload = Data(bytes[5..<total])
        return (CompanionFrame(type: type, payload: payload), total)
    }
}
