// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// One attributable network action (R-52). Health values never appear here.
public struct EgressAttempt: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable, Codable {
        case http
        case byteStream
        case discovery
    }

    public var kind: Kind
    public var host: String
    public var bytes: Int

    public init(kind: Kind, host: String, bytes: Int = 0) {
        self.kind = kind
        self.host = host
        self.bytes = bytes
    }
}

/// UX-49: one row per host this process has contacted, with counts and first/last seen.
public struct NetworkActivityRow: Sendable, Equatable, Codable {
    public var host: String
    public var kinds: [String]
    public var count: Int
    public var bytes: Int
    public var firstSeenEpoch: TimeInterval
    public var lastSeenEpoch: TimeInterval

    public init(
        host: String,
        kinds: [String],
        count: Int,
        bytes: Int,
        firstSeenEpoch: TimeInterval,
        lastSeenEpoch: TimeInterval
    ) {
        self.host = host
        self.kinds = kinds
        self.count = count
        self.bytes = bytes
        self.firstSeenEpoch = firstSeenEpoch
        self.lastSeenEpoch = lastSeenEpoch
    }
}

/// Opt-in in-memory recorder plus an optional durable store the app attaches at launch.
public enum EgressAttemptLog {
    public final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var attempts: [EgressAttempt] = []

        public init() {}

        public func append(_ attempt: EgressAttempt) {
            lock.lock()
            attempts.append(attempt)
            lock.unlock()
        }

        public func snapshot() -> [EgressAttempt] {
            lock.lock()
            defer { lock.unlock() }
            return attempts
        }
    }

    public final class PersistentStore: @unchecked Sendable {
        private let lock = NSLock()
        private let url: URL
        private let nowEpoch: @Sendable () -> TimeInterval
        private var rows: [String: NetworkActivityRow]

        public init(url: URL, nowEpoch: @escaping @Sendable () -> TimeInterval) {
            self.url = url
            self.nowEpoch = nowEpoch
            self.rows = Self.load(url: url)
        }

        public func record(kind: EgressAttempt.Kind, host: String, bytes: Int) {
            let now = nowEpoch()
            lock.lock()
            defer { lock.unlock() }
            var row = rows[host] ?? NetworkActivityRow(
                host: host,
                kinds: [],
                count: 0,
                bytes: 0,
                firstSeenEpoch: now,
                lastSeenEpoch: now
            )
            if !row.kinds.contains(kind.rawValue) {
                row.kinds.append(kind.rawValue)
            }
            row.count += 1
            row.bytes += max(0, bytes)
            row.lastSeenEpoch = now
            rows[host] = row
            persistLocked()
        }

        public func snapshot() -> [NetworkActivityRow] {
            lock.lock()
            defer { lock.unlock() }
            return rows.values.sorted { $0.host < $1.host }
        }

        public func removeFile() {
            lock.lock()
            rows = [:]
            lock.unlock()
            try? FileManager.default.removeItem(at: url)
        }

        private func persistLocked() {
            let payload = Array(rows.values).sorted { $0.host < $1.host }
            guard let data = try? JSONEncoder().encode(payload) else { return }
            try? data.write(to: url, options: .atomic)
        }

        private static func load(url: URL) -> [String: NetworkActivityRow] {
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([NetworkActivityRow].self, from: data)
            else {
                return [:]
            }
            return Dictionary(uniqueKeysWithValues: decoded.map { ($0.host, $0) })
        }
    }

    @TaskLocal public static var recorder: Recorder?

    private final class PersistentBox: @unchecked Sendable {
        let lock = NSLock()
        var store: PersistentStore?
    }

    private static let persistent = PersistentBox()

    public static func attachPersistent(_ store: PersistentStore) {
        persistent.lock.lock()
        persistent.store = store
        persistent.lock.unlock()
    }

    public static func persistentSnapshot() -> [NetworkActivityRow] {
        persistent.lock.lock()
        let store = persistent.store
        persistent.lock.unlock()
        return store?.snapshot() ?? []
    }

    public static func wipePersistent() {
        persistent.lock.lock()
        persistent.store?.removeFile()
        persistent.lock.unlock()
    }

    public static func record(kind: EgressAttempt.Kind, host: String, bytes: Int = 0) {
        let attempt = EgressAttempt(kind: kind, host: host, bytes: bytes)
        recorder?.append(attempt)
        persistent.lock.lock()
        let store = persistent.store
        persistent.lock.unlock()
        store?.record(kind: kind, host: host, bytes: bytes)
    }

    /// UX-49 honesty line. The list is corroboration, not an independent capture.
    public static func selfReportedCaveat(sourceCommit: String) -> String {
        "This is what the app records about its own network use. For an independent check, the source is at \(sourceCommit) and you can watch the traffic with a proxy."
    }

    public static let sectionTitle = "Network activity (self-reported)"
    public static let emptyCopy = "No hosts recorded yet."
}
