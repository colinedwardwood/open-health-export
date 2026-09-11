// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// In-repo HTTP/1.1 loopback double (QA-10): programmable status, delay, headers, body,
/// chunked transfer, redirect, Retry-After, and mid-body reset. No third-party server.
public final class ScriptableHTTPServer: @unchecked Sendable {
    public struct Request: Sendable, Equatable {
        public var method: String
        public var target: String
        public var headers: [String: String]
        public var body: Data
    }

    public struct Script: Sendable {
        public var status: Int
        public var reason: String
        public var headers: [String: String]
        public var body: Data
        public var delayNanoseconds: UInt64
        public var chunkSize: Int?
        public var closeAfterBodyBytes: Int?
        public var slowLorisNanosecondsPerByte: UInt64

        public init(
            status: Int = 204,
            reason: String? = nil,
            headers: [String: String] = [:],
            body: Data = Data(),
            delayNanoseconds: UInt64 = 0,
            chunkSize: Int? = nil,
            closeAfterBodyBytes: Int? = nil,
            slowLorisNanosecondsPerByte: UInt64 = 0
        ) {
            self.status = status
            self.reason = reason ?? HTTPStatus.reason(status)
            self.headers = headers
            self.body = body
            self.delayNanoseconds = delayNanoseconds
            self.chunkSize = chunkSize
            self.closeAfterBodyBytes = closeAfterBodyBytes
            self.slowLorisNanosecondsPerByte = slowLorisNanosecondsPerByte
        }

        public static func json(_ object: [String: Any], status: Int = 200) throws -> Script {
            let data = try JSONSerialization.data(withJSONObject: object)
            return Script(
                status: status,
                headers: ["Content-Type": "application/json"],
                body: data
            )
        }
    }

    private let lock = NSLock()
    private var queued: [Script] = []
    private var fallback = Script()
    private var recorded: [Request] = []
    private var listenFD: Int32 = -1
    private var acceptThread: Thread?
    public private(set) var port: UInt16 = 0

    public init() {}

    public var origin: URL {
        URL(string: "http://127.0.0.1:\(port)")!
    }

    public func enqueue(_ script: Script) {
        lock.lock()
        queued.append(script)
        lock.unlock()
    }

    public func setFallback(_ script: Script) {
        lock.lock()
        fallback = script
        lock.unlock()
    }

    public func requests() -> [Request] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    public func start() throws {
        #if os(Linux)
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        guard fd >= 0 else { throw ScriptableHTTPError.bind }
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
        addr.sin_addr = in_addr(s_addr: posixHtonl(0x7F00_0001))
        let bindStatus = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindStatus == 0 else {
            POSIXSockets.close(fd)
            throw ScriptableHTTPError.bind
        }
        guard listen(fd, 16) == 0 else {
            POSIXSockets.close(fd)
            throw ScriptableHTTPError.bind
        }
        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameStatus = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        guard nameStatus == 0 else {
            POSIXSockets.close(fd)
            throw ScriptableHTTPError.bind
        }
        port = posixNtohs(bound.sin_port)
        listenFD = fd
        let thread = Thread { [weak self] in
            self?.acceptLoop()
        }
        thread.name = "ohe.scriptable-http"
        acceptThread = thread
        thread.start()
    }

    public func stop() {
        let fd = listenFD
        listenFD = -1
        if fd >= 0 {
            POSIXSockets.shutdown(fd)
            POSIXSockets.close(fd)
        }
        acceptThread?.cancel()
        acceptThread = nil
        port = 0
    }

    deinit {
        stop()
    }

    private func nextScript() -> Script {
        lock.lock()
        defer { lock.unlock() }
        if queued.isEmpty { return fallback }
        return queued.removeFirst()
    }

    private func record(_ request: Request) {
        lock.lock()
        recorded.append(request)
        lock.unlock()
    }

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
            var timeout = timeval(tv_sec: 15, tv_usec: 0)
            _ = setsockopt(
                client,
                SOL_SOCKET,
                SO_RCVTIMEO,
                &timeout,
                socklen_t(MemoryLayout<timeval>.size)
            )
            _ = setsockopt(
                client,
                SOL_SOCKET,
                SO_SNDTIMEO,
                &timeout,
                socklen_t(MemoryLayout<timeval>.size)
            )
            handle(client: client)
        }
    }

    private func handle(client fd: Int32) {
        defer { POSIXSockets.close(fd) }
        do {
            let request = try readRequest(fd: fd)
            record(request)
            let script = nextScript()
            if script.delayNanoseconds > 0 {
                var spec = timespec(
                    tv_sec: Int(script.delayNanoseconds / 1_000_000_000),
                    tv_nsec: Int(script.delayNanoseconds % 1_000_000_000)
                )
                _ = nanosleep(&spec, nil)
            }
            try writeResponse(fd: fd, script: script)
        } catch {
            return
        }
    }

    private func readRequest(fd: Int32) throws -> Request {
        var buffer = Data()
        let separator = Data("\r\n\r\n".utf8)
        while buffer.range(of: separator) == nil {
            buffer.append(try POSIXSockets.recv(fd, max: 4096))
            if buffer.count > 1_048_576 { throw ScriptableHTTPError.parse }
        }
        guard let split = buffer.range(of: separator) else { throw ScriptableHTTPError.parse }
        let head = buffer.subdata(in: buffer.startIndex..<split.lowerBound)
        var rest = buffer.subdata(in: split.upperBound..<buffer.endIndex)
        guard let headText = String(data: head, encoding: .utf8) else { throw ScriptableHTTPError.parse }
        let lines = headText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { throw ScriptableHTTPError.parse }
        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else { throw ScriptableHTTPError.parse }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name.lowercased()] = String(value)
        }
        if headers["expect"]?.lowercased().contains("100-continue") == true {
            _ = try POSIXSockets.send(fd, Data("HTTP/1.1 100 Continue\r\n\r\n".utf8))
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        while rest.count < length {
            rest.append(try POSIXSockets.recv(fd, max: min(4096, length - rest.count)))
        }
        let body = rest.prefix(length)
        return Request(
            method: String(parts[0]),
            target: String(parts[1]),
            headers: headers,
            body: Data(body)
        )
    }

    private func writeResponse(fd: Int32, script: Script) throws {
        var headers = script.headers
        headers["Connection"] = "close"
        let payload: Data
        if let chunk = script.chunkSize, chunk > 0 {
            headers["Transfer-Encoding"] = "chunked"
            headers.removeValue(forKey: "Content-Length")
            payload = chunked(script.body, size: chunk)
        } else {
            headers["Content-Length"] = String(script.body.count)
            payload = script.body
        }
        var head = "HTTP/1.1 \(script.status) \(script.reason)\r\n"
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"
        var outgoing = Data(head.utf8)
        outgoing.append(payload)
        if let limit = script.closeAfterBodyBytes {
            let headerCount = Data(head.utf8).count
            let keep = min(outgoing.count, headerCount + max(0, limit))
            try send(fd: fd, Data(outgoing.prefix(keep)), pace: script.slowLorisNanosecondsPerByte)
            POSIXSockets.shutdown(fd)
            return
        }
        try send(fd: fd, outgoing, pace: script.slowLorisNanosecondsPerByte)
    }

    private func send(fd: Int32, _ data: Data, pace: UInt64) throws {
        if pace == 0 {
            _ = try POSIXSockets.send(fd, data)
            return
        }
        for byte in data {
            _ = try POSIXSockets.send(fd, Data([byte]))
            var spec = timespec(
                tv_sec: Int(pace / 1_000_000_000),
                tv_nsec: Int(pace % 1_000_000_000)
            )
            _ = nanosleep(&spec, nil)
        }
    }

    private func chunked(_ data: Data, size: Int) -> Data {
        var out = Data()
        var offset = 0
        while offset < data.count {
            let end = min(offset + size, data.count)
            let slice = data.subdata(in: offset..<end)
            out.append(Data(String(slice.count, radix: 16).utf8))
            out.append(Data("\r\n".utf8))
            out.append(slice)
            out.append(Data("\r\n".utf8))
            offset = end
        }
        out.append(Data("0\r\n\r\n".utf8))
        return out
    }
}

public enum ScriptableHTTPError: Error {
    case bind
    case parse
    case closed
}

private enum HTTPStatus {
    static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 302: return "Found"
        case 401: return "Unauthorized"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        default: return "Response"
        }
    }
}

private enum POSIXSockets {
    static func close(_ fd: Int32) {
        #if canImport(Darwin)
        _ = Darwin.close(fd)
        #else
        _ = Glibc.close(fd)
        #endif
    }

    static func shutdown(_ fd: Int32) {
        #if canImport(Darwin)
        _ = Darwin.shutdown(fd, SHUT_RDWR)
        #else
        _ = Glibc.shutdown(fd, Int32(SHUT_RDWR))
        #endif
    }

    static func recv(_ fd: Int32, max: Int) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: max)
        let n = buffer.withUnsafeMutableBytes { raw in
            #if canImport(Darwin)
            Darwin.recv(fd, raw.baseAddress, raw.count, 0)
            #else
            Glibc.recv(fd, raw.baseAddress, raw.count, 0)
            #endif
        }
        if n == 0 { throw ScriptableHTTPError.closed }
        if n < 0 { throw ScriptableHTTPError.closed }
        return Data(buffer.prefix(Int(n)))
    }

    static func send(_ fd: Int32, _ data: Data) throws -> Int {
        try data.withUnsafeBytes { raw in
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
                if n <= 0 { throw ScriptableHTTPError.closed }
                sent += n
            }
            return sent
        }
    }
}

private func posixHtonl(_ value: UInt32) -> in_addr_t {
    in_addr_t(value.bigEndian)
}

private func posixNtohs(_ value: in_port_t) -> UInt16 {
    UInt16(bigEndian: UInt16(value))
}
