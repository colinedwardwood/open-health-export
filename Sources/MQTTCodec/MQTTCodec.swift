import Foundation

public enum MQTTPacketKind: UInt8, Sendable {
    case connect = 1
    case connack = 2
    case publish = 3
    case puback = 4
    case pingreq = 12
    case pingresp = 13
    case disconnect = 14
}

public enum MQTTError: Error, Equatable {
    case remainingLength
    case truncated
    case badUTF8
    case badTopic
    case connack(UInt8)
    case unexpectedPacket(UInt8)
    case packetID
    case retainForbidden
}

public enum MQTTQoS: UInt8, Sendable {
    case atMostOnce = 0
    case atLeastOnce = 1
}

public enum MQTTRemainingLength {
    public static func encode(_ value: Int) throws -> [UInt8] {
        guard value >= 0, value <= 268_435_455 else { throw MQTTError.remainingLength }
        var n = value
        var bytes: [UInt8] = []
        repeat {
            var encoded = UInt8(n % 128)
            n /= 128
            if n > 0 { encoded |= 0x80 }
            bytes.append(encoded)
        } while n > 0
        return bytes
    }

    public static func decode(_ data: Data, start: Int) throws -> (value: Int, consumed: Int) {
        let bytes = [UInt8](data)
        var multiplier = 1
        var value = 0
        var i = start
        var encoded: UInt8
        repeat {
            guard i < bytes.count else { throw MQTTError.truncated }
            encoded = bytes[i]
            i += 1
            value += Int(encoded & 0x7F) * multiplier
            if multiplier > 128 * 128 * 128 { throw MQTTError.remainingLength }
            multiplier *= 128
        } while encoded & 0x80 != 0
        return (value, i - start)
    }
}

public enum MQTTTopic {
    public static let maximumUTF8Count = 65_535

    public static func validate(_ topic: String) throws {
        if topic.isEmpty { throw MQTTError.badTopic }
        if topic.contains("#") || topic.contains("+") || topic.contains("\0") {
            throw MQTTError.badTopic
        }
        guard topic.utf8.count <= maximumUTF8Count else { throw MQTTError.badTopic }
    }
}

public enum MQTTCodec {
    public static func connect(
        clientID: String,
        keepAlive: UInt16 = 60,
        username: String? = nil,
        password: String? = nil
    ) throws -> Data {
        var flags: UInt8 = 0b0000_0010 // CleanSession=1
        var payload = Data()
        payload.append(try mqttString(clientID))
        if let username {
            flags |= 0b1000_0000
            payload.append(try mqttString(username))
        }
        if let password {
            flags |= 0b0100_0000
            payload.append(try mqttString(password))
        }
        var variable = Data()
        variable.append(try mqttString("MQTT"))
        variable.append(4) // protocol level 3.1.1
        variable.append(flags)
        variable.append(UInt8(keepAlive >> 8))
        variable.append(UInt8(keepAlive & 0xFF))
        variable.append(payload)
        return try wrap(kind: .connect, flags: 0, body: variable)
    }

    public static func disconnect() throws -> Data {
        try wrap(kind: .disconnect, flags: 0, body: Data())
    }

    public static func pingreq() throws -> Data {
        try wrap(kind: .pingreq, flags: 0, body: Data())
    }

    public static func publish(
        topic: String,
        payload: Data,
        qos: MQTTQoS,
        packetID: UInt16,
        retain: Bool = false
    ) throws -> Data {
        try MQTTTopic.validate(topic)
        if qos == .atLeastOnce, packetID == 0 { throw MQTTError.packetID }
        var flags: UInt8 = qos.rawValue << 1
        if retain { flags |= 0b0000_0001 }
        var body = Data()
        body.append(try mqttString(topic))
        if qos != .atMostOnce {
            body.append(UInt8(packetID >> 8))
            body.append(UInt8(packetID & 0xFF))
        }
        body.append(payload)
        return try wrap(kind: .publish, flags: flags, body: body)
    }

    public static func decode(_ data: Data) throws -> (kind: MQTTPacketKind, flags: UInt8, body: Data, consumed: Int) {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { throw MQTTError.truncated }
        let header = bytes[0]
        let typeRaw = header >> 4
        guard let kind = MQTTPacketKind(rawValue: typeRaw) else {
            throw MQTTError.unexpectedPacket(typeRaw)
        }
        let (length, lengthBytes) = try MQTTRemainingLength.decode(data, start: 1)
        let headerSize = 1 + lengthBytes
        let end = headerSize + length
        guard bytes.count >= end else { throw MQTTError.truncated }
        let body = Data(bytes[headerSize..<end])
        return (kind, header & 0x0F, body, end)
    }

    public static func decodeConnack(_ body: Data) throws -> UInt8 {
        let bytes = [UInt8](body)
        guard bytes.count >= 2 else { throw MQTTError.truncated }
        return bytes[1]
    }

    public static func decodePuback(_ body: Data) throws -> UInt16 {
        let bytes = [UInt8](body)
        guard bytes.count >= 2 else { throw MQTTError.truncated }
        return UInt16(bytes[0]) << 8 | UInt16(bytes[1])
    }

    public static func decodePublishTopic(body: Data) throws -> String {
        var i = 0
        return try readMQTTString(body, start: &i).0
    }

    public static func decodePublishPacketID(flags: UInt8, body: Data) throws -> UInt16? {
        let qos = (flags >> 1) & 0b11
        guard qos > 0 else { return nil }
        var i = 0
        _ = try readMQTTString(body, start: &i)
        let bytes = [UInt8](body)
        guard bytes.count >= i + 2 else { throw MQTTError.truncated }
        return UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1])
    }
}

func wrap(kind: MQTTPacketKind, flags: UInt8, body: Data) throws -> Data {
    var packet = Data()
    packet.append((kind.rawValue << 4) | flags)
    packet.append(contentsOf: try MQTTRemainingLength.encode(body.count))
    packet.append(body)
    return packet
}

func mqttString(_ value: String) throws -> Data {
    guard let utf = value.data(using: .utf8), utf.count <= 65_535 else { throw MQTTError.badUTF8 }
    var data = Data([UInt8(utf.count >> 8), UInt8(utf.count & 0xFF)])
    data.append(utf)
    return data
}

func readMQTTString(_ data: Data, start: inout Int) throws -> (String, Int) {
    let bytes = [UInt8](data)
    guard bytes.count >= start + 2 else { throw MQTTError.truncated }
    let length = Int(bytes[start]) << 8 | Int(bytes[start + 1])
    start += 2
    guard bytes.count >= start + length else { throw MQTTError.truncated }
    let slice = Data(bytes[start..<(start + length)])
    start += length
    guard let string = String(data: slice, encoding: .utf8) else { throw MQTTError.badUTF8 }
    return (string, length)
}
