import CompanionWire
import Foundation
import SinkCompanion

public actor LoopbackCompanionBroker: CompanionBytePipe {
    private var receiver: CompanionReceiver
    private var remainder = Data()
    private var outbox = Data()
    private var waiters: [CheckedContinuation<Data, Error>] = []

    public init(installationID: String = "mac-receiver") {
        self.receiver = CompanionReceiver(installationID: installationID)
    }

    public func storedDigest(batchID: String) -> String? {
        receiver.storedDigest(batchID: batchID)
    }

    public func send(_ data: Data) async throws {
        remainder.append(data)
        while let decoded = try CompanionFrame.decodePrefix(remainder) {
            remainder.removeFirst(decoded.consumed)
            let message = try CompanionMessage.decode(decoded.frame)
            let replies = receiver.handle(message)
            for reply in replies {
                enqueue(try reply.encodedFrame())
            }
        }
    }

    public func receive(max: Int) async throws -> Data {
        if !outbox.isEmpty {
            let n = min(max, outbox.count)
            let chunk = outbox.prefix(n)
            outbox.removeFirst(n)
            return Data(chunk)
        }
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func enqueue(_ data: Data) {
        if waiters.isEmpty {
            outbox.append(data)
        } else {
            let waiter = waiters.removeFirst()
            waiter.resume(returning: data)
        }
    }
}
