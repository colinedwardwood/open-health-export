// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if os(macOS)
import Foundation
import Network

/// The Mac is the only process allowed to listen (R-34). iOS compiles this file out.
public actor CompanionListener {
    private let service: BonjourService
    private let parameters: NWParameters
    private let queue = DispatchQueue(label: "app.openhealthexporter.companion.listen")
    private var listener: NWListener?
    private var waiters: [CheckedContinuation<any ByteStream, Error>] = []
    private var accepted: [any ByteStream] = []

    public init(service: BonjourService, preSharedKey: PreSharedKey) {
        self.service = service
        self.parameters = TLSParameters.preSharedKey(preSharedKey)
    }

    public func start() async throws {
        if listener != nil { return }
        let listener = try NWListener(using: parameters)
        listener.service = NWListener.Service(name: service.name, type: service.type, domain: service.domain)
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.take(connection) }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    /// Next inbound phone connection, already started.
    public func accept() async throws -> any ByteStream {
        if !accepted.isEmpty {
            return accepted.removeFirst()
        }
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume(throwing: StreamError.closedByPeer)
        }
    }

    private func take(_ connection: NWConnection) {
        let stream = AcceptedNWStream(connection: connection, queue: queue)
        Task {
            await stream.start()
            enqueue(stream)
        }
    }

    private func enqueue(_ stream: AcceptedNWStream) {
        if waiters.isEmpty {
            accepted.append(stream)
        } else {
            let waiter = waiters.removeFirst()
            waiter.resume(returning: stream)
        }
    }
}

actor AcceptedNWStream: ByteStream {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var started = false

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    func start() {
        guard !started else { return }
        started = true
        connection.start(queue: queue)
    }

    public func open() async throws {
        start()
    }

    public func close() async {
        connection.cancel()
    }

    public func identity() async -> TLSIdentity? { nil }

    public func send(_ data: Data) async throws {
        try await open()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: StreamError.transport(String(describing: error)))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    public func receive(max: Int) async throws -> Data {
        try await open()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: max) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: StreamError.transport(String(describing: error)))
                    return
                }
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                    return
                }
                if isComplete {
                    continuation.resume(throwing: StreamError.closedByPeer)
                    return
                }
                continuation.resume(returning: Data())
            }
        }
    }
}
#endif
