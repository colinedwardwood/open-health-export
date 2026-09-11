import Foundation
import WireFormat

/// W3C Trace Context `traceparent` (R-54 / OBS-16). Never `tracestate` or `baggage`.
public enum Traceparent {
    public static let headerName = "traceparent"
    public static let forbiddenHeaderNames: Set<String> = ["tracestate", "baggage"]

    public static func make(seed: String) -> String {
        let digest = ContentSHA256.bytes(Data(seed.utf8))
        let trace = hex(digest.prefix(16))
        let span = hex(digest.suffix(8))
        return "00-\(trace)-\(span)-01"
    }

    /// Inbound headers are dropped. A Mac companion or local listener starts a new root.
    public static func root(seed: String, ignoringInbound inbound: String?) -> String {
        _ = inbound
        return make(seed: seed)
    }

    public static func isWellFormed(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "00" else { return false }
        guard parts[1].count == 32, parts[2].count == 16, parts[3].count == 2 else { return false }
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        for part in parts.dropFirst() {
            if part.unicodeScalars.contains(where: { !hex.contains($0) }) {
                return false
            }
        }
        return true
    }

    public static func isHeaderPlausibleFailure(_ error: Error) -> Bool {
        if let egress = error as? EgressError {
            switch egress {
            case .httpStatus(let status), .httpRetryAfter(status: let status, seconds: _):
                return status == 400 || status == 403 || status == 431
            case .transport:
                return true
            default:
                return false
            }
        }
        return false
    }

    public static func stripForbidden(_ headers: [String: String]) -> [String: String] {
        var copy = headers
        for key in headers.keys {
            let lower = key.lowercased()
            if forbiddenHeaderNames.contains(lower) || lower == headerName {
                copy.removeValue(forKey: key)
            }
        }
        return copy
    }

    private static func hex(_ bytes: Data.SubSequence) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// Shared across HTTPSSink copies so a successful no-header retry disables later posts.
public final class TraceparentEmission: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Bool
    public private(set) var autoDisabled = false

    public init(enabled: Bool) {
        self.enabled = enabled
    }

    public func header(seed: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard enabled else { return nil }
        return Traceparent.make(seed: seed)
    }

    public func noteAutoDisabled() {
        lock.lock()
        enabled = false
        autoDisabled = true
        lock.unlock()
    }
}
