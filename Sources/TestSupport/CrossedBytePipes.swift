// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import NetEgress

/// Two `ByteStream`s whose send on one is receive on the other. Linux-testable companion transfer.
public actor CrossedBytePipes {
    private var leftOut = Data()
    private var rightOut = Data()
    private var leftWait: [CheckedContinuation<Data, Error>] = []
    private var rightWait: [CheckedContinuation<Data, Error>] = []

    public init() {}

    public func left() -> any ByteStream {
        End(
            write: { try await self.writeLeft($0) },
            read: { try await self.readLeft(max: $0) }
        )
    }

    public func right() -> any ByteStream {
        End(
            write: { try await self.writeRight($0) },
            read: { try await self.readRight(max: $0) }
        )
    }

    private func writeLeft(_ data: Data) {
        if rightWait.isEmpty {
            rightOut.append(data)
        } else {
            rightWait.removeFirst().resume(returning: data)
        }
    }

    private func writeRight(_ data: Data) {
        if leftWait.isEmpty {
            leftOut.append(data)
        } else {
            leftWait.removeFirst().resume(returning: data)
        }
    }

    private func readLeft(max: Int) async throws -> Data {
        if !leftOut.isEmpty {
            let n = min(max, leftOut.count)
            let chunk = leftOut.prefix(n)
            leftOut.removeFirst(n)
            return Data(chunk)
        }
        return try await withCheckedThrowingContinuation { continuation in
            leftWait.append(continuation)
        }
    }

    private func readRight(max: Int) async throws -> Data {
        if !rightOut.isEmpty {
            let n = min(max, rightOut.count)
            let chunk = rightOut.prefix(n)
            rightOut.removeFirst(n)
            return Data(chunk)
        }
        return try await withCheckedThrowingContinuation { continuation in
            rightWait.append(continuation)
        }
    }
}

private struct End: ByteStream {
    let write: @Sendable (Data) async throws -> Void
    let read: @Sendable (Int) async throws -> Data

    func open() async throws {}
    func close() async {}
    func identity() async -> TLSIdentity? { nil }
    func send(_ data: Data) async throws { try await write(data) }
    func receive(max: Int) async throws -> Data { try await read(max) }
}
