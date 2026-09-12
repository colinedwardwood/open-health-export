// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation
import NetEgress
import Testing

/// Prior-knowledge HTTP/2 over plaintext TCP so Linux CI can exercise the QA-10
/// framer without an in-repo TLS stack. Darwin still covers TLS+ALPN `h2`.
final class LocalHTTP2CleartextServer: @unchecked Sendable {
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var acceptThread: Thread?
    private var sawPreface = false
    private var requests = 0
    private(set) var port: UInt16 = 0

    var prefaceSeen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return sawPreface
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func start() throws {
        #if os(Linux)
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        guard fd >= 0 else { throw StreamError.badPort }
        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        #if os(Linux)
        addr.sin_family = sa_family_t(AF_INET)
        #else
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        #endif
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: in_addr_t(UInt32(0x7F00_0001).bigEndian))
        let bindStatus = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindStatus == 0, listen(fd, 8) == 0 else {
            _ = close(fd)
            throw StreamError.badPort
        }
        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameStatus = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        guard nameStatus == 0 else {
            _ = close(fd)
            throw StreamError.badPort
        }
        port = UInt16(bigEndian: UInt16(bound.sin_port))
        listenFD = fd
        let thread = Thread { [weak self] in
            self?.acceptLoop()
        }
        acceptThread = thread
        thread.start()
    }

    func stop() {
        let fd = listenFD
        listenFD = -1
        if fd >= 0 {
            #if canImport(Darwin)
            _ = Darwin.shutdown(fd, SHUT_RDWR)
            _ = Darwin.close(fd)
            #else
            _ = Glibc.shutdown(fd, Int32(SHUT_RDWR))
            _ = Glibc.close(fd)
            #endif
        }
        acceptThread = nil
        port = 0
    }

    deinit { stop() }

    private func acceptLoop() {
        while listenFD >= 0 {
            var addr = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let client = withUnsafeMutablePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(listenFD, $0, &len)
                }
            }
            if client < 0 {
                if listenFD < 0 { return }
                continue
            }
            handle(client: client)
        }
    }

    private func handle(client fd: Int32) {
        defer {
            #if canImport(Darwin)
            _ = Darwin.close(fd)
            #else
            _ = Glibc.close(fd)
            #endif
        }
        var inbound = Data()
        var prefaceOK = false
        while true {
            var buffer = [UInt8](repeating: 0, count: 4_096)
            let n = buffer.withUnsafeMutableBytes { raw in
                #if canImport(Darwin)
                Darwin.recv(fd, raw.baseAddress, raw.count, 0)
                #else
                Glibc.recv(fd, raw.baseAddress, raw.count, 0)
                #endif
            }
            if n <= 0 { return }
            inbound.append(contentsOf: buffer.prefix(Int(n)))
            if !prefaceOK {
                guard inbound.count >= HTTP2Frame.clientPreface.count else { continue }
                guard inbound.prefix(HTTP2Frame.clientPreface.count) == HTTP2Frame.clientPreface else { return }
                inbound.removeSubrange(0 ..< HTTP2Frame.clientPreface.count)
                prefaceOK = true
                lock.lock()
                sawPreface = true
                lock.unlock()
                _ = sendAll(fd, HTTP2Frame.settings([]))
            }
            while let frame = HTTP2Frame.pop(from: &inbound) {
                switch frame.type {
                case 0x4 where frame.flags & 0x1 == 0:
                    _ = sendAll(fd, HTTP2Frame.settingsAck())
                case 0x6:
                    _ = sendAll(fd, HTTP2Frame.pingAck(frame.payload))
                case 0x1, 0x0:
                    if frame.flags & 0x1 == 0x1 {
                        lock.lock()
                        requests += 1
                        lock.unlock()
                        _ = sendAll(fd, HTTP2Frame.status204(streamID: frame.streamID))
                        return
                    }
                default:
                    break
                }
            }
        }
    }

    private func sendAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var sent = 0
            let total = raw.count
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            while sent < total {
                let n: Int
                #if canImport(Darwin)
                n = Darwin.send(fd, base + sent, total - sent, 0)
                #else
                n = Glibc.send(fd, base + sent, total - sent, 0)
                #endif
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }
}

enum HTTP2CleartextClient {
    static func post(port: UInt16, path: String, body: Data) async throws {
        let stream = POSIXByteStream(
            endpoint: try StreamEndpoint.parse(
                "http://127.0.0.1:\(port)",
                allowedHosts: ["127.0.0.1"],
                allowInsecure: true
            )
        )
        try await stream.open()
        try await stream.send(HTTP2Frame.clientPreface + HTTP2Frame.settings([]))
        var inbound = Data()
        var settingsAcked = false
        var saw204 = false
        var posted = false
        do {
            for _ in 0 ..< 32 {
                inbound.append(try await stream.receive(max: 4_096))
                while let frame = HTTP2Frame.pop(from: &inbound) {
                    if frame.type == 0x4, frame.flags & 0x1 == 0 {
                        try await stream.send(HTTP2Frame.settingsAck())
                        settingsAcked = true
                    }
                    if frame.type == 0x1, frame.payload == Data([0x89]) {
                        saw204 = true
                    }
                }
                if settingsAcked, !posted {
                    try await stream.send(
                        HTTP2Frame.postHeaders(streamID: 1, path: path)
                            + HTTP2Frame.data(streamID: 1, body: body, endStream: true)
                    )
                    posted = true
                }
                if saw204 {
                    await stream.close()
                    return
                }
            }
        } catch {
            await stream.close()
            throw error
        }
        await stream.close()
        throw StreamError.transport("http2-cleartext")
    }
}

@Test func posixLoopbackSpeaksPriorKnowledgeHTTP2() async throws {
    let server = LocalHTTP2CleartextServer()
    try server.start()
    defer { server.stop() }
    try await HTTP2CleartextClient.post(port: server.port, path: "/hook", body: Data("gzip-body".utf8))
    #expect(server.prefaceSeen)
    #expect(server.requestCount == 1)
}
