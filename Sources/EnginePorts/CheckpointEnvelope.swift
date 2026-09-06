import Foundation

/// Versioned cursor row. Corrupt or forward-version envelopes fail closed (R-86);
/// they never decode as "no cursor yet".
public struct CheckpointEnvelope: Sendable, Equatable {
    public static let currentFormat = 1

    public var format: Int
    public var tzDatabaseVersion: String
    public var epoch: UInt32
    public var adapterAnchor: Data

    public init(
        format: Int = CheckpointEnvelope.currentFormat,
        tzDatabaseVersion: String,
        epoch: UInt32,
        adapterAnchor: Data
    ) {
        self.format = format
        self.tzDatabaseVersion = tzDatabaseVersion
        self.epoch = epoch
        self.adapterAnchor = adapterAnchor
    }

    public func encoded() -> Data {
        var data = Data("OHEC".utf8)
        data.append(UInt8(format))
        let tz = Array(tzDatabaseVersion.utf8)
        let tzCount = UInt16(tz.count)
        data.append(UInt8((tzCount >> 8) & 0xFF))
        data.append(UInt8(tzCount & 0xFF))
        data.append(contentsOf: tz)
        data.append(UInt8((epoch >> 24) & 0xFF))
        data.append(UInt8((epoch >> 16) & 0xFF))
        data.append(UInt8((epoch >> 8) & 0xFF))
        data.append(UInt8(epoch & 0xFF))
        let count = UInt32(adapterAnchor.count)
        data.append(UInt8((count >> 24) & 0xFF))
        data.append(UInt8((count >> 16) & 0xFF))
        data.append(UInt8((count >> 8) & 0xFF))
        data.append(UInt8(count & 0xFF))
        data.append(adapterAnchor)
        return data
    }

    public static func decoded(_ data: Data) throws -> CheckpointEnvelope {
        guard data.count >= 15, data.prefix(4) == Data("OHEC".utf8) else {
            throw CheckpointError.corrupt
        }
        let format = Int(data[4])
        let tzCount = Int(UInt16(data[5]) << 8 | UInt16(data[6]))
        guard data.count >= 15 + tzCount else { throw CheckpointError.corrupt }
        let tzStart = 7
        let tzEnd = tzStart + tzCount
        let tzBytes = data[tzStart..<tzEnd]
        guard let tz = String(bytes: tzBytes, encoding: .utf8) else {
            throw CheckpointError.corrupt
        }
        let epochStart = tzEnd
        let epoch = UInt32(data[epochStart]) << 24
            | UInt32(data[epochStart + 1]) << 16
            | UInt32(data[epochStart + 2]) << 8
            | UInt32(data[epochStart + 3])
        let lenStart = epochStart + 4
        let count = UInt32(data[lenStart]) << 24
            | UInt32(data[lenStart + 1]) << 16
            | UInt32(data[lenStart + 2]) << 8
            | UInt32(data[lenStart + 3])
        let payload = data.dropFirst(lenStart + 4)
        guard payload.count == Int(count) else { throw CheckpointError.corrupt }
        if format > currentFormat {
            throw CheckpointError.unsupportedFormat
        }
        return CheckpointEnvelope(
            format: format,
            tzDatabaseVersion: tz,
            epoch: epoch,
            adapterAnchor: Data(payload)
        )
    }
}

public enum CheckpointError: Error, Equatable {
    case corrupt
    case unsupportedFormat
}
