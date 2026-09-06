import CoreDomain
import EnginePorts
import Foundation
import MQTTCodec
import NetEgress
import WireFormat

public protocol MQTTBytePipe: Sendable {
    func send(_ data: Data) async throws
    func receive(max: Int) async throws -> Data
}

public struct MQTTDestination: Sendable {
    public var url: URL
    public var clientID: String
    public var topic: String
    public var qos: MQTTQoS
    public var username: String?
    public var password: String?

    public init(
        urlString: String,
        allowedHosts: Set<String>,
        allowInsecure: Bool = false,
        clientID: String,
        topic: String,
        qos: MQTTQoS = .atLeastOnce,
        username: String? = nil,
        password: String? = nil
    ) throws {
        self.url = try EgressURL.parse(
            urlString,
            allowedHosts: allowedHosts,
            allowInsecureHTTP: allowInsecure
        )
        try MQTTTopic.validate(topic)
        self.clientID = clientID
        self.topic = topic
        self.qos = qos
        self.username = username
        self.password = password
    }
}

public actor MQTTSession {
    private let pipe: any MQTTBytePipe
    private var inbound = Data()
    private var nextID: UInt16 = 1

    public init(pipe: any MQTTBytePipe) {
        self.pipe = pipe
    }

    public func connect(destination: MQTTDestination) async throws {
        let packet = try MQTTCodec.connect(
            clientID: destination.clientID,
            username: destination.username,
            password: destination.password
        )
        try await pipe.send(packet)
        let (kind, _, body, _) = try await readPacket()
        guard kind == .connack else { throw MQTTError.unexpectedPacket(kind.rawValue) }
        let code = try MQTTCodec.decodeConnack(body)
        if code != 0 { throw MQTTError.connack(code) }
    }

    public func publish(topic: String, payload: Data, qos: MQTTQoS, retain: Bool = false) async throws {
        if retain, !HADiscovery.retainAllowed(topic: topic, payload: payload) {
            throw MQTTError.retainForbidden
        }
        let id = nextPacketID()
        let packet = try MQTTCodec.publish(
            topic: topic,
            payload: payload,
            qos: qos,
            packetID: id,
            retain: retain
        )
        try await pipe.send(packet)
        if qos == .atLeastOnce {
            let (kind, _, body, _) = try await readPacket()
            guard kind == .puback else { throw MQTTError.unexpectedPacket(kind.rawValue) }
            let acked = try MQTTCodec.decodePuback(body)
            if acked != id { throw MQTTError.packetID }
        }
    }

    public func disconnect() async throws {
        try await pipe.send(try MQTTCodec.disconnect())
    }

    private func nextPacketID() -> UInt16 {
        let id = nextID
        nextID = nextID == 65_535 ? 1 : nextID + 1
        if id == 0 { return nextPacketID() }
        return id
    }

    private func readPacket() async throws -> (MQTTPacketKind, UInt8, Data, Int) {
        while true {
            if inbound.count >= 2 {
                do {
                    let packet = try MQTTCodec.decode(inbound)
                    inbound.removeFirst(packet.consumed)
                    return (packet.kind, packet.flags, packet.body, packet.consumed)
                } catch MQTTError.truncated {
                    break
                }
            }
            let chunk = try await pipe.receive(max: 4096)
            if chunk.isEmpty { throw MQTTError.truncated }
            inbound.append(chunk)
        }
        while true {
            let chunk = try await pipe.receive(max: 4096)
            if chunk.isEmpty { throw MQTTError.truncated }
            inbound.append(chunk)
            do {
                let packet = try MQTTCodec.decode(inbound)
                inbound.removeFirst(packet.consumed)
                return (packet.kind, packet.flags, packet.body, packet.consumed)
            } catch MQTTError.truncated {
                continue
            }
        }
    }
}

public struct MQTTSink: DestinationSink, Sendable {
    public var destination: MQTTDestination
    public var pipe: any MQTTBytePipe

    public init(destination: MQTTDestination, pipe: any MQTTBytePipe) {
        self.destination = destination
        self.pipe = pipe
    }

    public func send(fileHandle: String, idempotencyKey: BatchID) async throws -> DeliveryReceipt {
        let file = URL(fileURLWithPath: fileHandle)
        let payload = try Data(contentsOf: file)
        let count = NativeWire.countRecords(in: String(decoding: payload, as: UTF8.self))
        let session = MQTTSession(pipe: pipe)
        try await session.connect(destination: destination)
        try await session.publish(
            topic: destination.topic,
            payload: payload,
            qos: destination.qos,
            retain: false
        )
        try await session.disconnect()
        if destination.qos == .atMostOnce {
            return DeliveryReceipt(batchID: idempotencyKey, accepted: 0, statusOnly: false, unconfirmed: count)
        }
        return DeliveryReceipt(batchID: idempotencyKey, accepted: count, statusOnly: false)
    }

    /// Host, port and TLS taken from the already-allowlisted destination URL.
    public static func streamEndpoint(for destination: MQTTDestination) throws -> StreamEndpoint {
        guard let host = destination.url.host, !host.isEmpty else { throw EgressError.invalidURL }
        let scheme = destination.url.scheme?.lowercased() ?? ""
        let usesTLS = scheme == "mqtts"
        let fallback: UInt16 = usesTLS ? 8883 : 1883
        let port: UInt16
        if let explicit = destination.url.port {
            guard let narrowed = UInt16(exactly: explicit), narrowed != 0 else { throw StreamError.badPort }
            port = narrowed
        } else {
            port = fallback
        }
        return try StreamEndpoint(host: host, port: port, usesTLS: usesTLS)
    }
}

#if canImport(Network)
extension MQTTSink {
    /// Dials with `NetEgress`'s byte stream. A pin is the trust decision for `mqtts`
    /// (self-signed home brokers); plaintext `mqtt` ignores it.
    public static func overNetwork(destination: MQTTDestination, pin: PinRecord?) throws -> MQTTSink {
        let stream = NWByteStream(
            endpoint: try streamEndpoint(for: destination),
            options: NWByteStream.Options(pin: pin, failFastOnWaiting: true)
        )
        return MQTTSink(destination: destination, pipe: ByteStreamMQTTPipe(stream: stream))
    }
}
#endif
