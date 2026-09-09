import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Plaintext TCP stream for Linux Mosquitto (R-90) and other non-TLS dials.
/// TLS stays on `NWByteStream` (Darwin). A pin is ignored here because there is no handshake.
public actor POSIXByteStream: ByteStream {
    private let endpoint: StreamEndpoint
    private var fd: Int32 = -1

    public init(endpoint: StreamEndpoint) {
        self.endpoint = endpoint
    }

    public func identity() async -> TLSIdentity? { nil }

    public func open() async throws {
        if fd >= 0 { return }
        if endpoint.usesTLS { throw StreamError.unsupportedPlatform }
        fd = try Self.connect(host: endpoint.host, port: endpoint.port)
    }

    public func send(_ data: Data) async throws {
        try await open()
        try data.withUnsafeBytes { raw in
            var sent = 0
            let total = raw.count
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            while sent < total {
                let n = DarwinOrGlibc.send(fd, base + sent, total - sent, 0)
                if n <= 0 { throw StreamError.transport("send") }
                sent += n
            }
        }
    }

    public func receive(max: Int) async throws -> Data {
        try await open()
        var buffer = [UInt8](repeating: 0, count: max)
        let n = buffer.withUnsafeMutableBytes { raw in
            DarwinOrGlibc.recv(fd, raw.baseAddress, raw.count, 0)
        }
        if n == 0 { throw StreamError.closedByPeer }
        if n < 0 { throw StreamError.transport("recv") }
        return Data(buffer.prefix(Int(n)))
    }

    public func close() async {
        if fd >= 0 {
            DarwinOrGlibc.closeSocket(fd)
            fd = -1
        }
    }

    private static func connect(host: String, port: UInt16) throws -> Int32 {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var info: UnsafeMutablePointer<addrinfo>?
        let portString = String(port)
        let err = host.withCString { hostC in
            portString.withCString { portC in
                getaddrinfo(hostC, portC, &hints, &info)
            }
        }
        guard err == 0, let info else { throw StreamError.transport("getaddrinfo") }
        defer { freeaddrinfo(info) }
        var cursor: UnsafeMutablePointer<addrinfo>? = info
        var lastError = StreamError.transport("connect")
        while let current = cursor {
            let socketFD = socket(current.pointee.ai_family, current.pointee.ai_socktype, current.pointee.ai_protocol)
            if socketFD >= 0 {
                let connected = DarwinOrGlibc.connect(socketFD, current.pointee.ai_addr, current.pointee.ai_addrlen)
                if connected == 0 {
                    var timeout = timeval(tv_sec: 10, tv_usec: 0)
                    _ = setsockopt(
                        socketFD,
                        SOL_SOCKET,
                        SO_RCVTIMEO,
                        &timeout,
                        socklen_t(MemoryLayout<timeval>.size)
                    )
                    _ = setsockopt(
                        socketFD,
                        SOL_SOCKET,
                        SO_SNDTIMEO,
                        &timeout,
                        socklen_t(MemoryLayout<timeval>.size)
                    )
                    return socketFD
                }
                DarwinOrGlibc.closeSocket(socketFD)
                lastError = StreamError.transport("connect")
            }
            cursor = current.pointee.ai_next
        }
        throw lastError
    }
}

private enum DarwinOrGlibc {
    static func send(_ fd: Int32, _ buf: UnsafeRawPointer?, _ len: Int, _ flags: Int32) -> Int {
        #if canImport(Darwin)
        return Darwin.send(fd, buf, len, flags)
        #else
        return Glibc.send(fd, buf, len, flags)
        #endif
    }

    static func recv(_ fd: Int32, _ buf: UnsafeMutableRawPointer?, _ len: Int, _ flags: Int32) -> Int {
        #if canImport(Darwin)
        return Darwin.recv(fd, buf, len, flags)
        #else
        return Glibc.recv(fd, buf, len, flags)
        #endif
    }

    static func connect(
        _ fd: Int32,
        _ addr: UnsafePointer<sockaddr>?,
        _ len: socklen_t
    ) -> Int32 {
        #if canImport(Darwin)
        return Darwin.connect(fd, addr, len)
        #else
        return Glibc.connect(fd, addr, len)
        #endif
    }

    static func closeSocket(_ fd: Int32) {
        #if canImport(Darwin)
        _ = Darwin.close(fd)
        #else
        _ = Glibc.close(fd)
        #endif
    }
}
