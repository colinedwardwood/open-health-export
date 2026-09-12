// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Plaintext TCP stream for Linux Mosquitto (R-90) and other non-TLS dials.
/// TLS stays on `NWByteStream` (Darwin). A pin is ignored here because there is no handshake.
/// Blocking `connect`/`send`/`recv` run on a libdispatch queue so they cannot stall Swift's
/// cooperative thread pool (Linux CI `swift test` otherwise deadlocks).
public actor POSIXByteStream: ByteStream {
    private let endpoint: StreamEndpoint
    private let resolver: any AddressResolver
    private var fd: Int32 = -1

    public init(endpoint: StreamEndpoint, resolver: any AddressResolver = SystemAddressResolver()) {
        self.endpoint = endpoint
        self.resolver = resolver
    }

    public func identity() async -> TLSIdentity? { nil }

    public func open() async throws {
        if fd >= 0 { return }
        EgressAttemptLog.record(kind: .byteStream, host: endpoint.host)
        if endpoint.usesTLS { throw StreamError.unsupportedPlatform }
        let host = endpoint.host
        let port = endpoint.port
        let policy = endpoint.addressPolicy
        let resolver = self.resolver
        fd = try await Self.offPool {
            let address = try ConnectTimeAddressGate.connectionAddress(
                host: host,
                policy: policy,
                resolver: resolver
            )
            return try Self.connect(host: address, port: port, numericHost: policy == .requireLocal)
        }
    }

    public func send(_ data: Data) async throws {
        try await open()
        EgressAttemptLog.record(kind: .byteStream, host: endpoint.host, bytes: data.count)
        let socket = fd
        try await Self.offPool {
            try data.withUnsafeBytes { raw in
                var sent = 0
                let total = raw.count
                let base = raw.bindMemory(to: UInt8.self).baseAddress!
                while sent < total {
                    try Self.wait(fd: socket, events: Int16(POLLOUT))
                    let n = DarwinOrGlibc.send(socket, base + sent, total - sent, 0)
                    if n <= 0 { throw StreamError.transport("send") }
                    sent += n
                }
            }
        }
    }

    public func receive(max: Int) async throws -> Data {
        try await open()
        let socket = fd
        return try await Self.offPool {
            try Self.wait(fd: socket, events: Int16(POLLIN))
            var buffer = [UInt8](repeating: 0, count: max)
            let n = buffer.withUnsafeMutableBytes { raw in
                DarwinOrGlibc.recv(socket, raw.baseAddress, raw.count, 0)
            }
            if n == 0 { throw StreamError.closedByPeer }
            if n < 0 {
                throw StreamError.transport("recv: \(String(cString: strerror(errno)))")
            }
            return Data(buffer.prefix(Int(n)))
        }
    }

    public func close() async {
        if fd >= 0 {
            DarwinOrGlibc.closeSocket(fd)
            fd = -1
        }
    }

    private static func offPool<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func wait(fd: Int32, events: Int16, milliseconds: Int32 = 10_000) throws {
        var fds = [pollfd(fd: fd, events: events, revents: 0)]
        let ready = poll(&fds, nfds_t(1), milliseconds)
        if ready == 0 { throw StreamError.transport("io timeout") }
        if ready < 0 { throw StreamError.transport("poll") }
    }

    private static func connect(host: String, port: UInt16, numericHost: Bool) throws -> Int32 {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        #if os(Linux)
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        #else
        hints.ai_socktype = SOCK_STREAM
        #endif
        if numericHost {
            hints.ai_flags = AI_NUMERICHOST
        }
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
                    Self.applyIOTimeout(socketFD)
                    return socketFD
                }
                DarwinOrGlibc.closeSocket(socketFD)
                lastError = StreamError.transport("connect")
            }
            cursor = current.pointee.ai_next
        }
        throw lastError
    }

    private static func applyIOTimeout(_ socketFD: Int32) {
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
