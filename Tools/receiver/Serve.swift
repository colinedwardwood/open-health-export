// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import WireFormat

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum ReceiverServer {
    static func run(arguments: [String]) throws {
        var port: UInt16 = 8080
        var seed: String?
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--port":
                guard index + 1 < arguments.count, let parsed = UInt16(arguments[index + 1]), parsed > 0 else {
                    throw ServerError.usage
                }
                port = parsed
                index += 2
            case "--seed":
                guard index + 1 < arguments.count else { throw ServerError.usage }
                seed = arguments[index + 1]
                index += 2
            default:
                throw ServerError.usage
            }
        }
        var receiver = ReferenceReceiver()
        if let seed {
            let text = try String(contentsOf: URL(fileURLWithPath: seed), encoding: .utf8)
            try receiver.ingest(ndjson: text)
        }
        let lock = NSLock()
        let fd = try bindListen(port: port)
        FileHandle.standardError.write(Data("receiver listening on 0.0.0.0:\(port)\n".utf8))
        while true {
            var addr = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let client = withUnsafeMutablePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(fd, $0, &len)
                }
            }
            if client < 0 { continue }
            handle(client: client, lock: lock, receiver: &receiver)
        }
    }

    static func handle(client fd: Int32, lock: NSLock, receiver: inout ReferenceReceiver) {
        defer { _ = close(fd) }
        do {
            let request = try readRequest(fd: fd)
            let path = request.target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? request.target
            let method = request.method.uppercased()
            let status: Int
            let contentType: String
            let body: Data
            if method == "GET", path == "/health" {
                status = 200
                contentType = "text/plain; charset=utf-8"
                body = Data("ok\n".utf8)
            } else if method == "GET", path == "/metrics" {
                lock.lock()
                let text = receiver.prometheusExposition()
                lock.unlock()
                status = 200
                contentType = "text/plain; version=0.0.4; charset=utf-8"
                body = Data(text.utf8)
            } else if method == "GET", path == "/state" {
                lock.lock()
                let state = receiver.expectedState()
                lock.unlock()
                status = 200
                contentType = "application/json"
                body = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
            } else if method == "POST", path == "/ingest" || path == "/" {
                let ndjson = String(decoding: request.body, as: UTF8.self)
                lock.lock()
                defer { lock.unlock() }
                do {
                    try receiver.ingest(ndjson: ndjson)
                    status = 204
                    contentType = "text/plain"
                    body = Data()
                } catch {
                    status = 400
                    contentType = "text/plain; charset=utf-8"
                    body = Data("invalid ndjson\n".utf8)
                }
            } else {
                status = 404
                contentType = "text/plain; charset=utf-8"
                body = Data("not found\n".utf8)
            }
            try writeResponse(fd: fd, status: status, contentType: contentType, body: body)
        } catch {
            return
        }
    }

    static func bindListen(port: UInt16) throws -> Int32 {
        #if os(Linux)
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        guard fd >= 0 else { throw ServerError.bind }
        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        #if os(Linux)
        addr.sin_family = sa_family_t(AF_INET)
        #else
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        #endif
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: 0)
        let bindStatus = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindStatus == 0, listen(fd, 16) == 0 else {
            _ = close(fd)
            throw ServerError.bind
        }
        return fd
    }

    static func readRequest(fd: Int32) throws -> (method: String, target: String, body: Data) {
        var buffer = Data()
        let separator = Data("\r\n\r\n".utf8)
        while buffer.range(of: separator) == nil {
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = chunk.withUnsafeMutableBytes { raw in
                recv(fd, raw.baseAddress, raw.count, 0)
            }
            if n <= 0 { throw ServerError.closed }
            buffer.append(contentsOf: chunk.prefix(Int(n)))
            if buffer.count > 32_000_000 { throw ServerError.closed }
        }
        guard let split = buffer.range(of: separator) else { throw ServerError.closed }
        let head = buffer.subdata(in: buffer.startIndex..<split.lowerBound)
        var rest = buffer.subdata(in: split.upperBound..<buffer.endIndex)
        guard let headText = String(data: head, encoding: .utf8) else { throw ServerError.closed }
        let lines = headText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { throw ServerError.closed }
        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else { throw ServerError.closed }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = String(value)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        while rest.count < length {
            var chunk = [UInt8](repeating: 0, count: min(4096, length - rest.count))
            let n = chunk.withUnsafeMutableBytes { raw in
                recv(fd, raw.baseAddress, raw.count, 0)
            }
            if n <= 0 { throw ServerError.closed }
            rest.append(contentsOf: chunk.prefix(Int(n)))
        }
        return (String(parts[0]), String(parts[1]), Data(rest.prefix(length)))
    }

    static func writeResponse(fd: Int32, status: Int, contentType: String, body: Data) throws {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 204: reason = "No Content"
        case 400: reason = "Bad Request"
        default: reason = "Not Found"
        }
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Connection: close\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n\r\n"
        var outgoing = Data(head.utf8)
        outgoing.append(body)
        try outgoing.withUnsafeBytes { raw in
            var sent = 0
            let total = raw.count
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            while sent < total {
                let n = send(fd, base + sent, total - sent, 0)
                if n <= 0 { throw ServerError.closed }
                sent += n
            }
        }
    }
}

enum ServerError: Error {
    case usage
    case bind
    case closed
}
