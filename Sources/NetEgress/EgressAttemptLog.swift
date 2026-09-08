import Foundation

/// One attributable network action (R-52). Health values never appear here.
public struct EgressAttempt: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case http
        case byteStream
        case discovery
    }

    public var kind: Kind
    public var host: String

    public init(kind: Kind, host: String) {
        self.kind = kind
        self.host = host
    }
}

/// Opt-in recorder. Production and uninstrumented tests leave `recorder` nil.
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

    @TaskLocal public static var recorder: Recorder?

    public static func record(kind: EgressAttempt.Kind, host: String) {
        recorder?.append(EgressAttempt(kind: kind, host: host))
    }
}
